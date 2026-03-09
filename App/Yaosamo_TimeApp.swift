//
//  Yaosamo_TimeApp.swift
//  Yaosamo Time
//
//  Created by Personal on 2/24/26.
//

import SwiftUI
import AppKit

@main
struct Yaosamo_TimeApp: App {
    @StateObject private var clockStore: ClockStore
    private let settingsWindowController: SettingsWindowController
    private let menuBarController: MenuBarController

    init() {
        let clockStore = ClockStore()
        _clockStore = StateObject(wrappedValue: clockStore)
        let settingsWindowController = SettingsWindowController(clockStore: clockStore)
        self.settingsWindowController = settingsWindowController
        menuBarController = MenuBarController(clockStore: clockStore, settingsWindowController: settingsWindowController)
    }

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                AppMenuCommands(settingsWindowController: settingsWindowController)
            }
    }
}

private struct AppMenuCommands: Commands {
    let settingsWindowController: SettingsWindowController

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Preferences…") {
                settingsWindowController.showWindow()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit Yaosamo Time") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
