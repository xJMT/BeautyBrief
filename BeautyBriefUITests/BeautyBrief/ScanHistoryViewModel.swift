import SwiftUI
import Combine

@MainActor
final class ScanHistoryViewModel: ObservableObject {

    @Published private(set) var scans: [ScanResult] = []
    private let storageKey = "beautybrief.scanhistory.v1"
    private let maxHistory = 100

    // Prevents loadAsync() from overwriting scans that were added while we were decoding.
    // Set to true by addScan() or clearAll() so that a stale load result is discarded.
    private var hasPendingWrites = false

    init() {
        // Load asynchronously so JSON decoding never blocks the main thread at launch.
        // `scans` starts empty; the History tab will be populated before the user
        // can navigate to it (decode completes in milliseconds).
        Task { await loadAsync() }
    }

    func addScan(_ result: ScanResult) {
        hasPendingWrites = true
        scans.insert(result, at: 0)
        if scans.count > maxHistory { scans = Array(scans.prefix(maxHistory)) }
        save()
    }

    func removeScan(id: UUID) {
        scans.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        hasPendingWrites = true
        scans = []
        save()
    }

    var recentScans: [ScanResult] { Array(scans.prefix(20)) }
    var scansWithAlerts: [ScanResult] { scans.filter { $0.hasAlerts } }

    private func save() {
        if let data = try? JSONEncoder().encode(scans) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // Decodes UserDefaults JSON on a background thread, then publishes on the main actor.
    // Guarded by hasPendingWrites: if addScan() or clearAll() ran while we were decoding,
    // the fresh in-memory state wins and the stale result is silently discarded.
    @MainActor
    private func loadAsync() async {
        let key = storageKey
        let loaded: [ScanResult] = await Task.detached(priority: .utility) {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let saved = try? JSONDecoder().decode([ScanResult].self, from: data)
            else { return [] }
            return saved
        }.value
        guard !hasPendingWrites else { return }
        scans = loaded
    }
}
