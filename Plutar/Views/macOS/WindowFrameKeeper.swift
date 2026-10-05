import AppKit
import SwiftUI

/// Remembers the main window's frame (size and position) across launches.
/// Saved on every resize/move rather than only at quit, so a force-quit or
/// crash doesn't lose it; restored once, when the window first appears.
private struct WindowFrameKeeper: NSViewRepresentable {
    static let defaultsKey = "plutar.mainWindowFrame"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?) {
            guard let window, observers.isEmpty else { return }
            if let saved = UserDefaults.standard.string(forKey: WindowFrameKeeper.defaultsKey) {
                let frame = NSRectFromString(saved)
                // Ignore a frame that no longer lands on any connected screen.
                if frame.width > 0, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                    window.setFrame(frame, display: true)
                }
            }
            let save: (Notification) -> Void = { [weak window] _ in
                guard let window else { return }
                UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: WindowFrameKeeper.defaultsKey)
            }
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main, using: save))
            }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}

extension View {
    /// macOS: persist and restore this window's frame between launches.
    func remembersWindowFrame() -> some View {
        background(WindowFrameKeeper())
    }
}
