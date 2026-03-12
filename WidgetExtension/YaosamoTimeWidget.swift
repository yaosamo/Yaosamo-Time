import SwiftUI
import WidgetKit

struct YaosamoTimeEntry: TimelineEntry {
    let date: Date
    let zones: [WidgetStoredZone]
}

struct YaosamoTimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> YaosamoTimeEntry {
        YaosamoTimeEntry(date: Date(), zones: sampleZones)
    }

    func getSnapshot(in context: Context, completion: @escaping (YaosamoTimeEntry) -> Void) {
        completion(YaosamoTimeEntry(date: Date(), zones: loadZones()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<YaosamoTimeEntry>) -> Void) {
        let now = Date()
        let nextMinute = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        let entry = YaosamoTimeEntry(date: now, zones: loadZones())
        completion(Timeline(entries: [entry], policy: .after(nextMinute)))
    }

    private func loadZones() -> [WidgetStoredZone] {
        guard
            let data = YaosamoTimeSharedStore.persistedClockStateData(),
            let state = try? JSONDecoder().decode(WidgetStoredClockState.self, from: data),
            !state.zones.isEmpty
        else {
            return sampleZones
        }

        return Array(state.zones.prefix(4))
    }

    private var sampleZones: [WidgetStoredZone] {
        [
            WidgetStoredZone(id: UUID(), timeZone: "America/Los_Angeles", title: "Portland", subtitle: "United States, OR"),
            WidgetStoredZone(id: UUID(), timeZone: "America/New_York", title: "Miami", subtitle: "United States, FL"),
            WidgetStoredZone(id: UUID(), timeZone: "Europe/Warsaw", title: "Warsaw", subtitle: "Poland"),
            WidgetStoredZone(id: UUID(), timeZone: "Asia/Tokyo", title: "Tokyo", subtitle: "Japan")
        ]
    }
}

struct YaosamoTimeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let entry: YaosamoTimeEntry

    var body: some View {
        let visibleZones = Array(entry.zones.prefix(maxVisibleZones))

        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(visibleZones) { zone in
                    WidgetZoneHeaderView(zone: zone, now: entry.date)
                        .environment(\.widgetRenderingMode, widgetRenderingMode)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(alignment: .top, spacing: 0) {
                ForEach(visibleZones) { zone in
                    WidgetZoneTimelineView(
                        zone: zone,
                        now: entry.date,
                        family: family,
                        availableHeight: max(0, geometry.size.height - headerHeight)
                    )
                    .environment(\.widgetRenderingMode, widgetRenderingMode)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .containerBackground(for: .widget) {
            backgroundColor
        }
    }

    private var maxVisibleZones: Int {
        4
    }

    private var horizontalPadding: CGFloat {
        switch family {
        case .systemMedium:
            return 0
        default:
            return 0
        }
    }

    private var verticalPadding: CGFloat {
        switch family {
        case .systemMedium:
            return 0
        default:
            return 0
        }
    }

    private var headerHeight: CGFloat {
        switch family {
        case .systemMedium:
            return 42
        default:
            return 46
        }
    }

    private var backgroundColor: some View {
        ZStack {
            if colorScheme == .dark {
                Color(red: 10 / 255, green: 11 / 255, blue: 13 / 255)
            } else {
                Color(red: 243 / 255, green: 245 / 255, blue: 248 / 255)
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.30),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct WidgetZoneHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let zone: WidgetStoredZone
    let now: Date

    var body: some View {
        VStack(spacing: 2) {
            Text(zone.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.3)
                .foregroundStyle(primaryHeaderTextColor)
                .lineLimit(1)

            Text(zone.subtitle.uppercased())
                .font(.system(size: 7.5, weight: .medium))
                .kerning(1.0)
                .foregroundStyle(secondaryHeaderTextColor)
                .lineLimit(1)

            Text(shortTime)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(timeHeaderTextColor)
                .padding(.top, 1)
                .padding(.horizontal, isNightHour ? 6 : 0)
                .padding(.vertical, isNightHour ? 2 : 0)
                .background {
                    if isNightHour {
                        Capsule(style: .continuous)
                            .fill(timeHeaderPillFillColor)
                    }
                }
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    private var shortTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: zone.timeZone)
        formatter.dateFormat = uses24HourClock ? "HH:mm" : "h:mm a"
        return formatter.string(from: now)
    }

    private var uses24HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)?
            .contains("a") == false
    }

    private var primaryHeaderTextColor: Color {
        guard widgetRenderingMode == .fullColor else { return .primary }
        return colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.78)
    }

    private var secondaryHeaderTextColor: Color {
        guard widgetRenderingMode == .fullColor else { return .secondary }
        return colorScheme == .dark ? Color.white.opacity(0.36) : Color.black.opacity(0.32)
    }

    private var timeHeaderTextColor: Color {
        guard widgetRenderingMode == .fullColor else {
            return isNightHour ? .primary : .secondary
        }
        if isNightHour {
            return Color.white.opacity(0.96)
        }
        return colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.52)
    }

    private var timeHeaderPillFillColor: Color {
        guard widgetRenderingMode == .fullColor else {
            return colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)
        }
        return Color(red: 99 / 255, green: 87 / 255, blue: 241 / 255)
    }

    private var isNightHour: Bool {
        let zoneHour = Calendar.current.dateComponents(in: TimeZone(identifier: zone.timeZone) ?? .current, from: now).hour ?? 0
        return zoneHour < 6 || zoneHour > 22
    }
}

