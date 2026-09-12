import SwiftUI

/// Minimal confirmation screen shown in the share sheet. Deliberately not a
/// re-skin of `RootView` — the extension process is short-lived and this is
/// the only screen it ever shows, so it borrows just the accent color and
/// wordmark treatment rather than pulling in `AppTheme`.
struct ShareView: View {
    let host: String
    @State var title: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var background: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.97)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title)
                        .font(.system(size: 15))
                } header: {
                    Text(host)
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .navigationTitle("plutar")
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
        }
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
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("plutar")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", action: onDismiss)
                }
            }
        }
        .tint(Color(red: 1, green: 0.31, blue: 0))
    }
}
