import SwiftUI
import PhotosUI

/// Big amount entry used by money forms.
struct AmountField: View {
    @Binding var text: String
    var color: Color = .ink
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 4) {
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.money(44, weight: .heavy))
                .foregroundStyle(color)
                .focused($focused)
            Text(Fmt.currency).font(.headline).foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .onAppear { focused = true }
    }
}

struct AccountPicker: View {
    @Environment(Store.self) private var store
    @Binding var selection: UUID?
    var title = "Payé avec"

    var body: some View {
        Picker(title, selection: Binding(get: { selection ?? store.data.accounts.first?.id }, set: { selection = $0 })) {
            ForEach(store.data.accounts) { a in
                Text("\(a.name) · \(Fmt.money(store.balance(of: a)))").tag(Optional(a.id))
            }
        }
    }
}

struct ExpenseFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var category = "Transport"
    @State private var note = ""
    @State private var accountId: UUID?
    @State private var date = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section { AmountField(text: $amount, color: .loss) }
                    .listRowBackground(Color.clear)
                Section("Pour quoi ?") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Expense.categories, id: \.self) { c in
                                Button { category = c; Haptics.tap() } label: {
                                    Text(c).font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14).frame(height: 38)
                                        .foregroundStyle(category == c ? Color.darkButtonText : Color.ink)
                                        .background(category == c ? Color.darkButton : Color.chip, in: .capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    TextField("Note (facultatif)", text: $note)
                }
                Section {
                    AccountPicker(selection: $accountId)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photo == nil ? "Photo du reçu" : "Reçu ajouté", systemImage: photo == nil ? "camera" : "checkmark.circle.fill")
                    }
                }
            }
            .navigationTitle("Dépense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let acc = accountId ?? store.data.accounts.first?.id else { return }
                        store.addExpense(Expense(amount: Fmt.parse(amount), category: category, note: note, accountId: acc, date: date, receiptPhoto: photo))
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(Fmt.parse(amount) <= 0 || store.data.accounts.isEmpty)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let d = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                    photo = img.resized(maxSide: 900).jpegData(compressionQuality: 0.5)
                }
            }
        }
    }
}

struct IncomeFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var label = ""
    @State private var accountId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section { AmountField(text: $amount, color: .gain) }
                    .listRowBackground(Color.clear)
                Section {
                    TextField("D'où vient cet argent ? (apport, prêt…)", text: $label)
                    AccountPicker(selection: $accountId, title: "Reçu sur")
                } footer: { Text("Pour l'argent qui n'est pas une vente : apport personnel, prêt reçu, remboursement…") }
            }
            .navigationTitle("Entrée d'argent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let acc = accountId ?? store.data.accounts.first?.id else { return }
                        store.addIncome(Income(amount: Fmt.parse(amount), label: label.isEmpty ? "Entrée d'argent" : label, accountId: acc))
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(Fmt.parse(amount) <= 0 || store.data.accounts.isEmpty)
                }
            }
        }
    }
}

struct TransferFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var fromId: UUID?
    @State private var toId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section { AmountField(text: $amount) }.listRowBackground(Color.clear)
                Section {
                    AccountPicker(selection: $fromId, title: "De")
                    Picker("Vers", selection: $toId) {
                        Text("Choisir").tag(UUID?.none)
                        ForEach(store.data.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            .navigationTitle("Transfert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        guard let from = fromId ?? store.data.accounts.first?.id, let toId else { return }
                        store.addTransfer(Transfer(fromId: from, toId: toId, amount: Fmt.parse(amount)))
                        dismiss()
                    }
                    .disabled(Fmt.parse(amount) <= 0 || toId == nil || toId == (fromId ?? store.data.accounts.first?.id))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
