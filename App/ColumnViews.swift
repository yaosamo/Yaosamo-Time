import SwiftUI

struct ZoneColumnHeaderView: View {
    @EnvironmentObject private var clockStore: ClockStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHeaderHovering = false
    @State private var isHeaderDragging = false
    @State private var isEditLocationPresented = false

    let zone: ZoneClock
    let now: Date
    let width: CGFloat
    let isDragging: Bool
    let dragOffset: CGSize
    let showPlaceholder: Bool
    let onHeaderDragStart: () -> Void
    let onHeaderDragChanged: (CGPoint, CGSize) -> Void
    let onHeaderDragEnded: () -> Void
    let onHeaderHoverChange: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if showPlaceholder {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(placeholderFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(placeholderStrokeColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
            }

            headerBlock
                .offset(dragOffset)
                .zIndex(isDragging ? 10 : 0)
                .opacity(isDragging ? 0.92 : 1)
                .shadow(
                    color: Color.black.opacity(isDragging ? 0.10 : 0.0),
                    radius: isDragging ? 10 : 0,
                    x: 0,
                    y: isDragging ? 6 : 0
                )
                .scaleEffect(isDragging ? 1.01 : 1.0, anchor: .top)
                .animation(.easeOut(duration: 0.08), value: isDragging)
        }
        .frame(width: width, height: 58, alignment: .top)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ZoneColumnFramePreferenceKey.self,
                    value: [zone.id: geometry.frame(in: .named("ZoneColumnsReorderSpace"))]
                )
            }
        )
    }

    private var headerBlock: some View {
        VStack(spacing: 2) {
            Text(zone.title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(1.3)
                .foregroundStyle(primaryHeaderTextColor)

            Text(zone.subtitle.uppercased())
                .font(.system(size: 9, weight: .medium))
                .kerning(1.0)
                .foregroundStyle(secondaryHeaderTextColor)
                .lineLimit(1)

            Text(clockStore.shortTime(for: zone.timeZone, date: now))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(timeHeaderTextColor)
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(headerHoverFillColor.opacity(isHeaderHovering ? 1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            Button {
                clockStore.removeZone(id: zone.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(deleteIconColor)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(deleteIconBackground)
                    )
            }
            .buttonStyle(.plain)
            .help("Remove city")
            .padding(.top, 2)
            .padding(.trailing, 2)
            .opacity(isHeaderHovering ? 1 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHeaderHovering)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isHeaderHovering)
        .popover(isPresented: $isEditLocationPresented, arrowEdge: .top) {
            AddCityPopover(
                isPresented: $isEditLocationPresented,
                mode: .edit(zoneID: zone.id, currentTitle: zone.title)
            )
            .environmentObject(clockStore)
        }
        .onHover { hovering in
            isHeaderHovering = hovering
            onHeaderHoverChange(hovering)
        }
        .onTapGesture {
            guard !isHeaderDragging else { return }
            isEditLocationPresented = true
        }
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("ZoneColumnsReorderSpace"))
                .onChanged { value in
                    if !isHeaderHovering {
                        isHeaderHovering = true
                        onHeaderHoverChange(true)
                    }
                    if !isHeaderDragging {
                        isHeaderDragging = true
                        onHeaderDragStart()
                    }
                    onHeaderDragChanged(value.location, value.translation)
                }
                .onEnded { _ in
                    isHeaderDragging = false
                    onHeaderDragEnded()
                }
        )
    }

    private var primaryHeaderTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.78)
    }

    private var secondaryHeaderTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.36) : Color.black.opacity(0.32)
    }

    private var timeHeaderTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.52)
    }

    private var headerHoverFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }

    private var deleteIconColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.42)
    }

    private var deleteIconBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.18)
    }

    private var placeholderFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.03)
    }

    private var placeholderStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }
}

