import Foundation
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class WidgetStateSyncController: ObservableObject {
    private static let appGroupID = "group.com.yaosamo.time"
    private static let persistedStateKey = "yaosamo_time.clock_store_state.v1"

    private var defaultsObserver: NSObjectProtocol?
    private var lastSyncedData: Data?

    init() {
        syncFromAppDefaultsIfNeeded()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromAppDefaultsIfNeeded()
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func syncFromAppDefaultsIfNeeded() {
        guard let appState = UserDefaults.standard.data(forKey: Self.persistedStateKey) else { return }
        guard appState != lastSyncedData else { return }

        lastSyncedData = appState
        UserDefaults(suiteName: Self.appGroupID)?
            .set(appState, forKey: Self.persistedStateKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
