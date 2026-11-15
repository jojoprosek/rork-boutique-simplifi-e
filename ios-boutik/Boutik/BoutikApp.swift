import SwiftUI

@main
struct BoutikApp: App {
    @State private var store = Store()
    @State private var sync = SyncEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(sync)
                .preferredColorScheme(colorScheme)
                .dynamicTypeSize(store.data.settings.largeText ? .xxLarge ... .accessibility3 : .xSmall ... .accessibility2)
                .tint(.gain)
                .task { sync.start(store: store) }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.data.settings.theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
