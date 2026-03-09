import SwiftUI
import AppKit
import Combine

struct ThemedRootView<Content: View>: View {
    @EnvironmentObject private var clockStore: ClockStore
    @ViewBuilder let content: Content

    var body: some View {
        content
            .preferredColorScheme(clockStore.themePreference.colorScheme)
            .id(clockStore.themePreference)
    }
}

struct SettingsView: View {
    let themePreference: AppThemePreference
    let onThemeChange: (AppThemePreference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Appearance")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Text("Choose how Yaosamo Time should appear across the tray window and settings.")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Theme", selection: themeBinding) {
                ForEach(AppThemePreference.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, height: 160, alignment: .topLeading)
        .background(backgroundColor)
    }

    private var themeBinding: Binding<AppThemePreference> {
        Binding(
            get: { themePreference },
            set: onThemeChange
        )
    }

    private var resolvedColorScheme: ColorScheme {
        themePreference.resolvedColorScheme
    }

    private var primaryTextColor: Color {
        resolvedColorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.82)
    }

    private var secondaryTextColor: Color {
        resolvedColorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.50)
    }

    private var backgroundColor: Color {
        resolvedColorScheme == .dark
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : Color(red: 0.95, green: 0.95, blue: 0.96)
    }
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private let clockStore: ClockStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(clockStore: ClockStore, settingsWindowController: SettingsWindowController) {
        self.clockStore = clockStore
        self.settingsWindowController = settingsWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopover()
        bindStore()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp {
            presentContextMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.showWindow()
    }

    @objc private func openAboutPanel(_ sender: Any?) {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Yaosamo Time")
        button.imagePosition = .imageLeading
        refreshStatusItemLabel()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: ThemedRootView {
                ContentView()
                    .environmentObject(clockStore)
            }
            .environmentObject(clockStore)
        )
    }

    private func bindStore() {
        clockStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshStatusItemLabel()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItemLabel() {
        guard let button = statusItem.button else { return }
        let attributes = statusItemTitleAttributes
        button.attributedTitle = NSAttributedString(string: " \(clockStore.menuBarLabel)", attributes: attributes)
        statusItem.length = statusItemFixedWidth(using: attributes, button: button)
    }

    private var statusItemTitleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
    }

    private func statusItemFixedWidth(using attributes: [NSAttributedString.Key: Any], button: NSStatusBarButton) -> CGFloat {
        let sample = clockStore.uses24HourClock ? " 23:59" : " 12:59PM"
        let textWidth = ceil((sample as NSString).size(withAttributes: attributes).width)
        let imageWidth = button.image?.size.width ?? 14
        return textWidth + imageWidth + 22
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }

        closeContextMenu()
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func presentContextMenu() {
        closePopover()

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Preferences…", action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About Yaosamo Time", action: #selector(openAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    private func closeContextMenu() {
        statusItem.menu?.cancelTracking()
        statusItem.menu = nil
    }
}

@MainActor
final class SettingsWindowController {
    private let clockStore: ClockStore
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?

    init(clockStore: ClockStore) {
        self.clockStore = clockStore
    }

    func showWindow() {
        let window = window ?? makeWindow()
        self.window = window
        applyWindowAppearance()
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow()
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.setContentSize(NSSize(width: 360, height: 160))
        let hostingController = NSHostingController(rootView: makeSettingsView())
        self.hostingController = hostingController
        window.contentViewController = hostingController
        window.center()
        return window
    }

    private func makeSettingsView() -> SettingsView {
        SettingsView(
            themePreference: clockStore.themePreference,
            onThemeChange: { [weak self] preference in
                self?.clockStore.setThemePreference(preference)
                self?.hostingController?.rootView = self?.makeSettingsView() ?? SettingsView(
                    themePreference: preference,
                    onThemeChange: { _ in }
                )
                self?.applyWindowAppearance()
            }
        )
    }

    private func applyWindowAppearance() {
        guard let window else { return }
        window.appearance = clockStore.themePreference.appearance
        window.backgroundColor =
            clockStore.themePreference.resolvedColorScheme == .dark
            ? NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.13, alpha: 1)
            : NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
    }
}

extension AppThemePreference {
    var resolvedColorScheme: ColorScheme {
        switch self {
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? .dark : .light
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .light:
            return NSAppearance(named: .aqua)
        }
    }
}
