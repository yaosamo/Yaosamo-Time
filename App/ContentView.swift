//
//  ContentView.swift
//  Yaosamo Time
//
//  Created by Personal on 2/24/26.
//

import SwiftUI
import AppKit
import Combine

struct ZoneClock: Identifiable {
    let id: UUID
    let timeZone: String
    let title: String
    let subtitle: String

    init(id: UUID = UUID(), timeZone: String, title: String, subtitle: String) {
        self.id = id
        self.timeZone = timeZone
        self.title = title
        self.subtitle = subtitle
    }
}

@MainActor
final class ClockStore: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var selectedReference: HourReference?
    @Published private(set) var zones: [ZoneClock] = [
        ZoneClock(timeZone: "America/Los_Angeles", title: "Portland", subtitle: "United States, OR"),
        ZoneClock(timeZone: "America/Edmonton", title: "Calgary", subtitle: "Canada, AB"),
        ZoneClock(timeZone: "America/Chicago", title: "Houston", subtitle: "United States, TX"),
        ZoneClock(timeZone: "America/New_York", title: "Miami", subtitle: "United States, FL"),
        ZoneClock(timeZone: "Europe/Warsaw", title: "Warsaw", subtitle: "Poland")
    ]

    private var timer: Timer?

    init() {
        ensureDefaultSelection()
        Task {
            await hydrateViewerZoneFromServer()
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
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date).replacingOccurrences(of: " ", with: "")
    }

    func longTime(for timeZoneID: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }

    func shortTime(for timeZoneID: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    func dateLine(for timeZoneID: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneID)
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    func offsetLine(for timeZoneID: String, date: Date) -> String {
        guard let zone = TimeZone(identifier: timeZoneID) else { return timeZoneID }
        let seconds = zone.secondsFromGMT(for: date)
        let hours = seconds / 3600
        let minutes = abs(seconds / 60 % 60)
        let sign = hours >= 0 ? "+" : "-"
        return "GMT\(sign)\(abs(hours))" + (minutes == 0 ? "" : String(format: ":%02d", minutes))
    }

    func select(hour: Int, in zone: ZoneClock) {
        guard let referenceDate = referenceDate(for: zone.timeZone, localHour: hour, anchor: now) else { return }
        selectedReference = HourReference(sourceZoneID: zone.id, sourceTimeZone: zone.timeZone, localHour: hour, utcDate: referenceDate)
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
        return true
    }

    func removeZone(id: UUID) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
        let removed = zones.remove(at: index)

        guard !zones.isEmpty else {
            selectedReference = nil
            return
        }

        guard let selected = selectedReference, selected.sourceZoneID == removed.id else { return }

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
        }
    }

    private func ensureDefaultSelection() {
        guard let preferred = zones.first else { return }
        let hour = localHour(in: preferred.timeZone, at: now)
        select(hour: hour, in: preferred)
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
}

private struct ViewerResolvedZone {
    let timeZone: String
    let title: String
    let subtitle: String
}

private struct ViewerHourFormatResponse: Decodable {
    let city: String?
    let countryCode: String?
    let geoapifyPlace: ViewerGeoapifyPlace?
    let regionCode: String?
    let timeZone: String?
}

private struct ViewerGeoapifyPlace: Decodable {
    let title: String?
    let subtitle: String?
    let timeZone: String?
}

private struct GeoapifyAutocompleteResponse: Decodable {
    let results: [GeoapifyAutocompleteRawResult]?
}

private struct GeoapifyAutocompleteRawResult: Decodable {
    let addressLine1: String?
    let city: String?
    let country: String?
    let countryCode: String?
    let county: String?
    let formatted: String?
    let hamlet: String?
    let name: String?
    let region: String?
    let state: String?
    let stateCode: String?
    let stateDistrict: String?
    let suburb: String?
    let timezone: GeoapifyTimeZoneValue?
    let town: String?
    let village: String?

    enum CodingKeys: String, CodingKey {
        case addressLine1 = "address_line1"
        case city
        case country
        case countryCode = "country_code"
        case county
        case formatted
        case hamlet
        case name
        case region
        case state
        case stateCode = "state_code"
        case stateDistrict = "state_district"
        case suburb
        case timezone
        case town
        case village
    }
}

