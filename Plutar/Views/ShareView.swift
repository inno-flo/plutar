import SwiftUI

/// The app's accent orange (`AppTheme.accent`, #FF4F00) — `AppTheme` itself
/// isn't compiled into the share extensions.
private let shareAccent = Color(red: 1, green: 0.31, blue: 0)

/// Brief HUD-style confirmation (a checkmark on a translucent rounded square,
/// centered, no text) shown once a shared link has been saved — the share
/// sequence has no editing/confirmation step any more: the extension saves
/// the link the moment it's extracted, shows this for a moment, then
/// dismisses itself (`ShareViewController.finishAfterDelay`). Title fixing is
/// left to `LinkMetadataEnricher` in the main app. Shared by `PlutarShare`
/// (iOS) and `PlutarShareMac` (macOS); deliberately not a re-skin of
/// `RootView`/`MacRootView` — it borrows just the accent color.
struct ShareSavedView: View {
    var body: some View {
        Image(systemName: "square.and.arrow.up.badge.checkmark")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(shareAccent)
            .frame(width: 120, height: 120)
            #if os(macOS)
            // macOS can't drop the window the extension is hosted in, so the
            // square and everything around it share the window's own
            // background color rather than a translucent material that would
            // read as a second, differently-tinted panel on top of it.
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            #else
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
    }
}

/// Shown instead of `ShareSavedView` when no URL could be extracted, or when the
/// shared store (the App Group container) couldn't be opened.
struct ShareErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            // A `Text` still wraps within a fixed-size share-extension
            // window, but a long underlying error (a real SwiftData/CloudKit
            // message, not our short hardcoded ones) can need more height
            // than the window has — the extra lines were simply clipped off
            // rather than shown. `ScrollView` keeps the whole message
            // reachable no matter how long it is.
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .navigationTitle("plutar")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", action: onDismiss)
                }
            }
            #endif
        }
        #if os(macOS)
        // A share extension's SwiftUI content isn't a window's own content view
        // controller, so `.toolbar` renders
        // nothing here, which is what made this dialog impossible to
        // dismiss on macOS. A plain button in the content area always shows.
        .safeAreaInset(edge: .bottom) {
            Button("OK", action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .padding()
        }
        #endif
        .tint(shareAccent)
    }
}
