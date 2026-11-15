import SwiftUI
import ContactsUI

struct ClientsView: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var onlyDebtors = false
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        summaryTile(title: "On me doit", value: store.totalOwedToMe, color: .gain, fill: .gainSoft)
                        summaryTile(title: "Clients", value: Double(store.data.clients.count), color: .ink, fill: .card, plain: true)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section {
                    Picker("Filtre", selection: $onlyDebtors) {
                        Text("Tous").tag(false)
                        Text("Me doivent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if clients.isEmpty {
                        EmptyStateView(icon: "person.2", title: "Aucun client", message: "Ajoutez vos clients pour suivre leurs achats et ce qu'ils vous doivent.")
                    }
                    ForEach(clients) { c in
                        NavigationLink { ClientDetailView(clientId: c.id) } label: { ClientRow(client: c) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas.ignoresSafeArea())
            .searchable(text: $search, prompt: "Chercher un client")
            .navigationTitle("Clients")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Nouveau client")
                }
            }
            .sheet(isPresented: $showNew) { NavigationStack { ClientFormView(client: nil) } }
            .safeAreaPadding(.bottom, 60)
        }
    }

    private var clients: [Client] {
        var list = store.data.clients
        if onlyDebtors { list = list.filter { store.clientBalance($0.id) > 0 } }
        let q = search.lowercased()
        if !q.isEmpty { list = list.filter { $0.name.lowercased().contains(q) || $0.phone.contains(q) } }
        return list.sorted { store.clientBalance($0.id) > store.clientBalance($1.id) }
    }

    private func summaryTile(title: String, value: Double, color: Color, fill: Color, plain: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
            Text(plain ? Fmt.qty(value) : Fmt.money(value)).font(.money(22, weight: .heavy)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .card(radius: 22, fill: fill, padding: 16)
    }
}

struct ClientRow: View {
    @Environment(Store.self) private var store
    let client: Client

    var body: some View {
        let owed = store.clientBalance(client.id)
        HStack(spacing: 12) {
            ClientAvatar(client: client, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name).font(.headline).foregroundStyle(Color.ink)
                Text(client.phone.isEmpty ? client.group.label : client.phone).font(.caption).foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            if owed > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.amount(owed)).font(.money(16)).foregroundStyle(Color.loss)
                    Text(store.isOverdue(client) ? "En retard" : "Me doit")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(store.isOverdue(client) ? Color.warn : Color.inkSecondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DebtorsView: View {
    @Environment(Store.self) private var store
    var body: some View {
        let debtors = store.data.clients.filter { store.clientBalance($0.id) > 0 }
            .sorted { store.clientBalance($0.id) > store.clientBalance($1.id) }
        List {
            Section {
                LabeledContent("Total") {
                    Text(Fmt.money(store.totalOwedToMe)).font(.money(20)).foregroundStyle(Color.gain)
                }
            }
            Section("Qui me doit") {
                if debtors.isEmpty { Text("Personne ne vous doit d'argent.").foregroundStyle(Color.inkSecondary) }
                ForEach(debtors) { c in
                    NavigationLink { ClientDetailView(clientId: c.id) } label: { ClientRow(client: c) }
                }
            }
        }
        .navigationTitle("On me doit")
        .toolbar(.hidden, for: .tabBar)
    }
}

struct ClientPickerView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: UUID?
    @State private var search = ""
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selected = nil; dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ClientAvatar(client: nil, size: 40)
                        Text("Client de passage").foregroundStyle(Color.ink)
                        Spacer()
                        if selected == nil { Image(systemName: "checkmark").foregroundStyle(Color.gain) }
                    }
                }
                ForEach(filtered) { c in
                    Button {
                        selected = c.id; Haptics.tap(); dismiss()
                    } label: {
                        HStack {
                            ClientRow(client: c)
                            if selected == c.id { Image(systemName: "checkmark").foregroundStyle(Color.gain) }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nom ou téléphone")
            .navigationTitle("Choisir le client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showNew = true } label: { Image(systemName: "person.badge.plus") }
                }
            }
            .sheet(isPresented: $showNew) {
                NavigationStack { ClientFormView(client: nil) { new in selected = new.id; dismiss() } }
            }
        }
    }

    private var filtered: [Client] {
        let q = search.lowercased()
        return store.data.clients.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.phone.contains(q) }
            .sorted { $0.name < $1.name }
    }
}

struct ClientFormView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let client: Client?
    var onSaved: ((Client) -> Void)? = nil

    @State private var draft = Client(name: "")
    @State private var showContacts = false

    var body: some View {
        Form {
            Section {
                Button { showContacts = true } label: {
                    Label("Choisir dans mes contacts", systemImage: "person.crop.circle.badge.plus")
                }
            }
            Section("Client") {
                TextField("Nom", text: $draft.name).textContentType(.name)
                TextField("Téléphone", text: $draft.phone).keyboardType(.phonePad)
                TextField("WhatsApp (si différent)", text: $draft.whatsapp).keyboardType(.phonePad)
                TextField("Adresse", text: $draft.address)
                Picker("Groupe de prix", selection: $draft.group) {
                    ForEach(ClientGroup.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Crédit") {
                LabeledContent("Limite de crédit") {
                    TextField("0", value: $draft.creditLimit, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                Stepper("Délai : \(draft.dueDays) jours", value: $draft.dueDays, in: 0...120, step: 1)
            }
            Section("Notes") {
                TextField("Notes", text: $draft.notes, axis: .vertical)
            }
        }
        .navigationTitle(client == nil ? "Nouveau client" : "Modifier")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    if draft.whatsapp.isEmpty { draft.whatsapp = draft.phone }
                    store.saveClient(draft)
                    onSaved?(draft)
                    dismiss()
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let client { draft = client } else {
                draft.creditLimit = 50_000
            }
        }
        .sheet(isPresented: $showContacts) {
            ContactPicker { name, phone in
                draft.name = name
                draft.phone = phone
            }
            .ignoresSafeArea()
        }
    }
}

struct ContactPicker: UIViewControllerRepresentable {
    let onPick: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let c = CNContactPickerViewController()
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String) -> Void
        init(onPick: @escaping (String, String) -> Void) { self.onPick = onPick }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            onPick(name, phone)
        }
    }
}
