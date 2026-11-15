import SwiftUI
import UIKit

/// Builds receipt text / PDF for a sale.
enum ReceiptBuilder {
    static func text(_ sale: Sale, settings: AppSettings) -> String {
        var t = "*\(settings.businessName)*\n"
        if !settings.phone.isEmpty { t += "Tél : \(settings.phone)\n" }
        t += "Reçu \(sale.numberLabel) · \(Fmt.full.string(from: sale.date))\n"
        t += "Client : \(sale.clientName)\n\n"
        for l in sale.lines {
            t += "\(Fmt.qty(l.quantity)) × \(l.name) : \(Fmt.money(l.total))\n"
        }
        if sale.globalDiscount > 0 { t += "Remise : −\(Fmt.money(sale.globalDiscount))\n" }
        t += "\n*Total : \(Fmt.money(sale.total))*\n"
        t += "Payé : \(Fmt.money(sale.paid))\n"
        if sale.remaining > 0 { t += "Reste à payer : \(Fmt.money(sale.remaining))\n" }
        t += "\n\(settings.receiptFooter)"
        return t
    }

    @MainActor
    static func pdf(_ sale: Sale, settings: AppSettings) -> URL? {
        let view = ReceiptPaper(sale: sale, settings: settings).frame(width: 300)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 300, height: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Recu-\(sale.numberLabel).pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }

    static func whatsappURL(phone: String?, text: String) -> URL? {
        let digits = (phone ?? "").filter(\.isNumber)
        var comps = URLComponents(string: digits.isEmpty ? "https://wa.me/" : "https://wa.me/\(digits)")
        comps?.queryItems = [URLQueryItem(name: "text", value: text)]
        return comps?.url
    }

    @MainActor
    static func print(url: URL, name: String) {
        let info = UIPrintInfo.printInfo()
        info.jobName = name
        info.outputType = .grayscale
        let c = UIPrintInteractionController.shared
        c.printInfo = info
        c.printingItem = url
        c.present(animated: true)
    }
}

/// 58/80 mm style paper receipt.
struct ReceiptPaper: View {
    let sale: Sale
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 2) {
                Text(settings.businessName).font(.system(size: 16, weight: .bold))
                if !settings.address.isEmpty { Text(settings.address).font(.system(size: 10)) }
                if !settings.phone.isEmpty { Text("Tél : \(settings.phone)").font(.system(size: 10)) }
            }
            .frame(maxWidth: .infinity)
            dashed
            Text("Reçu \(sale.numberLabel)").font(.system(size: 11, weight: .semibold))
            Text(Fmt.full.string(from: sale.date)).font(.system(size: 10))
            Text("Client : \(sale.clientName)").font(.system(size: 10))
            dashed
            ForEach(sale.lines) { l in
                HStack(alignment: .top) {
                    Text("\(Fmt.qty(l.quantity)) × \(l.name)").font(.system(size: 10))
                    Spacer()
                    Text(Fmt.amount(l.total)).font(.system(size: 10).monospacedDigit())
                }
            }
            if sale.globalDiscount > 0 {
                HStack { Text("Remise").font(.system(size: 10)); Spacer(); Text("−" + Fmt.amount(sale.globalDiscount)).font(.system(size: 10)) }
            }
            dashed
            HStack { Text("TOTAL").font(.system(size: 13, weight: .bold)); Spacer(); Text(Fmt.money(sale.total)).font(.system(size: 13, weight: .bold).monospacedDigit()) }
            HStack { Text("Payé").font(.system(size: 10)); Spacer(); Text(Fmt.money(sale.paid)).font(.system(size: 10)) }
            if sale.remaining > 0 {
                HStack { Text("Reste à payer").font(.system(size: 10, weight: .semibold)); Spacer(); Text(Fmt.money(sale.remaining)).font(.system(size: 10, weight: .semibold)) }
            }
            dashed
            Text(settings.receiptFooter).font(.system(size: 10)).frame(maxWidth: .infinity)
        }
        .foregroundStyle(.black)
        .padding(16)
        .background(.white)
    }

    private var dashed: some View {
        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.gray).frame(height: 1)
    }

    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)); return p
        }
    }
}

struct SaleSuccessView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let sale: Sale
    let change: Double
    let receipt: ReceiptChoice
    let onDone: () -> Void

    @State private var appeared = false
    @State private var pdfURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 96, height: 96)
                    .background(Color.gain, in: .circle)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                    .padding(.top, 24)
                Text("Vendu !").font(.largeTitle.bold()).foregroundStyle(Color.ink)
                Text(Fmt.money(sale.total)).font(.money(36, weight: .heavy)).foregroundStyle(Color.gain)

                if change > 0 {
                    VStack(spacing: 2) {
                        Text("Monnaie à rendre").font(.subheadline.weight(.semibold))
                        Text(Fmt.money(change)).font(.money(30, weight: .heavy))
                    }
                    .foregroundStyle(Color.gain)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color.gainSoft, in: .rect(cornerRadius: 20, style: .continuous))
                }
                if sale.remaining > 0 {
                    Text("\(Fmt.money(sale.remaining)) ajoutés à ce que \(sale.clientName) vous doit.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.loss)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color.lossSoft, in: .rect(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        receiptButton("Imprimer", icon: "printer") {
                            if let url = makePDF() { ReceiptBuilder.print(url: url, name: sale.numberLabel) }
                        }
                        receiptButton("WhatsApp", icon: "message") { sendWhatsApp() }
                        if let url = pdfURL {
                            ShareLink(item: url) {
                                receiptLabel("PDF", icon: "doc.richtext")
                            }
                        }
                    }
                }

                ReceiptPaper(sale: sale, settings: store.data.settings)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .padding(.horizontal, 30)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Nouvelle vente", action: onDone)
                .buttonStyle(BigButtonStyle(kind: .dark))
                .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
            pdfURL = ReceiptBuilder.pdf(sale, settings: store.data.settings)
            switch receipt {
            case .print: if let url = makePDF() { ReceiptBuilder.print(url: url, name: sale.numberLabel) }
            case .whatsapp: sendWhatsApp()
            default: break
            }
        }
    }

    private func makePDF() -> URL? {
        if let pdfURL { return pdfURL }
        let url = ReceiptBuilder.pdf(sale, settings: store.data.settings)
        pdfURL = url
        return url
    }

    private func sendWhatsApp() {
        let phone = store.client(sale.clientId)?.whatsapp
        if let url = ReceiptBuilder.whatsappURL(phone: phone, text: ReceiptBuilder.text(sale, settings: store.data.settings)) {
            openURL(url)
        }
    }

    private func receiptButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { receiptLabel(title, icon: icon) }.buttonStyle(PressableStyle())
    }

    private func receiptLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Color.card, in: .rect(cornerRadius: 18, style: .continuous))
    }
}
