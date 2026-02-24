//
//  Yaosamo_TimeApp.swift
//  Yaosamo Time
//
//  Created by Personal on 2/24/26.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct Yaosamo_TimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var clockStore = ClockStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(clockStore)
        } label: {
            Label(clockStore.menuBarLabel, systemImage: "clock")
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
