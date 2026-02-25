import SwiftUI
import Combine

@MainActor
final class ClockStore: ObservableObject {
    private static let persistedStateKey = "yaosamo_time.clock_store_state.v1"

    @Published private(set) var now = Date()
    @Published private(set) var selectedReference: HourReference?
    @Published private(set) var zones: [ZoneClock] = [
        ZoneClock(timeZone: "America/Los_Angeles", title: "Portland", subtitle: "United States, OR"),
        ZoneClock(timeZone: "America/Edmonton", title: "Calgary", subtitle: "Canada, AB"),
        ZoneClock(timeZone: "America/Chicago", title: "Houston", subtitle: "United States, TX"),
        ZoneClock(timeZone: "America/New_York", title: "Miami", subtitle: "United States, FL"),
        ZoneClock(timeZone: "Europe/Warsaw", title: "Warsaw", subtitle: "Poland")
    ]
    @Published private(set) var uses24HourClock = ClockStore.detectUses24HourClock()

    private var timer: Timer?

    init() {
        let restoredPersistedState = restorePersistedState()
        if !restoredPersistedState {
            applySystemDefaultZone()
            ensureDefaultSelection()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
    }

    deinit {
        timer?.invalidate()
    }

    var menuBarLabel: String {
        let warsaw = zones.last?.timeZone ?? TimeZone.current.identifier
        return compactTime(for: warsaw, date: now)
    }

    func compactTime(for timeZoneID: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = uses24HourClock ? "HH:mm" : "h:mm a"
        let output = formatter.string(from: date)
        return uses24HourClock ? output : output.replacingOccurrences(of: " ", with: "")
    }

    func shortTime(for timeZoneID: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = uses24HourClock ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    func formattedHourLabel(_ hour: Int) -> String {
        if uses24HourClock {
            return String(format: "%02d", hour)
        }
        let period = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h)\(hour < 10 ? " " : "") \(period)"
    }

    func select(hour: Int, in zone: ZoneClock) {
        guard let referenceDate = referenceDate(for: zone.timeZone, localHour: hour, anchor: now) else { return }
        selectedReference = HourReference(sourceZoneID: zone.id, sourceTimeZone: zone.timeZone, localHour: hour, utcDate: referenceDate)
        persistState()
    }

    func projectedHour(for zone: ZoneClock) -> Int? {
        guard let reference = selectedReference else { return nil }
        return localHour(in: zone.timeZone, at: reference.utcDate)
    }

    func currentHour(for zone: ZoneClock) -> Int {
        localHour(in: zone.timeZone, at: now)
    }

    func currentMinute(for zone: ZoneClock) -> Int {
        localMinute(in: zone.timeZone, at: now)
    }

    func resetToCurrentHour() {
        guard let preferred = zones.first else { return }
        let hour = localHour(in: preferred.timeZone, at: now)
        select(hour: hour, in: preferred)
    }

    @discardableResult
    func addZone(timeZone: String, title: String, subtitle: String) -> Bool {
        guard TimeZone(identifier: timeZone) != nil else { return false }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }

        let candidate = ZoneClock(
            timeZone: timeZone,
            title: normalizedTitle,
            subtitle: normalizedSubtitle
        )

        zones.append(candidate)
        persistState()
        return true
    }

