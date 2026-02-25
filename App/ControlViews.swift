import SwiftUI
import AppKit

struct LeftRailGlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    // Lower the frosty white cast while preserving material distortion.
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.30), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05), radius: 7, x: 0, y: 4)

            content
                .padding(.vertical, 8)
        }
        .frame(width: width)
        .padding(.trailing, 2)
    }
}

struct ZoneControlRail: View {
    @EnvironmentObject private var clockStore: ClockStore
    let onCopyCelebration: () -> Void
    @State private var isAddCityPresented = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    init(onCopyCelebration: @escaping () -> Void = {}) {
        self.onCopyCelebration = onCopyCelebration
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            ControlCircleButton(symbol: "plus") {
                isAddCityPresented = true
            }
            .help("Add city")
            .popover(isPresented: $isAddCityPresented, arrowEdge: .trailing) {
                AddCityPopover(isPresented: $isAddCityPresented, mode: .add)
                    .environmentObject(clockStore)
            }

            ControlCircleButton(
                symbol: "link",
                activeSymbol: "checkmark",
                isActive: isCopyFeedbackVisible
            ) {
                copyLinkToPasteboard()
                showCopyFeedback()
                onCopyCelebration()
            }
            .help("Copy link")
        }
        .frame(width: 24)
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    private func copyLinkToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shareLinkString(), forType: .string)
    }

    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            isCopyFeedbackVisible = true
        }

        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    isCopyFeedbackVisible = false
                }
            }
        }
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

enum LocationPickerMode {
    case add
    case edit(zoneID: UUID, currentTitle: String)
}

struct AddCityPopover: View {
    @EnvironmentObject private var clockStore: ClockStore
    @Binding var isPresented: Bool
    let mode: LocationPickerMode

    @State private var query = ""
    @State private var results: [GeoapifySearchResult] = []
    @State private var statusText = "Type at least 2 characters"
    @State private var isSearching = false
    @State private var errorText: String?
    @FocusState private var isFieldFocused: Bool

