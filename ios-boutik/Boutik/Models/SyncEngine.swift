import Foundation
import Network
import Observation

/// Watches the network and pushes the local operation journal.
/// The server endpoint is not connected yet: when online, the journal is
/// compressed into a batch and acknowledged locally (see docs/api-sync.md).
@Observable
final class SyncEngine {
    var isOnline = true
    var isExpensive = false
    var isSyncing = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private var loop: Task<Void, Never>?

    func start(store: Store) {
        self.store = store
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "boutik.network"))
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await self?.syncIfPossible()
            }
        }
    }

    var canSync: Bool {
        guard isOnline, let store else { return false }
        if store.data.settings.syncWifiOnly && isExpensive { return false }
        return true
    }

    func syncIfPossible() async {
        guard canSync, !isSyncing, let store, !store.data.pending.isEmpty else { return }
        isSyncing = true
        let batch = store.data.pending
        // Batch would be gzip-compressed and POSTed to /v1/sync/push here.
        try? await Task.sleep(for: .milliseconds(900))
        let sentIds = Set(batch.map(\.id))
        store.data.pending.removeAll { sentIds.contains($0.id) }
        store.data.lastSync = Date()
        isSyncing = false
    }
}
