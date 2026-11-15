import SwiftUI

struct SubscriptionView: View {
    @Environment(Store.self) private var store
    @State private var yearly = false
    @State private var selected: Plan = .pro
    @State private var confirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                status

                Picker("Facturation", selection: $yearly) {
                    Text("Mensuel").tag(false)
                    Text("Annuel · 2 mois offerts").tag(true)
                }
                .pickerStyle(.segmented)

                ForEach(Plan.allCases) { plan in
                    Button { selected = plan; Haptics.tap() } label: { planCard(plan) }
                        .buttonStyle(PressableStyle())
                }

                Button {
                    confirm = true
                } label: {
                    Text(store.data.settings.plan == selected && !store.data.settings.subscriptionCancelled ? "Plan actuel" : "Choisir \(selected.label)")
                }
                .buttonStyle(BigButtonStyle(kind: .green))
                .disabled(store.data.settings.plan == selected && store.data.settings.billingYearly == yearly && !store.data.settings.subscriptionCancelled)

                Text("Paiement par mobile money ou carte. Sans engagement : vous pouvez arrêter quand vous voulez. Vos données restent sur votre téléphone même si l'abonnement s'arrête.")
                    .font(.footnote).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)

                if store.data.settings.plan != nil && !store.data.settings.subscriptionCancelled {
                    Button("Arrêter l'abonnement", role: .destructive) {
                        store.data.settings.subscriptionCancelled = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(16)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Abonnement")
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            selected = store.data.settings.plan ?? .pro
            yearly = store.data.settings.billingYearly
        }
        .alert("Passer à \(selected.label) ?", isPresented: $confirm) {
            Button("Annuler", role: .cancel) {}
            Button("Confirmer") {
                store.data.settings.plan = selected
                store.data.settings.billingYearly = yearly
                store.data.settings.subscriptionCancelled = false
                Haptics.success()
            }
        } message: {
            Text("\(Fmt.money(yearly ? selected.yearlyPrice : selected.monthlyPrice)) par \(yearly ? "an" : "mois").")
        }
    }

    private var status: some View {
        let s = store.data.settings
        return HStack(spacing: 14) {
            IconBadge(systemName: s.plan == nil ? "hourglass" : "checkmark.seal.fill",
                      tint: s.plan == nil ? .warn : .gain, fill: s.plan == nil ? .warnSoft : .gainSoft, size: 50)
            VStack(alignment: .leading, spacing: 4) {
                if let plan = s.plan, !s.subscriptionCancelled {
                    Text("Plan \(plan.label)").font(.headline)
                    Text("\(Fmt.money(s.billingYearly ? plan.yearlyPrice : plan.monthlyPrice)) / \(s.billingYearly ? "an" : "mois")")
                        .font(.subheadline).foregroundStyle(Color.inkSecondary)
                } else if s.subscriptionCancelled {
                    Text("Abonnement arrêté").font(.headline)
                    Text("Choisissez un plan pour continuer.").font(.subheadline).foregroundStyle(Color.inkSecondary)
                } else {
                    Text("Essai gratuit").font(.headline)
                    Text(store.trialDaysLeft > 0 ? "Encore \(store.trialDaysLeft) jours pour tout essayer." : "Votre essai est terminé.")
                        .font(.subheadline).foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
        }
        .card(radius: 26)
    }

    private func planCard(_ plan: Plan) -> some View {
        let isSel = selected == plan
        let price = yearly ? plan.yearlyPrice : plan.monthlyPrice
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(plan.label).font(.title3.bold()).foregroundStyle(Color.ink)
                if plan == .pro {
                    Text("Le plus choisi").font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Color.gain, in: .capsule)
                }
                Spacer()
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(isSel ? Color.gain : Color.hairline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.money(price)).font(.money(26, weight: .heavy)).foregroundStyle(Color.ink)
                Text(yearly ? "/ an" : "/ mois").foregroundStyle(Color.inkSecondary)
            }
            ForEach(plan.perks, id: \.self) { perk in
                Label(perk, systemImage: "checkmark").font(.subheadline).foregroundStyle(Color.ink)
            }
        }
        .card(radius: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSel ? Color.gain : .clear, lineWidth: 2)
        }
    }
}