    init(isPresented: Binding<Bool>, mode: LocationPickerMode = .add) {
        self._isPresented = isPresented
        self.mode = mode
        switch mode {
        case .add:
            self._query = State(initialValue: "")
        case .edit(_, let currentTitle):
            self._query = State(initialValue: currentTitle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titleText)
                .font(.system(size: 13, weight: .semibold))

            TextField(textFieldPlaceholder, text: $query)
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

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(results) { item in
                        Button {
                            let succeeded = submitSelection(item)
                            if succeeded {
                                isPresented = false
                            } else {
                                errorText = modeFailureText
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

    private var titleText: String {
        switch mode {
        case .add:
            return "Add City"
        case .edit:
            return "Edit Location"
        }
    }

    private var textFieldPlaceholder: String {
        switch mode {
        case .add:
            return "Search city..."
        case .edit:
            return "Replace city..."
        }
    }

    private var modeFailureText: String {
        switch mode {
        case .add:
            return "Unable to add city"
        case .edit:
            return "Unable to update city"
        }
    }

    private func submitSelection(_ item: GeoapifySearchResult) -> Bool {
        switch mode {
        case .add:
            return clockStore.addZone(
                timeZone: item.timeZone,
                title: item.title,
                subtitle: item.subtitle
            )
        case .edit(let zoneID, _):
            return clockStore.replaceZone(
                id: zoneID,
                timeZone: item.timeZone,
                title: item.title,
                subtitle: item.subtitle
            )
        }
    }

    private func searchCities(for rawQuery: String) async {
        errorText = nil
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
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            statusText = "Search unavailable"
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

struct ControlCircleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let activeSymbol: String?
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false

    init(symbol: String, activeSymbol: String? = nil, isActive: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.activeSymbol = activeSymbol
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            buttonFace
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var buttonFace: some View {
        Circle()
            .fill(.thinMaterial)
            .overlay { buttonOverlay }
            .frame(width: 24, height: 24)
            .scaleEffect(isHovering ? 1.02 : 1)
            .shadow(color: successColor.opacity(isActive ? 0.14 : 0), radius: 6, x: 0, y: 2)
    }

    private var buttonOverlay: some View {
        ZStack {
            Circle()
                .fill(glassTintFill)

            Circle()
                .stroke(glassHighlightStroke, lineWidth: 0.8)

            Circle()
                .stroke(borderColor, lineWidth: 1)

            iconOverlay
        }
    }

    @ViewBuilder
    private var iconOverlay: some View {
        if let activeSymbol {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
                .opacity(isActive ? 0 : 1)

            Image(systemName: activeSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activeIconColor)
                .opacity(isActive ? 1 : 0)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var backgroundFill: Color {
        .clear
    }

    private var borderColor: Color {
        if isActive {
            return successColor.opacity(0.55)
        }
        return colorScheme == .dark
            ? Color.white.opacity(isHovering ? 0.20 : 0.14)
            : Color.black.opacity(isHovering ? 0.18 : 0.12)
    }

    private var iconColor: Color {
        return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }

    private var activeIconColor: Color {
        successColor.opacity(colorScheme == .dark ? 0.96 : 0.86)
    }

    private var glassTintFill: Color {
        if isActive {
            return successColor.opacity(colorScheme == .dark ? 0.16 : 0.18)
        }
        return Color.white.opacity(colorScheme == .dark ? (isHovering ? 0.06 : 0.03) : (isHovering ? 0.16 : 0.10))
    }

    private var glassHighlightStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(isHovering ? 0.28 : 0.20)
            : Color.white.opacity(isHovering ? 0.62 : 0.52)
    }

    private var successColor: Color { Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255) }
}

struct FistBumpOverlayFullScreen: View {
    let startDate: Date

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let t = max(0, min(1, elapsed / 0.9))
                let overlayAlpha = keyframed(t, points: [(0.0, 0), (0.05, 1), (0.72, 1), (1.0, 0)])
                let veilAlpha = keyframed(t, points: [(0.0, 0), (0.14, 1), (0.75, 0.55), (1.0, 0)])
                let flashAlpha = keyframed(t, points: [(0.0, 0), (0.24, 0), (0.34, 1), (0.52, 0.35), (1.0, 0)])
                let flashScale = keyframed(t, points: [(0.0, 0.7), (0.24, 0.7), (0.34, 1.0), (0.52, 1.1), (1.0, 1.2)])
                let fistOpacity = keyframed(t, points: [(0.0, 0), (0.12, 1), (0.70, 1), (1.0, 0)])
                let leftRot = keyframed(t, points: [(0.0, -14), (0.36, -5), (0.44, -1), (0.50, -3), (0.70, -2), (1.0, -2)])
                let rightRot = keyframed(t, points: [(0.0, 14), (0.36, 5), (0.44, 1), (0.50, 3), (0.70, 2), (1.0, 2)])
                let fistScale = keyframed(t, points: [(0.0, 0.9), (0.36, 1.0), (0.44, 1.12), (0.50, 1.03), (0.70, 1.0), (1.0, 1.0)])

                let width = geometry.size.width
                let height = geometry.size.height
                let fistFont = min(max(width * 0.16, 72), 170)
                let baseBurst = min(width, height) * 0.36
                let centerShiftX = 0.0
                let startDistance = width * 0.25
                let leftEndX = -width * 0.07
                let rightEndX = width * 0.07
                let impactDistance = max(width * 0.008, 4)
                let overshootDistance = max(width * 0.02, 8)
                let leftX = keyframed(t, points: [
                    (0.0, -startDistance),
                    (0.36, -impactDistance),
                    (0.44, leftEndX + overshootDistance),
                    (0.50, leftEndX - (overshootDistance * 0.35)),
                    (0.70, leftEndX),
                    (1.0, leftEndX)
                ], easing: easeInQuad)
                let rightX = keyframed(t, points: [
                    (0.0, startDistance),
                    (0.36, impactDistance),
                    (0.44, rightEndX - overshootDistance),
                    (0.50, rightEndX + (overshootDistance * 0.35)),
                    (0.70, rightEndX),
                    (1.0, rightEndX)
                ], easing: easeInQuad)

                ZStack {
                    Color.black.opacity(0.30 * veilAlpha)

                    Circle()
                        .fill(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.20 * veilAlpha))
                        .frame(width: baseBurst * 2.1, height: baseBurst * 2.1)
                        .offset(x: centerShiftX)
                        .blur(radius: 8)

                    Circle()
                        .fill(Color.white.opacity(0.9 * flashAlpha))
                        .frame(width: baseBurst * 0.92, height: baseBurst * 0.92)
                        .scaleEffect(flashScale)
                        .blur(radius: 2)
                        .offset(x: centerShiftX)

                    Circle()
                        .fill(Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255).opacity(0.45 * flashAlpha))
                        .frame(width: baseBurst * 1.25, height: baseBurst * 1.25)
                        .scaleEffect(flashScale)
                        .blur(radius: 4)
                        .offset(x: centerShiftX)

                    Text("🤜")
                        .font(.system(size: fistFont))
                        .opacity(fistOpacity)
                        .rotationEffect(.degrees(leftRot))
                        .scaleEffect(fistScale)
                        .offset(x: leftX + centerShiftX)

                    Text("🤛")
                        .font(.system(size: fistFont))
                        .opacity(fistOpacity)
                        .rotationEffect(.degrees(rightRot))
                        .scaleEffect(fistScale)
                        .offset(x: rightX + centerShiftX)
                }
                .opacity(overlayAlpha)
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

private func keyframed(_ t: Double, points: [(Double, Double)], easing: (Double) -> Double = { $0 }) -> Double {
    guard let first = points.first, let last = points.last else { return 0 }
    if t <= first.0 { return first.1 }
    if t >= last.0 { return last.1 }
    for idx in 0..<(points.count - 1) {
        let a = points[idx]
        let b = points[idx + 1]
        if t >= a.0 && t <= b.0 {
            let span = max(0.0001, b.0 - a.0)
            let p = easing((t - a.0) / span)
            return a.1 + ((b.1 - a.1) * p)
        }
    }
    return last.1
}

private func easeInQuad(_ p: Double) -> Double {
    p * p
}