    @discardableResult
    func replaceZone(id: UUID, timeZone: String, title: String, subtitle: String) -> Bool {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return false }
        guard TimeZone(identifier: timeZone) != nil else { return false }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return false }

        let previous = zones[index]
        zones[index] = ZoneClock(
            id: previous.id,
            timeZone: timeZone,
            title: normalizedTitle,
            subtitle: normalizedSubtitle
        )

        if let selected = selectedReference, selected.sourceZoneID == previous.id {
            selectedReference = HourReference(
                sourceZoneID: previous.id,
                sourceTimeZone: timeZone,
                localHour: selected.localHour,
                utcDate: referenceDate(for: timeZone, localHour: selected.localHour, anchor: now) ?? selected.utcDate
            )
        }

        persistState()
        return true
    }

    func removeZone(id: UUID) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
        let removed = zones.remove(at: index)

        guard !zones.isEmpty else {
            selectedReference = nil
            persistState()
            return
        }

        guard let selected = selectedReference, selected.sourceZoneID == removed.id else {
            persistState()
            return
        }

        let fallbackIndex = min(index, zones.count - 1)
        let fallbackZone = zones[fallbackIndex]
        if let utcDate = referenceDate(for: fallbackZone.timeZone, localHour: selected.localHour, anchor: now) {
            selectedReference = HourReference(
                sourceZoneID: fallbackZone.id,
                sourceTimeZone: fallbackZone.timeZone,
                localHour: selected.localHour,
                utcDate: utcDate
            )
        } else {
            ensureDefaultSelection()
            return
        }
        persistState()
    }

    func moveZone(id: UUID, toInsertionIndex insertionIndex: Int) {
        guard let fromIndex = zones.firstIndex(where: { $0.id == id }) else { return }

        var reordered = zones
        let moved = reordered.remove(at: fromIndex)
        let clampedTarget = max(0, min(insertionIndex, reordered.count))
        let adjustedTarget = insertionIndex > fromIndex ? max(0, clampedTarget - 1) : clampedTarget
        reordered.insert(moved, at: adjustedTarget)

        guard reordered.map(\.id) != zones.map(\.id) else { return }
        zones = reordered
        persistState()
    }

    private func ensureDefaultSelection() {
        guard let preferred = zones.first else { return }
        let hour = localHour(in: preferred.timeZone, at: now)
        select(hour: hour, in: preferred)
    }

    private func applySystemDefaultZone() {
        guard !zones.isEmpty else { return }
        let systemTimeZoneID = TimeZone.current.identifier
        guard TimeZone(identifier: systemTimeZoneID) != nil else { return }

        let previousFirst = zones[0]
        zones[0] = ZoneClock(
            id: previousFirst.id,
            timeZone: systemTimeZoneID,
            title: fallbackTitle(for: systemTimeZoneID),
            subtitle: systemDefaultSubtitle(for: systemTimeZoneID)
        )
    }

    private func systemDefaultSubtitle(for timeZoneID: String) -> String {
        let locale = Locale.current
        let regionCode = locale.region?.identifier.uppercased()
        let countryName = regionCode.flatMap { locale.localizedString(forRegionCode: $0) }
        if let countryName, let regionCode {
            return "\(countryName), \(regionCode)"
        }
        if let countryName { return countryName }
        if let regionCode { return regionCode }
        return fallbackSubtitle(for: timeZoneID)
    }

    private func hydrateViewerZoneFromServer() async {
        guard let url = URL(string: "https://time.yaosamo.com/api/viewer-hour-format") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let viewerContext = try JSONDecoder().decode(ViewerHourFormatResponse.self, from: data)
            applyViewerGeoapifyPlace(viewerContext)
        } catch {
            // Ignore network/decoding failures and keep local defaults.
        }
    }

    private func applyViewerGeoapifyPlace(_ viewerContext: ViewerHourFormatResponse) {
        guard !zones.isEmpty else { return }

        let viewerZone = buildViewerDefaultZone(from: viewerContext)
        guard let viewerZone else { return }

        let previousFirst = zones[0]
        zones[0] = ZoneClock(id: previousFirst.id, timeZone: viewerZone.timeZone, title: viewerZone.title, subtitle: viewerZone.subtitle)

        if let selected = selectedReference, selected.sourceZoneID == previousFirst.id {
            selectedReference = HourReference(
                sourceZoneID: previousFirst.id,
                sourceTimeZone: viewerZone.timeZone,
                localHour: selected.localHour,
                utcDate: referenceDate(for: viewerZone.timeZone, localHour: selected.localHour, anchor: now) ?? selected.utcDate
            )
        }
        persistState()
    }

    private func restorePersistedState() -> Bool {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.persistedStateKey) else { return false }
        guard let state = try? JSONDecoder().decode(PersistedClockStoreState.self, from: data) else { return false }
        guard !state.zones.isEmpty else { return false }

        zones = state.zones

        if
            let selected = state.selected,
            let selectedZone = zones.first(where: { $0.id == selected.sourceZoneID }),
            let utcDate = referenceDate(for: selectedZone.timeZone, localHour: selected.localHour, anchor: now)
        {
            selectedReference = HourReference(
                sourceZoneID: selectedZone.id,
                sourceTimeZone: selectedZone.timeZone,
                localHour: selected.localHour,
                utcDate: utcDate
            )
        } else {
            selectedReference = nil
            ensureDefaultSelection()
        }

        return true
    }

    private func persistState() {
        let state = PersistedClockStoreState(
            zones: zones,
            selected: selectedReference.map {
                PersistedSelectedReference(
                    sourceZoneID: $0.sourceZoneID,
                    localHour: $0.localHour
                )
            }
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.persistedStateKey)
    }

    private func buildViewerDefaultZone(from viewerContext: ViewerHourFormatResponse) -> ViewerResolvedZone? {
        if
            let geo = viewerContext.geoapifyPlace,
            let timeZone = geo.timeZone?.trimmingCharacters(in: .whitespacesAndNewlines),
            !timeZone.isEmpty,
            TimeZone(identifier: timeZone) != nil
        {
            return ViewerResolvedZone(
                timeZone: timeZone,
                title: nonEmpty(geo.title) ?? fallbackTitle(for: timeZone),
                subtitle: nonEmpty(geo.subtitle) ?? fallbackSubtitle(for: timeZone)
            )
        }

        guard
            let timeZone = nonEmpty(viewerContext.timeZone),
            TimeZone(identifier: timeZone) != nil
        else { return nil }

        let title = nonEmpty(viewerContext.city) ?? fallbackTitle(for: timeZone)
        let countryCode = nonEmpty(viewerContext.countryCode)?.uppercased()
        let regionCode = nonEmpty(viewerContext.regionCode)?.uppercased()
        let subtitle: String
        if let countryCode, let regionCode {
            subtitle = "\(countryCode), \(regionCode)"
        } else if let countryCode {
            subtitle = countryCode
        } else {
            subtitle = fallbackSubtitle(for: timeZone)
        }

        return ViewerResolvedZone(timeZone: timeZone, title: title, subtitle: subtitle)
    }

    private func fallbackTitle(for timeZoneID: String) -> String {
        timeZoneID.split(separator: "/").last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? timeZoneID
    }

    private func fallbackSubtitle(for timeZoneID: String) -> String {
        timeZoneID.split(separator: "/").dropLast().joined(separator: " / ").replacingOccurrences(of: "_", with: " ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func referenceDate(for timeZoneID: String, localHour: Int, anchor: Date) -> Date? {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = calendar.dateComponents([.year, .month, .day], from: anchor)
        components.hour = localHour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    private func localHour(in timeZoneID: String, at date: Date) -> Int {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date)
    }

    private func localMinute(in timeZoneID: String, at date: Date) -> Int {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.minute, from: date)
    }

    private static func detectUses24HourClock() -> Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return !template.contains("a")
    }
}
