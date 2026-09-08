import SwiftUI
import SwiftData

@main
struct PlutarApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: LinkItem.self, SourceRank.self)
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
        seedIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    /// Populates the store with the 200 demo links on first launch only.
    private func seedIfNeeded() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<LinkItem>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for item in SeedData.makeLinkItems() {
            context.insert(item)
            SourceRank.bump(item.host, in: context)
        }
        try? context.save()
    }
}