struct ZoneTimelineColumnView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var clockStore: ClockStore
    @State private var isTimelineGestureActive = false
    @State private var hoveredHour: Int?

    let zone: ZoneClock
    let rowHeight: CGFloat
    let viewportHeight: CGFloat
    let width: CGFloat
    let edgeFadeEnabled: Bool
    let projectedHour: Int?
    let selectedSourceZoneID: UUID?
    let isDragging: Bool
    let dragOffset: CGSize
    let showPlaceholder: Bool
    let onTimelineDragStart: () -> Void
    let onTimelineDragChanged: (CGPoint, CGSize) -> Void
    let onTimelineDragEnded: () -> Void
    let onTimelineHoverChange: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if showPlaceholder {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(placeholderFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(placeholderStrokeColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
                    .padding(.top, 2)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectionFillColor)
                    .frame(height: rowHeight)
                    .padding(.horizontal, 3)
                    .offset(y: CGFloat(projectedHour ?? 0) * rowHeight)
                    .opacity(projectedHour == nil ? 0 : 1)
                    .animation(.spring(response: 0.22, dampingFraction: 0.86), value: projectedHour)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hourHoverFillColor)
                    .frame(height: rowHeight)
                    .padding(.horizontal, 3)
                    .offset(y: CGFloat(hoveredHour ?? 0) * rowHeight)
                    .opacity(hoveredHour == nil ? 0 : 1)
                    .animation(.easeOut(duration: 0.10), value: hoveredHour)

                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { hour in
                        GeometryReader { rowGeometry in
                            HourRowView(
                                zone: zone,
                                hour: hour,
                                rowHeight: rowHeight,
                                topFadeProgress: min(
                                    topFadeProgress(rowFrame: rowGeometry.frame(in: .named("ZoneTimelineScrollViewport"))),
                                    bottomFadeProgress(rowFrame: rowGeometry.frame(in: .named("ZoneTimelineScrollViewport")))
                                ),
                                projectedHour: projectedHour,
                                selectedSourceZoneID: selectedSourceZoneID,
                                currentHour: clockStore.currentHour(for: zone),
                                currentMinute: clockStore.currentMinute(for: zone),
                                onHoverChanged: { isHovered in
                                    hoveredHour = isHovered ? hour : (hoveredHour == hour ? nil : hoveredHour)
                                }
                            )
                            .environmentObject(clockStore)
                        }
                        .frame(height: rowHeight)
                    }
                }
            }
            .offset(dragOffset)
            .zIndex(isDragging ? 10 : 0)
            .opacity(isDragging ? 0.92 : 1)
            .shadow(
                color: Color.black.opacity(isDragging ? 0.10 : 0.0),
                radius: isDragging ? 10 : 0,
                x: 0,
                y: isDragging ? 6 : 0
            )
            .scaleEffect(isDragging ? 1.01 : 1.0, anchor: .top)
            .animation(.easeOut(duration: 0.08), value: isDragging)
        }
        .frame(width: width, alignment: .top)
        .onHover {
            onTimelineHoverChange($0)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("ZoneColumnsReorderSpace"))
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let shouldActivate = abs(dx) > 3 && abs(dx) > abs(dy)
                    guard shouldActivate || isTimelineGestureActive else { return }

                    if !isTimelineGestureActive {
                        isTimelineGestureActive = true
                        onTimelineDragStart()
                    }
                    onTimelineDragChanged(value.location, value.translation)
                }
                .onEnded { _ in
                    guard isTimelineGestureActive else { return }
                    isTimelineGestureActive = false
                    onTimelineDragEnded()
                }
        )
    }

    private var placeholderFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.03)
    }

    private var placeholderStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }

    private var hourHoverFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

    private var selectionFillColor: Color {
        guard let projectedHour else { return .clear }
        if isDayHour(projectedHour) {
            return Color(red: 0.90, green: 0.76, blue: 0.02)
        }
        return Color(red: 99 / 255, green: 87 / 255, blue: 241 / 255)
    }

    private nonisolated func topFadeProgress(rowFrame: CGRect) -> Double {
        guard edgeFadeEnabled else { return 1 }
        let rowCenter = rowFrame.midY
        let fadeStart = rowHeight * 1.35
        let fadeEnd = rowHeight * 0.25
        if rowCenter >= fadeStart { return 1 }
        if rowCenter <= fadeEnd { return 0 }
        return Double((rowCenter - fadeEnd) / (fadeStart - fadeEnd))
    }

    private nonisolated func bottomFadeProgress(rowFrame: CGRect) -> Double {
        guard edgeFadeEnabled else { return 1 }
        let rowCenter = rowFrame.midY
        let distanceToBottom = viewportHeight - rowCenter
        let fadeStart = rowHeight * 1.35
        let fadeEnd = rowHeight * 0.25
        if distanceToBottom >= fadeStart { return 1 }
        if distanceToBottom <= fadeEnd { return 0 }
        return Double((distanceToBottom - fadeEnd) / (fadeStart - fadeEnd))
    }
}

