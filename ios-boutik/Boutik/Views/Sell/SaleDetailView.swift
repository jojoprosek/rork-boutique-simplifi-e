import SwiftUI

struct SaleDetailView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let saleId: UUID

    @State private var askCancel = false
    @State private var reason = ""

    var body: some View {
        Group {
            if let sale = store.data.sales.first(where: { $0.id == saleId }) {
                content(sale)
            } else {
                EmptyStateView(icon: "receipt", title: "Vente introuvable", message: "")
            }
        }
        .background(Color.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
    }

    private func content(_ sale: Sale) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(sale.numberLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                        Spacer()
                        if sale.isCancelled {
                            Text("Annulée").font(.caption.weight(.bold)).foregroundStyle(Color.loss)
                                .padding(.horizontal, 10).padding(.vertical, 4).background(Color.lossSoft, in: .capsule)
                        } else if sale.remaining > 0 {
                            Text("À crédit").font(.caption.weight(.bold)).foregroundStyle(Color.warn)
                                .padding(.horizontal, 10).padding(.vertical, 4).background(Color.warnSoft, in: .capsule)
                        }
                    }
                    Text(Fmt.money(sale.total)).font(.money(36, weight: .heavy))
                        .foregroundStyle(sale.isCancelled ? Color.inkSecondary : Color.ink)
                        .strikethrough(sale.isCancelled)
                    Text("\(sale.clientName) · \(Fmt.full.string(from: sale.date))").font(.subheadline).foregroundStyle(Color.inkSecondary)
                    if sale.isCancelled && !sale.cancelReason.isEmpty {
                        Text("Motif : \(sale.cancelReason)").font(.footnote).foregroundStyle(Color.loss)
                    }
                }
                .card(radius: 26)

                VStack(spacing: 0) {
                    ForEach(sale.lines) { l in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name).font(.subheadline.weight(.semibold))
                                Text("\(Fmt.qty(l.quantity)) × \(Fmt.money(l.unitPrice))\(l.discount > 0 ? " − \(Fmt.amount(l.discount))" : "")")
                                    .font(.caption).foregroundStyle(Color.inkSecondary)
                            }
                            Spacer()
                            Text(Fmt.money(l.total)).font(.money(15))
                        }
                        .padding(.horizontal, 16).frame(minHeight: 54)
                        Divider().padding(.leading, 16)
                    }
                    if sale.globalDiscount > 0 { line("Remise", "−" + Fmt.money(sale.globalDiscount)) }
                    ForEach(Array(sale.payments.enumerated()), id: \.offset) { _, p in
                        line(p.method.label, Fmt.money(p.amount))
                    }
                    if sale.remaining > 0 { line("Reste à payer", Fmt.money(sale.remaining), color: .loss) }
                    line("Je gagne", Fmt.money(sale.total - sale.cost), color: .gain)
                }
                .background(Color.card, in: .rect(cornerRadius: 22, style: .continuous))

                HStack(spacing: 10) {
                    Button {
                        if let url = ReceiptBuilder.whatsappURL(phone: store.client(sale.clientId)?.whatsapp,
                                                                text: ReceiptBuilder.text(sale, settings: store.data.settings)) { openURL(url) }
                    } label: { Label("WhatsApp", systemImage: "message") }
                        .buttonStyle(BigButtonStyle(kind: .outline))
                    Button {
                        if let url = ReceiptBuilder.pdf(sale, settings: store.data.settings) { ReceiptBuilder.print(url: url, name: sale.numberLabel) }
                    } label: { Label("Imprimer", systemImage: "printer") }
                        .buttonStyle(BigButtonStyle(kind: .outline))
                }

                if !sale.isCancelled {
                    Button(role: .destructive) { askCancel = true } label: {
                        Label("Annuler cette vente", systemImage: "arrow.uturn.backward")
                            .font(.headline).foregroundStyle(Color.loss)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    Text("Le stock sera remis et l'annulation gardée dans l'historique.")
                        .font(.caption).foregroundStyle(Color.inkSecondary)
                }
            }
            .padding(16)
        }
        .navigationTitle("Vente")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Annuler la vente ?", isPresented: $askCancel) {
            TextField("Motif (obligatoire)", text: $reason)
            Button("Garder", role: .cancel) {}
            Button("Annuler la vente", role: .destructive) {
                store.cancelSale(sale, reason: reason.isEmpty ? "Sans motif" : reason)
                reason = ""
            }
        }
    }

    private func line(_ label: String, _ value: String, color: Color = .ink) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.inkSecondary)
            Spacer()
            Text(value).font(.money(15)).foregroundStyle(color)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).frame(minHeight: 46)
    }
}