private struct WidgetZoneTimelineView: View {
    let zone: WidgetStoredZone
    let now: Date
    let family: WidgetFamily
    let availableHeight: CGFloat
    private let visibleHours = Array(6...22)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(visibleHours, id: \.self) { hour in
                WidgetHourRowView(
                    hour: hour,
                    isCurrentHour: currentHour == hour,
                    rowHeight: rowHeight
                )
            }
        }
        .padding(.horizontal, 1)
    }

    private var currentHour: Int {
        let timeZone = TimeZone(identifier: zone.timeZone) ?? .current
        return Calendar.current.dateComponents(in: timeZone, from: now).hour ?? 0
    }

    private var rowHeight: CGFloat {
        let computedHeight = floor(max(6, availableHeight) / CGFloat(visibleHours.count))
        switch family {
        case .systemMedium:
            return max(7, computedHeight)
        default:
            return max(8, computedHeight)
        }
    }
}

private struct WidgetHourRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let hour: Int
    let isCurrentHour: Bool
    let rowHeight: CGFloat

    var body: some View {
        ZStack {
            if isCurrentHour {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selectionFillColor)
                    .padding(.horizontal, 2)
            }

            if isCurrentHour {
                Rectangle()
                    .fill(currentMarkerColor)
                    .frame(height: 1)
                    .padding(.horizontal, 6)
                    .offset(y: rowLineOffset)
            }

            Text(formattedHourLabel(hour))
                .font(.system(size: fontSize, weight: isCurrentHour ? .medium : .regular, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(textColor)
                .opacity(textOpacity)
                .frame(maxWidth: .infinity)
        }
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    private var fontSize: CGFloat {
        max(8.5, min(10.5, rowHeight - 0.2))
    }

    private var rowLineOffset: CGFloat {
        max(3, min(4.5, rowHeight * 0.48))
    }

    private var selectionFillColor: Color {
        guard widgetRenderingMode == .fullColor else {
            return colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14)
        }
        if isDayHour(hour) {
            return Color(red: 0.90, green: 0.76, blue: 0.02)
        }
        return Color(red: 99 / 255, green: 87 / 255, blue: 241 / 255)
    }

    private var textOpacity: Double {
        if isCurrentHour { return 1 }
        if isDayHour(hour) { return 0.78 }
        return 0.16
    }

    private var textColor: Color {
        if widgetRenderingMode != .fullColor {
            return isCurrentHour ? .primary : .primary
        }
        if isCurrentHour { return Color.black.opacity(0.88) }
        if colorScheme == .dark { return Color.white.opacity(0.92) }
        return Color.black.opacity(1)
    }

    private var currentMarkerColor: Color {
        guard widgetRenderingMode == .fullColor else {
            return colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.30)
        }
        return Color.gray.opacity(0.35)
    }
}

private func formattedHourLabel(_ hour: Int) -> String {
    let uses24HourClock = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)?
        .contains("a") == false

    if uses24HourClock {
        return String(format: "%02d", hour)
    }

    let period = hour >= 12 ? "PM" : "AM"
    let normalizedHour = hour % 12 == 0 ? 12 : hour % 12
    return "\(normalizedHour)\(hour < 10 ? " " : "") \(period)"
}

private func isDayHour(_ hour: Int) -> Bool {
    (6...21).contains(hour)
}

struct YaosamoTimeWidget: Widget {
    let kind = "YaosamoTimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: YaosamoTimeProvider()) { entry in
            YaosamoTimeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("World Clock Board")
        .description("Shows your saved Yaosamo Time zones using the same timezone column layout as the app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
