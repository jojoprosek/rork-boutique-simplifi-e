import SwiftUI
import PhotosUI

struct ProductFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let product: Product?
    var barcode: String = ""

    @State private var draft = Product(name: "", category: "Épicerie", costPrice: 0, retailPrice: 0, wholesalePrice: 0)
    @State private var initialStock: Double = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var newCategory = ""

    private var complete: Bool { store.data.settings.mode == .complete }
    private var wholesale: Bool { store.data.settings.businessType != .retail }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ProductThumb(product: draft, size: 84)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(draft.photoData == nil ? "Ajouter une photo" : "Changer la photo", systemImage: "camera")
                    }
                }
            }
            Section("Produit") {
                TextField("Nom (ex. Riz parfumé 5 kg)", text: $draft.name)
                Picker("Catégorie", selection: $draft.category) {
                    ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    TextField("Nouvelle catégorie", text: $newCategory)
                    Button("Ajouter") {
                        let c = newCategory.trimmingCharacters(in: .whitespaces)
                        guard !c.isEmpty else { return }
                        draft.category = c; newCategory = ""
                    }
                    .disabled(newCategory.isEmpty)
                }
                HStack {
                    TextField("Code-barres", text: $draft.barcode).keyboardType(.numberPad)
                    Button { showScanner = true } label: { Image(systemName: "barcode.viewfinder") }
                        .buttonStyle(.borderless)
                    Button("Créer") { draft.barcode = generateBarcode() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                }
                if complete { TextField("Référence", text: $draft.reference) }
            }

            Section("Prix") {
                money("Prix d'achat", $draft.costPrice)
                money("Prix de vente (détail)", $draft.retailPrice)
                if wholesale { money("Prix de gros", $draft.wholesalePrice) }
                if draft.costPrice > 0 {
                    LabeledContent("Je gagne") {
                        Text("\(Fmt.money(draft.margin)) (\(Int(draft.marginPercent.rounded())) %)")
                            .foregroundStyle(draft.margin >= 0 ? Color.gain : Color.loss)
                    }
                    let suggested = (draft.costPrice * 1.25 / 25).rounded() * 25
                    Button("Prix conseillé : \(Fmt.money(suggested)) (+25 %)") { draft.retailPrice = suggested }
                        .font(.subheadline)
                }
            }

            Section {
                TextField("Unité (pièce, sachet, boîte…)", text: $draft.unitName)
                if wholesale {
                    TextField("Conditionnement (carton, sac…)", text: $draft.packName)
                    Stepper("1 \(draft.packName) = \(Fmt.qty(draft.packSize)) \(draft.unitName)", value: $draft.packSize, in: 1...1000)
                }
            } header: { Text("Unités") }

            if wholesale && complete {
                Section {
                    ForEach($draft.tiers) { $t in
                        HStack {
                            Text("Dès")
                            TextField("Qté", value: $t.minQty, format: .number).keyboardType(.numberPad).frame(width: 60)
                            Text(draft.unitName)
                            Spacer()
                            TextField("Prix", value: $t.price, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                    }
                    .onDelete { draft.tiers.remove(atOffsets: $0) }
                    Button("Ajouter un palier") {
                        draft.tiers.append(PriceTier(minQty: max(10, draft.packSize), price: draft.wholesalePrice))
                    }
                } header: { Text("Prix par quantité") } footer: { Text("Le prix baisse automatiquement quand on achète beaucoup.") }
            }

            Section("Stock") {
                if product == nil {
                    LabeledContent("Stock de départ") {
                        TextField("0", value: $initialStock, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                }
                Stepper("Alerte sous \(Fmt.qty(draft.lowStockAlert)) \(draft.unitName)", value: $draft.lowStockAlert, in: 0...10_000)
                Toggle("Favori (en haut de la vente)", isOn: $draft.isFavorite)
                TextField("Fournisseur habituel (facultatif)", text: Binding(
                    get: { draft.supplier ?? "" },
                    set: { draft.supplier = $0.isEmpty ? nil : $0 }))
                    .textInputAutocapitalization(.words)
            }
        }
        .navigationTitle(product == nil ? "Nouveau produit" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    if !wholesale { draft.wholesalePrice = draft.retailPrice }
                    if draft.wholesalePrice == 0 { draft.wholesalePrice = draft.retailPrice }
                    store.saveProduct(draft, initialStock: product == nil ? initialStock : nil)
                    dismiss()
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.retailPrice <= 0)
            }
        }
        .onAppear {
            if let product { draft = product } else {
                draft.lowStockAlert = store.data.settings.defaultLowStock
                draft.barcode = barcode
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
                draft.photoData = img.resized(maxSide: 600).jpegData(compressionQuality: 0.6)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            BarcodeScannerView { draft.barcode = $0 }
        }
    }

    private var allCategories: [String] {
        var set = Set(store.categories + ["Épicerie", "Boissons", "Hygiène", "Riz et céréales", "Huiles", "Divers"])
        set.insert(draft.category)
        return set.sorted()
    }

    private func money(_ label: String, _ value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
        }
    }

    /// Internal EAN-13 starting with 200 (in-store range) with a valid check digit.
    private func generateBarcode() -> String {
        var digits = [2, 0, 0] + (0..<9).map { _ in Int.random(in: 0...9) }
        let sum = digits.enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 1 : 3) }
        digits.append((10 - sum % 10) % 10)
        return digits.map(String.init).joined()
    }
}

extension UIImage {
    /// Shrinks photos so they stay light to store and sync.
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
