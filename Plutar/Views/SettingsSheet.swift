import SwiftUI

/// The "Affichage" drawer from the mockup: theme, font, density and timeline
/// layout, plus a destructive "Vider le fil" action.
struct SettingsSheet: View {
    @Binding var theme: AppTheme
    @Binding var appFont: AppFont
    @Binding var compact: Bool
    @Binding var layout: LinkLayout
    let onClearAll: () -> Void
    let onClose: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Police") {
                        HStack(spacing: 8) {
                            ForEach(AppFont.allCases) { f in
                                pill(f.label, isActive: appFont == f, font: f.font(size: 13)) {
                                    appFont = f
                                }
                            }
                        }
                    }

                    section("Thème") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(AppTheme.allCases) { t in
                                Button {
                                    theme = t
                                } label: {
                                    HStack(spacing: 7) {
                                        Circle().fill(t.swatch).frame(width: 12, height: 12)
                                        Text(t.label)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(PillButtonStyle(isActive: theme == t))
                            }
                        }
                    }

                    section("Densité") {
                        HStack(spacing: 8) {
                            pill("Complet", isActive: !compact) { compact = false }
                            pill("Compact · sans image", isActive: compact) { compact = true }
                        }
                    }

                    section("Mise en page de la timeline") {
                        HStack(spacing: 8) {
                            ForEach(LinkLayout.allCases) { l in
                                pill(l.label, isActive: layout == l) { layout = l }
                            }
                        }
                    }

                    Button(role: .destructive, action: onClearAll) {
                        Text("Vider le fil")
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle("Affichage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", action: onClose)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func pill(_ label: String, isActive: Bool, font: Font? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(font)
        }
        .buttonStyle(PillButtonStyle(isActive: isActive))
    }
}

private struct PillButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(isActive ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
