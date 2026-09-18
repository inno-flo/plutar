import SwiftUI
import LinkPresentation

/// Minimal confirmation screen shown in the share sheet — shared by both
/// `PlutarShare` (iOS) and `PlutarShareMac` (macOS), each hosting it via
/// their own `ShareViewController` (`UIHostingController`/`NSHostingController`
/// respectively). Deliberately not a re-skin of `RootView`/`MacRootView` —
/// the extension process is short-lived and this is the only screen it ever
/// shows, so it borrows just the accent color and wordmark treatment rather
/// than pulling in `AppTheme`.
struct ShareView: View {
    let host: String
    @State var title: String
    /// Needed only to fetch the real page title below (macOS) — the source
    /// app's own share payload rarely includes one (Firefox and most
    /// third-party apps hand over just the URL), so `title` here is often
    /// that same URL string, which is what the field showed instead of an
    /// actual title.
    let url: URL
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var background: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.97)
    }

    /// Whether `title` is still whatever fallback `ShareViewController` used
    /// (the bare host, or the URL itself) rather than something the source
    /// app actually supplied — mirrors `LinkMetadataEnricher`'s own
    /// `isFallbackTitle` check for the same reason: never overwrite a title
    /// that came from somewhere real.
    private var isFallbackTitle: Bool {
        title == host || title == url.absoluteString
    }

    /// Fetches the page's real title via `LPMetadataProvider` — the same
    /// mechanism `LinkMetadataEnricher` uses in the main app, just run here
    /// too so the confirmation screen doesn't show a bare URL where a title
    /// belongs when the source app supplied none. macOS only for now (see
    /// `.task` below) — iOS shares already skew toward apps that do include
    /// a real title (Safari's JS preprocessing, Notes, etc.).
    private func fetchRealTitle() async {
        guard isFallbackTitle else { return }
        let provider = LPMetadataProvider()
        provider.timeout = 8
        guard let metadata = try? await provider.startFetchingMetadata(for: url),
              let fetched = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fetched.isEmpty
        else { return }
        // Still the fallback — the user hasn't typed anything of their own
        // in the meantime — otherwise this would clobber an edit made while
        // the fetch was in flight.
        guard isFallbackTitle else { return }
        title = fetched
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title)
                        .font(.system(size: 15))
                        // macOS's `.formStyle(.grouped)` below renders a
                        // `TextField`'s title as a permanent leading label
                        // next to the field, unlike iOS's Form (where it's
                        // just placeholder text inside the empty field) —
                        // hidden here so the row is just the field itself.
                        #if os(macOS)
                        .labelsHidden()
                        #endif
                } header: {
                    Text(host)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            #if os(macOS)
            // macOS's default Form style has no side insets of its own
            // (unlike iOS's grouped-list look), so the label and text field
            // ran flush against the window's left/right edges. `.grouped`
            // adds the same breathing room iOS gets for free.
            .formStyle(.grouped)
            #endif
            .navigationTitle("plutar")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                        .font(.system(size: 17))
                        .foregroundStyle(.black)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { onSave(title) }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            #endif
        }
        #if os(macOS)
        .task { await fetchRealTitle() }
        // A share extension's SwiftUI content is embedded as a child view
        // controller inside the host app's own view hierarchy, not set as
        // any window's `contentViewController` — so `.toolbar` has no
        // window toolbar to attach to and silently renders nothing here,
        // leaving no way to confirm or cancel. Plain buttons below the form
        // render regardless of window chrome.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Annuler", action: onCancel)
                Spacer()
                Button("Ajouter") { onSave(title) }
                    .keyboardShortcut(.defaultAction)
            }
            .tint(.primary)
            .padding()
        }
        #endif
        .tint(Color(red: 1, green: 0.31, blue: 0))
        .background(background)
    }
}

/// Shown instead of `ShareView` when no URL could be extracted, or when the
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
        // See the matching comment in `ShareView` above: `.toolbar` renders
        // nothing here, which is what made this dialog impossible to
        // dismiss on macOS. A plain button in the content area always shows.
        .safeAreaInset(edge: .bottom) {
            Button("OK", action: onDismiss)
                .keyboardShortcut(.defaultAction)
                .padding()
        }
        #endif
        .tint(Color(red: 1, green: 0.31, blue: 0))
    }
}