private enum GeoapifyTimeZoneValue: Decodable {
    case string(String)
    case object(GeoapifyTimeZoneObject)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        self = .object(try container.decode(GeoapifyTimeZoneObject.self))
    }
}

private struct GeoapifyTimeZoneObject: Decodable {
    let id: String?
    let name: String?
}

private struct GeoapifySearchResult: Identifiable, Equatable {
    let id: String
    let label: String
    let title: String
    let subtitle: String
    let timeZone: String
}

struct ContentView: View {
    @EnvironmentObject private var clockStore: ClockStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZoneControlRail()
                .environmentObject(clockStore)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(clockStore.zones) { zone in
                        ZoneColumnView(zone: zone, now: clockStore.now)
                            .environmentObject(clockStore)
                    }
                }
                .padding(.trailing, 22)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(width: 660, height: 600, alignment: .leading)
    }
}

#Preview {
    ContentView()
        .environmentObject(ClockStore())
}

private struct ZoneColumnView: View {
    @EnvironmentObject private var clockStore: ClockStore
    let zone: ZoneClock
    let now: Date

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            VStack(spacing: 2) {
                Text(zone.title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.3)
                    .foregroundStyle(Color.black.opacity(0.78))

                Text(zone.subtitle.uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .kerning(1.0)
                    .foregroundStyle(Color.black.opacity(0.32))
                    .lineLimit(1)

                Text(clockStore.shortTime(for: zone.timeZone, date: now))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .padding(.top, 1)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
                    clockStore.removeZone(id: zone.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.42))
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .help("Remove city")
                .offset(x: 4, y: -1)
            }

            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HourRowView(
                        zone: zone,
                        hour: hour,
                        projectedHour: clockStore.projectedHour(for: zone),
                        selectedSourceZoneID: clockStore.selectedReference?.sourceZoneID,
                        currentHour: clockStore.currentHour(for: zone),
                        currentMinute: clockStore.currentMinute(for: zone)
                    )
                    .environmentObject(clockStore)
                }
            }
        }
        .frame(width: 118, alignment: .top)
    }
}

struct HourReference {
    let sourceZoneID: UUID
    let sourceTimeZone: String
    let localHour: Int
    let utcDate: Date
}

private struct HourRowView: View {
    @EnvironmentObject private var clockStore: ClockStore

    let zone: ZoneClock
    let hour: Int
    let projectedHour: Int?
    let selectedSourceZoneID: UUID?
    let currentHour: Int
    let currentMinute: Int

    private var isProjected: Bool { projectedHour == hour }
    private var isSourceSelected: Bool { isProjected && selectedSourceZoneID == zone.id }
    private var isCurrentHour: Bool { currentHour == hour }

