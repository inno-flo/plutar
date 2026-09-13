import Foundation
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// `UIImage`/`NSImage` compatibility shim — this file (in `Persistence/`) is
/// compiled into every target that touches thumbnails: both apps and both
/// share extensions. `LinkRowView` (app targets only) additionally wraps
/// this in a SwiftUI `Image(platformImage:)` initializer of its own.
extension PlatformImage {
    /// `UIImage.jpegData(compressionQuality:)` on iOS; `NSImage` has no
    /// equivalent, so this goes through `NSBitmapImageRep` on macOS.
    func plutarJPEGData(compressionQuality: CGFloat) -> Data? {
        #if canImport(UIKit)
        return jpegData(compressionQuality: compressionQuality)
        #elseif canImport(AppKit)
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
        #endif
    }
}
