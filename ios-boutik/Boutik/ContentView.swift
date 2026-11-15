import SwiftUI

enum AppTab: Hashable { case home, sell, products, clients, more }

enum QuickSheet: String, Identifiable {
    case expense, product, client, stockIn, income
    var id: String { rawValue }
}

@Observable
final class Router {
    var tab: AppTab = .home
    var sheet: QuickSheet?
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked = true
    @State private var backgroundedAt: Date?

    var body: some View {
        Group {
            if !store.data.settings.onboarded {
                OnboardingView()
                    .transition(.opacity)
            } else if locked && store.data.settings.pin != nil {
                LockView { withAnimation { locked = false } }
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.data.settings.onboarded)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                if let at = backgroundedAt,
                   Date().timeIntervalSince(at) > Double(store.data.settings.autoLockMinutes * 60) {
                    locked = true
                }
                backgroundedAt = nil
            default: break
            }
        }
    }
}

struct MainTabs: View {
    @Environment(Store.self) private var store
    @State private var router = Router()

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Accueil", systemImage: "house", value: AppTab.home) {
                HomeView()
            }
            Tab("Vendre", systemImage: "cart", value: AppTab.sell) {
                SellView()
            }
            Tab("Produits", systemImage: "shippingbox", value: AppTab.products) {
                ProductsView()
            }
            Tab("Clients", systemImage: "person.2", value: AppTab.clients) {
                ClientsView()
            }
            Tab("Plus", systemImage: "ellipsis", value: AppTab.more) {
                MoreView()
            }
        }
        .environment(router)
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                UndoToastView(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .expense: ExpenseFormView()
            case .income: IncomeFormView()
            case .product: NavigationStack { ProductFormView(product: nil) }
            case .client: NavigationStack { ClientFormView(client: nil) }
            case .stockIn: StockInPickerView()
            }
        }
    }
}

struct UndoToastView: View {
    @Environment(Store.self) private var store
    let toast: UndoToast

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.gain)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.darkButtonText)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Annuler") { store.undo() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.gain)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(Color.darkButton, in: .rect(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(5))
            store.dismissToast(toast)
        }
    }
}

/// Quick actions "+" menu shared by tab screens.
struct QuickActionsMenu: View {
    @Environment(Router.self) private var router

    var body: some View {
        Menu {
            Button { router.tab = .sell } label: { Label("Nouvelle vente", systemImage: "cart.badge.plus") }
            Button { router.sheet = .expense } label: { Label("Dépense", systemImage: "arrow.down.right") }
            Button { router.sheet = .income } label: { Label("Autre entrée d'argent", systemImage: "arrow.up.right") }
            Button { router.sheet = .product } label: { Label("Produit", systemImage: "shippingbox") }
            Button { router.sheet = .client } label: { Label("Client", systemImage: "person.badge.plus") }
            Button { router.sheet = .stockIn } label: { Label("Entrée de stock", systemImage: "tray.and.arrow.down") }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
        }
        .accessibilityLabel("Actions rapides")
    }
}
