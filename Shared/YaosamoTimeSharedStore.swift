import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum YaosamoTimeSharedStore {
    static let appGroupID = "group.com.yaosamo.time"
    static let appBundleID = "com.yaosamo.time"
    static let persistedStateKey = "yaosamo_time.clock_store_state.v1"

    static var userDefaultsCandidates: [UserDefaults] {
        [
            UserDefaults(suiteName: appGroupID),
            UserDefaults(suiteName: appBundleID),
            .standard
        ].compactMap { $0 }
    }

    static func persistedClockStateData() -> Data? {
        for defaults in userDefaultsCandidates {
            if let data = defaults.data(forKey: persistedStateKey) {
                return data
            }
        }
        return nil
    }

    static func reloadAllWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

struct WidgetStoredZone: Identifiable, Decodable {
    let id: UUID
    let timeZone: String
    let title: String
    let subtitle: String
}

struct WidgetStoredClockState: Decodable {
    let zones: [WidgetStoredZone]
}