    var body: some View {
        Button {
            clockStore.select(hour: hour, in: zone)
        } label: {
            ZStack {
                if let highlightKind {
                    if highlightKind == .selected {
                        Rectangle()
                            .fill(selectionFillColor)
                            .frame(height: 14)
                            .padding(.horizontal, 4)
                    } else if highlightKind == .current {
                        Rectangle()
                            .fill(highlightKind.fillColor)
                            .frame(height: 1)
                            .padding(.horizontal, 4)
                            .offset(y: 7)
                            .opacity(currentBlinkOpacity)
                            .animation(.easeInOut(duration: 0.25), value: currentBlinkOpacity)
                    }
                }

                Text(formatHour(hour))
                    .font(.system(size: 12, weight: textWeight, design: .monospaced))
                    .kerning(0.4)
                    .foregroundStyle(textColor)
                    .opacity(textOpacity)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var highlightKind: HourHighlightKind? {
        if isProjected { return .selected }
        if isCurrentHour { return .current }
        return nil
    }

    private var textWeight: Font.Weight {
        if isSourceSelected { return .semibold }
        if isProjected || isCurrentHour { return .medium }
        return .regular
    }

    private var textOpacity: Double {
        if highlightKind != nil { return 1 }
        if isDayHour(hour) { return 0.78 }
        return 0.16
    }

    private var textColor: Color {
        if highlightKind == .current { return Color.black.opacity(0.78) }
        if isProjected && !isDayHour(hour) { return Color.white.opacity(0.96) }
        return Color.black.opacity(highlightKind == nil ? 1 : 0.92)
    }

    private var currentBlinkOpacity: Double {
        guard isCurrentHour else { return 1 }
        let second = Calendar.current.component(.second, from: clockStore.now)
        return second.isMultiple(of: 2) ? 1 : 0.28
    }

    private var selectionFillColor: Color {
        if isDayHour(hour) {
            return Color(red: 0.90, green: 0.76, blue: 0.02)
        }
        return Color(red: 99 / 255, green: 87 / 255, blue: 241 / 255)
    }
}

private enum HourHighlightKind {
    case selected
    case current

    var fillColor: Color {
        switch self {
        case .selected:
            return Color(red: 0.90, green: 0.76, blue: 0.02)
        case .current:
            return Color.black.opacity(0.28)
        }
    }
}

private struct ZoneControlRail: View {
    @EnvironmentObject private var clockStore: ClockStore
    @State private var isAddCityPresented = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            ControlCircleButton(symbol: "plus") {
                isAddCityPresented = true
            }
            .help("Add city")
            .popover(isPresented: $isAddCityPresented, arrowEdge: .trailing) {
                AddCityPopover(isPresented: $isAddCityPresented)
                    .environmentObject(clockStore)
            }

            ControlCircleButton(symbol: "link") {
                copyLinkToPasteboard()
            }
            .help("Copy link")

            Spacer(minLength: 0)
        }
        .frame(width: 24)
        .padding(.vertical, 10)
    }

    private func copyLinkToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareLinkString(), forType: .string)
    }

    private func shareLinkString() -> String {
        let payload = buildWhenThereSharePayload()
        guard let encodedState = encodeWhenThereState(payload) else {
            return "https://time.yaosamo.com/"
        }

        var components = URLComponents(string: "https://time.yaosamo.com/") ?? URLComponents()
        components.queryItems = [URLQueryItem(name: "state", value: encodedState)]
        return components.url?.absoluteString ?? "https://time.yaosamo.com/"
    }

    private func buildWhenThereSharePayload() -> WhenThereSharePayload {
        let indexedZones = clockStore.zones.enumerated().map { index, zone in
            WhenThereShareZone(
                id: "z\(index + 1)",
                timeZone: zone.timeZone,
                title: zone.title,
                subtitle: zone.subtitle
            )
        }

        let selected = clockStore.selectedReference.flatMap { selectedRef -> WhenThereShareSelected? in
            let matchedZoneID = clockStore.zones.enumerated().first(where: { _, zone in
                zone.id == selectedRef.sourceZoneID
            })?.offset

            return WhenThereShareSelected(
                zoneId: matchedZoneID.map { "z\($0 + 1)" },
                timeZone: selectedRef.sourceTimeZone,
                localHour: selectedRef.localHour
            )
        }

        return WhenThereSharePayload(zones: indexedZones, selected: selected)
    }

    private func encodeWhenThereState(_ payload: WhenThereSharePayload) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return nil }

        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct AddCityPopover: View {
    @EnvironmentObject private var clockStore: ClockStore
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var results: [GeoapifySearchResult] = []
    @State private var statusText = "Type at least 2 characters"
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var debugLine: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add City")
                .font(.system(size: 13, weight: .semibold))

            TextField("Search city...", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFieldFocused)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.85))
            } else if isSearching || results.isEmpty {
                Text(isSearching ? "Searching..." : statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let debugLine, !debugLine.isEmpty {
                Text(debugLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(results) { item in
                        Button {
                            let added = clockStore.addZone(
                                timeZone: item.timeZone,
                                title: item.title,
                                subtitle: item.subtitle
                            )
                            if added {
                                isPresented = false
                            } else {
                                errorText = "Unable to add city"
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text("\(item.subtitle) · \(item.timeZone)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 210)
        }
        .padding(12)
        .frame(width: 320)
        .task {
            isFieldFocused = true
        }
        .task(id: query) {
            await searchCities(for: query)
        }
    }

    private func searchCities(for rawQuery: String) async {
        errorText = nil
        debugLine = nil
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 2 else {
            isSearching = false
            results = []
            statusText = "Type at least 2 characters"
            return
        }

        do {
            try await Task.sleep(nanoseconds: 140_000_000)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        isSearching = true

        defer { isSearching = false }

        do {
            let outcome = try await fetchGeoapifyResults(query: trimmed)
            guard !Task.isCancelled else { return }
            results = outcome.results
            statusText = outcome.results.isEmpty ? "No city matches" : ""
            debugLine = "source: \(outcome.sourceHost)"
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            statusText = "Search unavailable"
            debugLine = error.localizedDescription
        }
    }

    private func fetchGeoapifyResults(query: String) async throws -> (results: [GeoapifySearchResult], sourceHost: String) {
        let bases = [
            "https://time.yaosamo.com",
            "https://when-there.vercel.app"
        ]

        var lastError: Error?
        var attemptNotes: [String] = []

        for base in bases {
            do {
                var components = URLComponents(string: "\(base)/api/geoapify-autocomplete")!
                components.queryItems = [
                    URLQueryItem(name: "text", value: query),
                    URLQueryItem(name: "limit", value: "8")
                ]

                let (data, response) = try await URLSession.shared.data(from: components.url!)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    attemptNotes.append("\(base): HTTP \(status)")
                    throw URLError(.badServerResponse)
                }

                let decoded = try JSONDecoder().decode(GeoapifyAutocompleteResponse.self, from: data)
                return (normalizeGeoapifyResults(decoded.results ?? []), URL(string: base)?.host ?? base)
            } catch {
                attemptNotes.append("\(base): \(error.localizedDescription)")
                lastError = error
                continue
            }
        }

        if !attemptNotes.isEmpty {
            throw NSError(
                domain: "GeoapifyAutocomplete",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: attemptNotes.joined(separator: " | ")]
            )
        }

        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private func normalizeGeoapifyResults(_ rawResults: [GeoapifyAutocompleteRawResult]) -> [GeoapifySearchResult] {
        var normalized: [GeoapifySearchResult] = []
        var seen = Set<String>()

        for item in rawResults {
            guard let timeZone = extractGeoapifyTimeZone(item), TimeZone(identifier: timeZone) != nil else { continue }

            let cityName = item.city ?? item.town ?? item.village ?? item.hamlet ?? item.suburb ?? item.name ?? item.addressLine1
            guard let cityName, !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let title = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = buildGeoSubtitle(item)
            let key = "\(title)|\(subtitle)|\(timeZone)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            normalized.append(
                GeoapifySearchResult(
                    id: key,
                    label: item.formatted ?? "\(title), \(subtitle)",
                    title: title,
                    subtitle: subtitle,
                    timeZone: timeZone
                )
            )
        }

        return normalized
    }

    private func extractGeoapifyTimeZone(_ item: GeoapifyAutocompleteRawResult) -> String? {
        guard let timezone = item.timezone else { return nil }
        switch timezone {
        case .string(let value):
            return value
        case .object(let object):
            return object.name ?? object.id
        }
    }

    private func buildGeoSubtitle(_ item: GeoapifyAutocompleteRawResult) -> String {
        let country = item.country ?? item.countryCode?.uppercased() ?? ""
        let region = item.stateCode ?? item.state ?? item.county ?? item.region ?? item.stateDistrict ?? ""
        if !country.isEmpty, !region.isEmpty { return "\(country), \(region)" }
        return !country.isEmpty ? country : (!region.isEmpty ? region : (item.formatted ?? ""))
    }
}

private struct ControlCircleButton: View {
    let symbol: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.white.opacity(isHovering ? 0.46 : 0.18))
                .overlay {
                    ZStack {
                        Circle()
                            .stroke(Color.black.opacity(isHovering ? 0.24 : 0.18), lineWidth: 1)

                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                }
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct WhenThereSharePayload: Encodable {
    let zones: [WhenThereShareZone]
    let selected: WhenThereShareSelected?
}

private struct WhenThereShareZone: Encodable {
    let id: String
    let timeZone: String
    let title: String
    let subtitle: String
}

private struct WhenThereShareSelected: Encodable {
    let zoneId: String?
    let timeZone: String
    let localHour: Int
}

private func formatHour(_ hour: Int) -> String {
    let period = hour >= 12 ? "PM" : "AM"
    let h = hour % 12 == 0 ? 12 : hour % 12
    return "\(h)\(hour < 10 ? " " : "") \(period)"
}

private func isDayHour(_ hour: Int) -> Bool {
    (6...21).contains(hour)
}
