import SwiftUI
import LocalAuthentication

struct LockView: View {
    @Environment(Store.self) private var store
    let onUnlock: () -> Void

    @State private var entered = ""
    @State private var shake = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.gain)
                .frame(width: 80, height: 80)
                .background(Color.gainSoft, in: .circle)
            Text(store.data.settings.businessName).font(.title2.bold()).foregroundStyle(Color.ink)
            Text("Entrez votre code").foregroundStyle(Color.inkSecondary)
            PinDots(count: entered.count)
                .modifier(ShakeEffect(animatableData: CGFloat(shake)))
            Spacer()
            PinPad(value: $entered, showBiometrics: store.data.settings.useBiometrics, onBiometrics: biometrics)
            Spacer().frame(height: 20)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .onChange(of: entered) { _, v in
            guard v.count == 4 else { return }
            if v == store.data.settings.pin {
                Haptics.success(); onUnlock()
            } else {
                Haptics.warning()
                withAnimation(.default) { shake += 1 }
                entered = ""
            }
        }
        .task { if store.data.settings.useBiometrics { biometrics() } }
    }

    private func biometrics() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Ouvrir votre boutique") { ok, _ in
            if ok { Task { @MainActor in onUnlock() } }
        }
    }
}

struct PinDots: View {
    let count: Int
    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<4) { i in
                Circle()
                    .fill(i < count ? Color.ink : Color.clear)
                    .overlay(Circle().strokeBorder(Color.ink, lineWidth: 2))
                    .frame(width: 16, height: 16)
            }
        }
    }
}

struct PinPad: View {
    @Binding var value: String
    var showBiometrics = false
    var onBiometrics: () -> Void = {}

    var body: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["bio", "0", "del"]]
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in keyView(key) }
                }
            }
        }
    }

    @ViewBuilder
    private func keyView(_ key: String) -> some View {
        switch key {
        case "bio":
            Button(action: onBiometrics) {
                Image(systemName: "faceid").font(.title2).frame(width: 76, height: 76)
            }
            .opacity(showBiometrics ? 1 : 0)
            .disabled(!showBiometrics)
            .accessibilityLabel("Face ID")
        case "del":
            Button { if !value.isEmpty { value.removeLast() } } label: {
                Image(systemName: "delete.left").font(.title2).frame(width: 76, height: 76)
            }
            .foregroundStyle(Color.ink)
            .accessibilityLabel("Effacer")
        default:
            Button {
                guard value.count < 4 else { return }
                Haptics.tap(); value.append(key)
            } label: {
                Text(key).font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .frame(width: 76, height: 76)
                    .background(Color.card, in: .circle)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Create or change the 4-digit code.
struct SetPinSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var first: String?
    @State private var entered = ""
    @State private var mismatch = false

    var body: some View {
        VStack(spacing: 24) {
            Text(first == nil ? "Choisissez un code à 4 chiffres" : "Confirmez le code")
                .font(.title3.bold()).foregroundStyle(Color.ink)
                .padding(.top, 30)
            if mismatch { Text("Les codes ne correspondent pas").foregroundStyle(Color.loss).font(.subheadline) }
            PinDots(count: entered.count)
            Spacer()
            PinPad(value: $entered)
            Button("Annuler") { dismiss() }.padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .onChange(of: entered) { _, v in
            guard v.count == 4 else { return }
            if let first {
                if first == v {
                    store.data.settings.pin = v
                    Haptics.success()
                    dismiss()
                } else {
                    mismatch = true; self.first = nil; entered = ""; Haptics.warning()
                }
            } else {
                first = v; entered = ""; mismatch = false
            }
        }
    }
}
