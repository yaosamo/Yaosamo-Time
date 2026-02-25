import SwiftUI
import AppKit

struct WindowDragConfigurator: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(windowFrom: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(windowFrom: nsView)
        }
    }

    private func configure(windowFrom view: NSView) {
        guard let window = view.window else { return }
        window.styleMask.insert(.resizable)
        window.minSize = NSSize(width: 480, height: 400)
        window.isMovableByWindowBackground = isEnabled
    }
}

struct ZoneColumnFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
