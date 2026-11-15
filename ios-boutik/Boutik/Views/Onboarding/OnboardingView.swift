import SwiftUI

struct OnboardingView: View {
    @Environment(Store.self) private var store
    @State private var step = 0
    @State private var settings = AppSettings()

    private let currencies = ["FCFA", "GNF", "CDF", "MAD", "DZD", "TND", "EUR", "XAF", "USD"]
    private let countries = ["Côte d'Ivoire", "Sénégal", "Mali", "Burkina Faso", "Cameroun", "Guinée", "Bénin", "Togo", "Niger", "RD Congo", "Maroc", "France", "Autre"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule().fill(i <= step ? Color.gain : Color.hairline).frame(height: 5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $step) {
                welcome.tag(0)
                shop.tag(1)
                start.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: step)
        }
        .background(Color.canvas.ignoresSafeArea())
        .onAppear { settings = store.data.settings; settings.businessName = ""; settings.ownerName = "" }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Color.gainSoft).frame(width: 180, height: 180)
                Image(systemName: "storefront.fill")
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(Color.gain)
            }
            Text("Boutik").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Color.ink)
            Text("Vendez, suivez votre stock et sachez chaque soir combien il vous reste. Même sans internet.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.inkSecondary)
                .padding(.horizontal, 28)
            VStack(alignment: .leading, spacing: 12) {
                bullet("cart.fill", "Vendre en 3 touches")
                bullet("shippingbox.fill", "Stock toujours juste")
                bullet("person.2.fill", "Savoir qui vous doit")
            }
            .padding(.top, 8)
            Spacer()
            Button("Commencer") { step = 1 }
                .buttonStyle(BigButtonStyle(kind: .dark))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, size: 36)
            Text(text).font(.headline).foregroundStyle(Color.ink)
        }
    }

    private var shop: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Votre boutique").font(.largeTitle.bold()).foregroundStyle(Color.ink)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Infos") {
                    TextField("Nom de la boutique", text: $settings.businessName)
                    TextField("Votre prénom", text: $settings.ownerName)
                    TextField("Téléphone", text: $settings.phone).keyboardType(.phonePad)
                }
                Section("Pays et monnaie") {
                    Picker("Pays", selection: $settings.country) { ForEach(countries, id: \.self) { Text($0) } }
                    Picker("Monnaie", selection: $settings.currency) { ForEach(currencies, id: \.self) { Text($0) } }
                }
                Section {
                    Picker("Je vends", selection: $settings.businessType) {
                        ForEach(BusinessType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: { Text("Je vends") } footer: { Text("Grossiste ou mixte : prix de gros, cartons et prix par quantité.") }
            }
            .scrollContentBackground(.hidden)
            Button("Continuer") { step = 2 }
                .buttonStyle(BigButtonStyle(kind: .dark))
                .disabled(settings.businessName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private var start: some View {
        VStack(spacing: 16) {
            Text("Comment voulez-vous commencer ?")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("Affichage").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSecondary)
                Picker("Mode", selection: $settings.mode) {
                    ForEach(AppMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.mode == .simple ? "L'essentiel seulement. Vous pourrez tout activer plus tard." : "Toutes les options : paliers de prix, références, rapports détaillés.")
                    .font(.footnote).foregroundStyle(Color.inkSecondary)
            }
            .card()

            Button { finish(demo: true) } label: {
                choice(icon: "sparkles", title: "Essayer avec une boutique exemple", sub: "Produits, clients et ventes déjà remplis pour découvrir.")
            }
            .buttonStyle(PressableStyle())

            Button { finish(demo: false) } label: {
                choice(icon: "plus.circle.fill", title: "Commencer avec ma boutique", sub: "Une boutique vide, prête pour vos produits.")
            }
            .buttonStyle(PressableStyle())

            Spacer()
            Text("14 jours d'essai gratuit. Sans carte bancaire.")
                .font(.footnote).foregroundStyle(Color.inkSecondary)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
    }

    private func choice(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                Text(sub).font(.subheadline).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.inkSecondary)
        }
        .card()
    }

    private func finish(demo: Bool) {
        var s = settings
        s.trialStart = Date()
        s.onboarded = true
        if demo {
            store.loadDemo()
            var merged = store.data.settings
            merged.businessName = s.businessName
            merged.ownerName = s.ownerName
            merged.phone = s.phone
            merged.country = s.country
            merged.currency = s.currency
            merged.businessType = s.businessType
            merged.mode = s.mode
            merged.onboarded = true
            store.data.settings = merged
        } else {
            store.startEmpty(keeping: s)
        }
        Haptics.success()
    }
}
