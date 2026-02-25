//
//  ContentView.swift
//  Yaosamo Time
//
//  Created by Personal on 2/24/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var clockStore: ClockStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedZoneID: UUID?
    @State private var activeDropInsertionIndex: Int?
    @State private var headerHoveringZoneIDs: Set<UUID> = []
    @State private var columnFrames: [UUID: CGRect] = [:]
    @State private var draggedColumnOffset: CGSize = .zero
    @State private var animatedProjectedHoursByZoneID: [UUID: Int?] = [:]
    @State private var selectionCascadeTask: Task<Void, Never>?
    @State private var fistBumpOverlayStartDate: Date?
    @State private var fistBumpOverlayHideTask: Task<Void, Never>?

    private let controlsLeadingInset: CGFloat = 16
    private let controlsWidth: CGFloat = 24
    private let controlsToContentGap: CGFloat = 8
    private let columnMinWidth: CGFloat = 118
    private let dropSlotWidth: CGFloat = 10
    private let columnHorizontalPadding: CGFloat = 4
    private let scrollTrailingPadding: CGFloat = 0

    private var isWindowBackgroundDragEnabled: Bool {
        draggedZoneID == nil && headerHoveringZoneIDs.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = resolvedColumnWidth(forContentWidth: geometry.size.width)
            let contentLeadingInset: CGFloat = 0
            let columnsViewportHeight = max(0, geometry.size.height)

            ZStack(alignment: .leading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    let headerHeight: CGFloat = 58
                    let headerGap: CGFloat = 8
                    let timelineTopPadding: CGFloat = 18
                    let timelineBottomPadding: CGFloat = 18
                    let timelineViewportHeight = max(0, columnsViewportHeight - headerHeight - headerGap)
                    let timelinePaddingTotal = timelineTopPadding + timelineBottomPadding
                    let rowHeight = max(22, (timelineViewportHeight - timelinePaddingTotal) / 24)
                    let timelineContentHeight = max(timelineViewportHeight, (rowHeight * 24) + timelinePaddingTotal)
                    let edgeFadeEnabled = timelineContentHeight > (timelineViewportHeight + 0.5)

                    VStack(alignment: .leading, spacing: headerGap) {
                        HStack(alignment: .top, spacing: 0) {
                            ZoneReorderDropSlot(
                                isActive: draggedZoneID != nil && activeDropInsertionIndex == 0,
                                height: headerHeight
                            )

                            ForEach(Array(clockStore.zones.enumerated()), id: \.element.id) { index, zone in
                                ZoneColumnHeaderView(
                                    zone: zone,
                                    now: clockStore.now,
                                    width: columnWidth,
                                    isDragging: draggedZoneID == zone.id,
                                    dragOffset: draggedZoneID == zone.id ? draggedColumnOffset : .zero,
                                    showPlaceholder: draggedZoneID == zone.id,
                                    onHeaderDragStart: {
                                        draggedZoneID = zone.id
                                        draggedColumnOffset = .zero
                                        activeDropInsertionIndex = index
                                    },
                                    onHeaderDragChanged: { location, translation in
                                        draggedColumnOffset = translation
                                        updateColumnReorderInsertion(for: zone.id, pointerX: location.x)
                                    },
                                    onHeaderDragEnded: {
                                        finishColumnReorder()
                                    },
                                    onHeaderHoverChange: { hovering in
                                        if hovering {
                                            headerHoveringZoneIDs.insert(zone.id)
                                        } else {
                                            headerHoveringZoneIDs.remove(zone.id)
                                        }
                                    }
                                )
                                .environmentObject(clockStore)
                                .padding(.horizontal, columnHorizontalPadding)

                                ZoneReorderDropSlot(
                                    isActive: draggedZoneID != nil && activeDropInsertionIndex == (index + 1),
                                    height: headerHeight
                                )
                            }
                        }

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: timelineTopPadding)
                                HStack(alignment: .top, spacing: 0) {
                                ZoneReorderDropSlot(
                                    isActive: draggedZoneID != nil && activeDropInsertionIndex == 0,
                                    height: timelineContentHeight
                                )

                                ForEach(Array(clockStore.zones.enumerated()), id: \.element.id) { index, zone in
                                    ZoneTimelineColumnView(
                                        zone: zone,
                                        rowHeight: rowHeight,
                                        viewportHeight: timelineViewportHeight,
                                        width: columnWidth,
                                        edgeFadeEnabled: edgeFadeEnabled,
                                        projectedHour: animatedProjectedHoursByZoneID[zone.id] ?? clockStore.projectedHour(for: zone),
                                        selectedSourceZoneID: clockStore.selectedReference?.sourceZoneID,
                                        isDragging: draggedZoneID == zone.id,
                                        dragOffset: draggedZoneID == zone.id ? draggedColumnOffset : .zero,
                                        showPlaceholder: draggedZoneID == zone.id,
                                        onTimelineDragStart: {
                                            draggedZoneID = zone.id
                                            draggedColumnOffset = .zero
                                            activeDropInsertionIndex = index
                                        },
                                        onTimelineDragChanged: { location, translation in
                                            draggedColumnOffset = translation
                                            updateColumnReorderInsertion(for: zone.id, pointerX: location.x)
                                        },
                                        onTimelineDragEnded: {
                                            finishColumnReorder()
                                        },
                                        onTimelineHoverChange: { hovering in
                                            if hovering {
                                                headerHoveringZoneIDs.insert(zone.id)
                                            } else {
                                                headerHoveringZoneIDs.remove(zone.id)
                                            }
                                        }
                                    )
                                    .environmentObject(clockStore)
                                    .padding(.horizontal, columnHorizontalPadding)

                                    ZoneReorderDropSlot(
                                        isActive: draggedZoneID != nil && activeDropInsertionIndex == (index + 1),
                                        height: timelineContentHeight
                                    )
                                }
                            }
                            Color.clear.frame(height: timelineBottomPadding)
                            }
                            .frame(height: timelineContentHeight, alignment: .top)
                        }
                        .coordinateSpace(name: "ZoneTimelineScrollViewport")
                        .frame(height: timelineViewportHeight)
                    }
                    .coordinateSpace(name: "ZoneColumnsReorderSpace")
                    .onPreferenceChange(ZoneColumnFramePreferenceKey.self) { columnFrames = $0 }
                    .onAppear {
                        syncAnimatedProjectedHours(animated: false)
                    }
                    .onChange(of: clockStore.zones.map(\.id)) { _ in
                        syncAnimatedProjectedHours(animated: false)
                    }
                    .onChange(of: selectionAnimationToken) { _ in
                        syncAnimatedProjectedHours(animated: true)
                    }
                    .padding(.leading, contentLeadingInset)
                    .padding(.trailing, scrollTrailingPadding)
                }

                ZoneControlRail(onCopyCelebration: triggerFullScreenFistBumpOverlay)
                    .environmentObject(clockStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, controlsLeadingInset)
                    .padding(.bottom, 16)
                    .zIndex(20)

                if let fistBumpOverlayStartDate {
                    FistBumpOverlayFullScreen(startDate: fistBumpOverlayStartDate)
                        .transition(.opacity)
                        .zIndex(40)
                }
            }
        }
        .padding(.leading, 0)
        .padding(.trailing, 0)
        .padding(.top, 16)
        .padding(.bottom, 0)
        .frame(
            minWidth: 480,
            idealWidth: 520,
            minHeight: 400,
            idealHeight: 420,
            alignment: .leading
        )
        .background(windowBackground)
        .background(
            WindowDragConfigurator(isEnabled: isWindowBackgroundDragEnabled)
        )
        .onDisappear {
            selectionCascadeTask?.cancel()
            fistBumpOverlayHideTask?.cancel()
            fistBumpOverlayHideTask = nil
        }
    }

    private func resolvedColumnWidth(forContentWidth width: CGFloat) -> CGFloat {
        let count = max(clockStore.zones.count, 1)
        let visibleColumnsWidth = width - scrollTrailingPadding
        let slotsWidth = CGFloat(count + 1) * dropSlotWidth
        let columnPaddingWidth = CGFloat(count) * (columnHorizontalPadding * 2)
        let distributed = floor((visibleColumnsWidth - slotsWidth - columnPaddingWidth) / CGFloat(count))
        return max(columnMinWidth, distributed)
    }

    private var windowBackground: Color {
        if colorScheme == .dark {
            return Color(red: 10 / 255, green: 11 / 255, blue: 13 / 255)
        }
        return Color(red: 243 / 255, green: 245 / 255, blue: 248 / 255)
    }

    private func updateColumnReorderInsertion(for zoneID: UUID, pointerX: CGFloat) {
        guard draggedZoneID == zoneID else { return }

        let orderedFrames = clockStore.zones.compactMap { zone in
            columnFrames[zone.id]
        }
        guard orderedFrames.count == clockStore.zones.count else { return }

        var insertionIndex = orderedFrames.count
        for (index, frame) in orderedFrames.enumerated() {
            if pointerX < frame.midX {
                insertionIndex = index
                break
            }
        }
        activeDropInsertionIndex = insertionIndex
    }

    private func finishColumnReorder() {
        defer {
            draggedZoneID = nil
            activeDropInsertionIndex = nil
            draggedColumnOffset = .zero
        }
        guard let draggedZoneID, let insertionIndex = activeDropInsertionIndex else { return }
        clockStore.moveZone(id: draggedZoneID, toInsertionIndex: insertionIndex)
    }

    private var selectionAnimationToken: String {
        guard let selected = clockStore.selectedReference else { return "none" }
        return "\(selected.sourceZoneID.uuidString)|\(selected.localHour)|\(selected.utcDate.timeIntervalSince1970)"
    }

    private func syncAnimatedProjectedHours(animated: Bool) {
        selectionCascadeTask?.cancel()

        let targetHours = Dictionary(uniqueKeysWithValues: clockStore.zones.map { zone in
            (zone.id, clockStore.projectedHour(for: zone))
        })

        guard animated else {
            animatedProjectedHoursByZoneID = targetHours
            return
        }

        let previous = animatedProjectedHoursByZoneID
        if previous.isEmpty {
            animatedProjectedHoursByZoneID = targetHours
            return
        }

        let sourceZoneID = clockStore.selectedReference?.sourceZoneID
        let sourceIndex = sourceZoneID.flatMap { id in clockStore.zones.firstIndex(where: { $0.id == id }) } ?? 0
        let orderedIndices = clockStore.zones.indices.sorted { lhs, rhs in
            let dl = abs(lhs - sourceIndex)
            let dr = abs(rhs - sourceIndex)
            if dl == dr { return lhs < rhs }
            return dl < dr
        }
        let cascadeStepDelay: UInt64 = 95_000_000

        selectionCascadeTask = Task {
            for (step, index) in orderedIndices.enumerated() {
                if Task.isCancelled { return }
                let zone = clockStore.zones[index]
                let target = targetHours[zone.id] ?? nil
                if previous[zone.id] != target {
                    if step > 0 {
                        try? await Task.sleep(nanoseconds: cascadeStepDelay)
                    }
                    if Task.isCancelled { return }
                    await MainActor.run {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            animatedProjectedHoursByZoneID[zone.id] = target
                        }
                    }
                }
            }

            if Task.isCancelled { return }
            await MainActor.run {
                for zone in clockStore.zones where animatedProjectedHoursByZoneID[zone.id] == nil && targetHours[zone.id] != nil {
                    animatedProjectedHoursByZoneID[zone.id] = targetHours[zone.id] ?? nil
                }
            }
        }
    }

    private func triggerFullScreenFistBumpOverlay() {
        fistBumpOverlayHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.08)) {
            fistBumpOverlayStartDate = Date()
        }

        fistBumpOverlayHideTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.15)) {
                    fistBumpOverlayStartDate = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClockStore())
}
