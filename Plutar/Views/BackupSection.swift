import SwiftData
import SwiftUI

/// The backup controls at the top of "Avancé" — shared by iOS's `SettingsSheet`
/// and macOS's `MacSettingsView`, which lay out the rest of that section the
/// same way (a button, then its caption).
///
/// Two blocks, one per kind of backup (`BackupKind`). Each shows the date of
/// its last backup and has its own "Restaurer": the dates are what lets the
/// user choose between the last manual backup and the last automatic one.
/// Only the manual block has a "Sauvegarder" — the automatic one is made by
/// `BackupService.runAutomaticIfDue`.
struct BackupSection: View {
    @Environment(\.modelContext) private var modelContext

    /// `.footnote` on iOS, 13 pt on the Mac — each settings screen's own
    /// caption size.
    let captionFont: Font
    /// The section title's weight — semibold on iOS, regular on the Mac
    /// (like the other titles of each settings screen).
    var titleWeight: Font.Weight = .semibold
    /// iOS: Settings-style cells instead of glass buttons, captions indented
    /// to line up with the cells' text.
    var usesCells = false
    /// The Mac's "Sauvegarde" tab is already named after the section.
    var showsTitle = true

    /// The cached dates first, so the section isn't blank (or wrong, offline)
    /// while CloudKit is asked for the real ones.
    @State private var dates = BackupService.cachedDates()
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var thumbnailProgress: (done: Int, total: Int)?
    @State private var kindToRestore: BackupKind?
    @State private var message: Message?

    private struct Message {
        let title: String
        let text: String
    }

    /// Everything is locked while one operation runs, thumbnails included: a
    /// second restore on top of a first one's downloads would just fight it.
    private var isBusy: Bool { isBackingUp || isRestoring || thumbnailProgress != nil }

    var body: some View {
        Group {
            if showsTitle {
                SettingsSectionView(title: "Sauvegarde et restauration", titleWeight: titleWeight) {
                    blocks
                }
            } else {
                blocks
            }
        }
        .task { dates = await BackupService.lastBackupDates() }
        .confirmationDialog(
            kindToRestore.map { "Restaurer la sauvegarde \($0.label)" } ?? "",
            isPresented: Binding(get: { kindToRestore != nil }, set: { if !$0 { kindToRestore = nil } }),
            titleVisibility: .visible,
            presenting: kindToRestore
        ) { kind in
            Button("Restaurer", role: .destructive) { restore(kind) }
            Button("Annuler", role: .cancel) {}
        } message: { kind in
            Text("Tout le contenu actuel (liens et classement) sera remplacé par celui de la sauvegarde \(kind.label)\(dates[kind].map { " du \(Self.format($0))" } ?? ""). Cette action est irréversible et s'applique aussi à vos autres appareils synchronisés par iCloud.")
        }
        .alert(
            message?.title ?? "",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message?.text ?? "")
        }
    }

    private var blocks: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: backUpManually) {
                    HStack(spacing: 6) {
                        Text("Sauvegarder")
                        if isBackingUp {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .settingsActionStyle(cells: usesCells)
                .disabled(isBusy)

                caption("Sauvegarde manuelle des liens non-lus, lus et du classement des 15 sources principales.", date: .manual)
            }

            VStack(alignment: .leading, spacing: 8) {
                restoreButton(.manual)
                caption("Restauration de la dernière sauvegarde manuelle.")
            }

            VStack(alignment: .leading, spacing: 8) {
                // Intertitle: what follows is about the automatic backup.
                Text("Sauvegarde automatique")
                    .font(captionFont.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, usesCells ? 20 : 0)
                    // Mac: 5pt more room before the button.
                    .padding(.bottom, usesCells ? 0 : 5)
                restoreButton(.automatic)
                caption("Restauration de la sauvegarde automatique.", date: .automatic)
            }

            if let thumbnailProgress, thumbnailProgress.total > 0 {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Vignettes : \(thumbnailProgress.done)/\(thumbnailProgress.total)")
                }
                .font(captionFont)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// A button's caption; with `date`, a line break and then the date and
    /// time of the last backup of that kind.
    private func caption(_ text: String, date kind: BackupKind? = nil) -> some View {
        let dateLine = kind.map { kind in
            "\n" + (dates[kind].map { "Dernière sauvegarde : \(Self.format($0))." } ?? "Aucune sauvegarde \(kind.label).")
        } ?? ""
        return Text(text + dateLine)
            .font(captionFont)
            .foregroundStyle(.secondary)
            .padding(.horizontal, usesCells ? 20 : 0)
    }

    private func restoreButton(_ kind: BackupKind) -> some View {
        Button(role: .destructive) {
            kindToRestore = kind
        } label: {
            Text("Restaurer…")
        }
        .settingsActionStyle(cells: usesCells)
        .disabled(dates[kind] == nil || isBusy)
    }

    private func backUpManually() {
        isBackingUp = true
        Task {
            defer { isBackingUp = false }
            do {
                dates[.manual] = try await BackupService.backUp(.manual, from: modelContext)
            } catch {
                message = Message(title: "Sauvegarde impossible", text: error.localizedDescription)
            }
        }
    }

    private func restore(_ kind: BackupKind) {
        isRestoring = true
        Task {
            do {
                let summary = try await BackupService.restore(kind, into: modelContext)
                // Set before `isRestoring` drops, so the buttons stay locked
                // across the hand-over; the line only shows once there's a
                // total to show.
                thumbnailProgress = (0, 0)
                isRestoring = false
                message = Message(title: "Restauration terminée", text: Self.summaryText(summary))
                await LinkMetadataEnricher.regenerateMissingThumbnails(in: modelContext) { done, total in
                    thumbnailProgress = (done, total)
                }
                thumbnailProgress = nil
            } catch {
                isRestoring = false
                message = Message(title: "Restauration impossible", text: error.localizedDescription)
            }
        }
    }

    private static func summaryText(_ summary: RestoreSummary) -> String {
        let count = "\(summary.linkCount) \(summary.linkCount > 1 ? "liens" : "lien")"
        return "L'app contient maintenant \(count) (\(summary.added) ajouté\(summary.added > 1 ? "s" : ""), \(summary.removed) supprimé\(summary.removed > 1 ? "s" : "")). Les vignettes manquantes sont récupérées en arrière-plan."
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM yyyy 'à' HH:mm"
        return f
    }()

    private static func format(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