struct ZoneReorderDropSlot: View {
    @Environment(\.colorScheme) private var colorScheme
    let isActive: Bool
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10, height: height)

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(dropIndicatorColor.opacity(isActive ? 1 : 0))
                .frame(width: 2, height: max(0, height - 8))
                .animation(.easeOut(duration: 0.08), value: isActive)
        }
        .contentShape(Rectangle())
    }

    private var dropIndicatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.28)
    }
}

struct HourRowView: View {
    @EnvironmentObject private var clockStore: ClockStore
    @Environment(\.colorScheme) private var colorScheme

    let zone: ZoneClock
    let hour: Int
    let rowHeight: CGFloat
    let topFadeProgress: Double
    let projectedHour: Int?
    let selectedSourceZoneID: UUID?
    let currentHour: Int
    let currentMinute: Int
    let onHoverChanged: (Bool) -> Void

    private var isProjected: Bool { projectedHour == hour }
    private var isSourceSelected: Bool { isProjected && selectedSourceZoneID == zone.id }
    private var isCurrentHour: Bool { currentHour == hour }

    var body: some View {
        Button {
            clockStore.select(hour: hour, in: zone)
        } label: {
            ZStack {
                if let highlightKind {
                    if highlightKind == .current {
                        Rectangle()
                            .fill(highlightKind.fillColor)
                            .frame(height: 1)
                            .padding(.horizontal, 4)
                            .offset(y: 7)
                            .opacity(currentBlinkOpacity)
                            .animation(.easeInOut(duration: 0.25), value: currentBlinkOpacity)
                    }
                }

                Text(clockStore.formattedHourLabel(hour))
                    .font(.system(size: 12, weight: textWeight, design: .monospaced))
                    .kerning(0.4)
                    .foregroundStyle(textColor)
                    .opacity(textOpacity * topFadeProgress)
                    .scaleEffect(x: max(0.82, topFadeProgress), y: max(0.82, topFadeProgress), anchor: .center)
                    .offset(y: (1 - topFadeProgress) * -5)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHoverChanged)
    }

    private var highlightKind: HourHighlightKind? {
        if isCurrentHour { return .current }
        return nil
    }

    private var textWeight: Font.Weight {
        if isSourceSelected { return .semibold }
        if isProjected { return .medium }
        return .regular
    }

    private var textOpacity: Double {
        if isProjected { return 1 }
        if isDayHour(hour) { return 0.78 }
        return 0.16
    }

    private var textColor: Color {
        if isProjected { return Color.black.opacity(0.88) }
        if colorScheme == .dark { return Color.white.opacity(0.92) }
        return Color.black.opacity(1)
    }

    private var currentBlinkOpacity: Double {
        guard isCurrentHour else { return 1 }
        let second = Calendar.current.component(.second, from: clockStore.now)
        return second.isMultiple(of: 2) ? 1 : 0.28
    }
}

enum HourHighlightKind {
    case current

    var fillColor: Color {
        switch self {
        case .current:
            return Color.gray.opacity(0.35)
        }
    }
}

func isDayHour(_ hour: Int) -> Bool {
    (6...21).contains(hour)
}
