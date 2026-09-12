import SwiftUI
import UIKit

/// UIKit's built-in shake gesture — the same `UIEvent.EventSubtype
/// .motionShake` motion event behind system features like "Secouer pour
/// annuler" (Shake to Undo). It rides the existing accelerometer-driven
/// motion detection UIKit already does for that, delivered through the
/// responder chain rather than a CoreMotion feed Plutar would have to poll
/// itself — the same mechanism used for the price-hiding shake in
/// PierreVincent.
///
/// `UIResponder.motionEnded(_:with:)` is where it normally arrives; `UIWindow`
/// is first in the responder chain to see it, so overriding it here catches
/// every shake in the app and re-broadcasts it as a plain notification SwiftUI
/// can subscribe to.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .plutarDeviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

extension Notification.Name {
    static let plutarDeviceDidShake = Notification.Name("plutarDeviceDidShake")
}

extension View {
    /// Runs `action` whenever the device is shaken while this view is on screen.
    func onShake(perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .plutarDeviceDidShake)) { _ in
            action()
        }
    }
}
