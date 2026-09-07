import Foundation

/// Raw description of one demo link, before it is turned into a `LinkItem`
/// anchored on "now". `dayOffset` 0 = today, 9 = nine days ago.
private struct SeedEntry {
    let title: String
    let host: String
    let pathHint: String
    let excerpt: String
    let colorHex: String
    let initial: String
    let sourceApp: String
    let hasThumbnail: Bool
    let dayOffset: Int
    let hour: Int
    let minute: Int
}

/// Generates 200 demo links used before the real Share Extension exists (no
/// paid developer account yet — see project notes), spread across the same
/// 6 test sources (macrumors.com, theverge.com, daringfireball.net,
/// nytimes.com, lemonde.fr, reuters.com/technology). Each source's quantity
/// is randomized on every call — see `makeLinkItems` — by cycling that
/// source's handful of content templates to fill its quota.
enum SeedData {

    private static let macrumors = "macrumors.com"
    private static let macrumorsColor = "#E8433D"
    private static let theverge = "theverge.com"
    private static let thevergeColor = "#6C5CE7"
    private static let daringfireball = "daringfireball.net"
    private static let daringfireballColor = "#2F5FD0"
    private static let nytimes = "nytimes.com"
    private static let nytimesColor = "#222222"
    private static let lemonde = "lemonde.fr"
    private static let lemondeColor = "#B01E24"
    private static let reuters = "reuters.com"
    private static let reutersColor = "#FF8000"

    private static let macrumorsItems: [SeedEntry] = [
        SeedEntry(title: "iOS 26.1 Beta Adds New Control Center Customization Options", host: macrumors, pathHint: "ios-26-1-beta-control-center", excerpt: "The update lets users rearrange and resize modules for the first time.", colorHex: macrumorsColor, initial: "M", sourceApp: "Safari", hasThumbnail: true, dayOffset: 0, hour: 9, minute: 12),
        SeedEntry(title: "Apple Reportedly Testing Foldable iPhone for 2027 Launch", host: macrumors, pathHint: "foldable-iphone-2027-testing", excerpt: "Supply chain sources point to a book-style hinge similar to Samsung's.", colorHex: macrumorsColor, initial: "M", sourceApp: "Safari", hasThumbnail: true, dayOffset: 2, hour: 8, minute: 41),
        SeedEntry(title: "M5 MacBook Pro Benchmarks Leak Ahead of Expected October Unveil", host: macrumors, pathHint: "m5-macbook-pro-benchmarks-leak", excerpt: "Geekbench listings show a healthy jump in single-core performance.", colorHex: macrumorsColor, initial: "M", sourceApp: "Safari", hasThumbnail: false, dayOffset: 4, hour: 7, minute: 55),
        SeedEntry(title: "Apple Vision Pro Software Update Brings Widescreen Mac Virtual Display", host: macrumors, pathHint: "vision-pro-widescreen-mac-display", excerpt: "The ultrawide mode roughly doubles the usable horizontal space.", colorHex: macrumorsColor, initial: "M", sourceApp: "Mastodon", hasThumbnail: true, dayOffset: 6, hour: 10, minute: 3),
        SeedEntry(title: "Everything New in visionOS 3: Features, Compatible Devices, and More", host: macrumors, pathHint: "visionos-3-everything-new", excerpt: "A full rundown of what shipped and what's still coming later this year.", colorHex: macrumorsColor, initial: "M", sourceApp: "Safari", hasThumbnail: true, dayOffset: 8, hour: 9, minute: 20),
    ]

    private static let thevergeItems: [SeedEntry] = [
        SeedEntry(title: "Google's New AI Search Mode Is Rolling Out to Everyone", host: theverge, pathHint: "google-ai-search-mode-rollout", excerpt: "The conversational results panel is now the default for most queries.", colorHex: thevergeColor, initial: "V", sourceApp: "Safari", hasThumbnail: true, dayOffset: 0, hour: 14, minute: 30),
        SeedEntry(title: "The Best Laptops for 2026, Tested and Ranked", host: theverge, pathHint: "best-laptops-2026-tested-ranked", excerpt: "Our picks after months of battery, display, and build-quality testing.", colorHex: thevergeColor, initial: "V", sourceApp: "Safari", hasThumbnail: true, dayOffset: 1, hour: 16, minute: 5),
        SeedEntry(title: "Amazon's Next Kindle Finally Gets a Color Screen That Doesn't Feel Like a Gimmick", host: theverge, pathHint: "kindle-color-screen-review", excerpt: "It's still an E Ink panel, but the tuning makes a real difference.", colorHex: thevergeColor, initial: "V", sourceApp: "Notes", hasThumbnail: false, dayOffset: 3, hour: 18, minute: 12),
        SeedEntry(title: "Meta's Smart Glasses Are Starting to Feel Like a Real Product", host: theverge, pathHint: "meta-smart-glasses-real-product", excerpt: "Three generations in, the hardware finally matches the pitch.", colorHex: thevergeColor, initial: "V", sourceApp: "Safari", hasThumbnail: true, dayOffset: 5, hour: 15, minute: 47),
        SeedEntry(title: "Netflix Is Raising Prices Again — Here's What You'll Pay Now", host: theverge, pathHint: "netflix-price-increase-2026", excerpt: "Every tier goes up, with the ad-supported plan seeing the biggest jump.", colorHex: thevergeColor, initial: "V", sourceApp: "Safari", hasThumbnail: false, dayOffset: 7, hour: 13, minute: 26),
    ]

    private static let daringfireballItems: [SeedEntry] = [
        SeedEntry(title: "The Talk Show: 'Live From the Liquid Glass Launch'", host: daringfireball, pathHint: "talk-show-liquid-glass-launch", excerpt: "A wide-ranging conversation recorded the night of the keynote.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: false, dayOffset: 0, hour: 21, minute: 8),
        SeedEntry(title: "Regarding Apple's Q3 Earnings Call", host: daringfireball, pathHint: "apple-q3-earnings-call-notes", excerpt: "A few numbers worth pulling out of an otherwise routine call.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: false, dayOffset: 1, hour: 20, minute: 41),
        SeedEntry(title: "★ On the New MacBook Pro's Display", host: daringfireball, pathHint: "new-macbook-pro-display", excerpt: "Brighter, yes, but the color consistency is the real story.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: true, dayOffset: 2, hour: 19, minute: 55),
        SeedEntry(title: "Why the App Store Fee Changes Actually Matter", host: daringfireball, pathHint: "app-store-fee-changes-matter", excerpt: "The headline percentage isn't where the interesting part is.", colorHex: daringfireballColor, initial: "D", sourceApp: "Messages", hasThumbnail: false, dayOffset: 3, hour: 22, minute: 2),
        SeedEntry(title: "A Quick Thought on Threads' New Edit Feature", host: daringfireball, pathHint: "threads-edit-feature-thought", excerpt: "Short and to the point, as these link posts usually are.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: false, dayOffset: 4, hour: 20, minute: 17),
        SeedEntry(title: "Panic's Playdate Gets a Surprising Second Wind", host: daringfireball, pathHint: "playdate-second-wind", excerpt: "A new season of exclusive games is bringing back old owners.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: true, dayOffset: 5, hour: 21, minute: 34),
        SeedEntry(title: "The Case Against 'AI' as a Product Category Name", host: daringfireball, pathHint: "case-against-ai-category-name", excerpt: "A pet peeve, argued at just the right length.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: false, dayOffset: 6, hour: 19, minute: 49),
        SeedEntry(title: "Nilay Patel on the State of Android Tablets", host: daringfireball, pathHint: "nilay-patel-android-tablets", excerpt: "Worth reading even if you have zero interest in Android.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: false, dayOffset: 7, hour: 20, minute: 58),
        SeedEntry(title: "Six Colors' Excellent Breakdown of iPadOS 26", host: daringfireball, pathHint: "six-colors-ipados-26-breakdown", excerpt: "The definitive multitasking explainer, linked without much comment.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: true, dayOffset: 8, hour: 18, minute: 22),
        SeedEntry(title: "★ My Initial Vision Pro 2 Impressions", host: daringfireball, pathHint: "vision-pro-2-initial-impressions", excerpt: "Lighter, sharper, and still an odd thing to wear in public.", colorHex: daringfireballColor, initial: "D", sourceApp: "Safari", hasThumbnail: true, dayOffset: 9, hour: 21, minute: 15),
    ]

    private static let nytimesItems: [SeedEntry] = [
        SeedEntry(title: "Tech Giants Face New Antitrust Scrutiny in Europe", host: nytimes, pathHint: "technology/eu-antitrust-tech-giants", excerpt: "Regulators are examining bundling practices across three companies.", colorHex: nytimesColor, initial: "N", sourceApp: "Safari", hasThumbnail: true, dayOffset: 1, hour: 7, minute: 30),
        SeedEntry(title: "Inside the Race to Build the Next Generation of Chips", host: nytimes, pathHint: "technology/next-generation-chips-race", excerpt: "A look at three companies betting on very different architectures.", colorHex: nytimesColor, initial: "N", sourceApp: "Safari", hasThumbnail: true, dayOffset: 3, hour: 6, minute: 50),
        SeedEntry(title: "How Artificial Intelligence Is Reshaping Newsrooms", host: nytimes, pathHint: "business/media/ai-newsrooms", excerpt: "Editors describe what changed, and what they refused to automate.", colorHex: nytimesColor, initial: "N", sourceApp: "Safari", hasThumbnail: false, dayOffset: 5, hour: 8, minute: 5),
        SeedEntry(title: "The Quiet Return of the Personal Blog", host: nytimes, pathHint: "technology/personal-blogs-comeback", excerpt: "A small but real shift away from algorithm-driven feeds.", colorHex: nytimesColor, initial: "N", sourceApp: "Safari", hasThumbnail: false, dayOffset: 7, hour: 7, minute: 18),
        SeedEntry(title: "What a Decade of Remote Work Did to American Cities", host: nytimes, pathHint: "upshot/remote-work-decade-cities", excerpt: "Downtown foot traffic still hasn't recovered in most metro areas.", colorHex: nytimesColor, initial: "N", sourceApp: "Safari", hasThumbnail: true, dayOffset: 9, hour: 6, minute: 40),
    ]

    private static let lemondeItems: [SeedEntry] = [
        SeedEntry(title: "Comment l'intelligence artificielle transforme la recherche scientifique", host: lemonde, pathHint: "pixels/ia-recherche-scientifique", excerpt: "Des chercheurs racontent comment leurs méthodes de travail ont changé.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: true, dayOffset: 0, hour: 12, minute: 5),
        SeedEntry(title: "La bataille des semi-conducteurs relance la géopolitique industrielle", host: lemonde, pathHint: "economie/bataille-semi-conducteurs", excerpt: "Trois blocs économiques se disputent désormais chaque usine.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: true, dayOffset: 1, hour: 11, minute: 22),
        SeedEntry(title: "Vie privée en ligne : ce que change le nouveau règlement européen", host: lemonde, pathHint: "pixels/reglement-vie-privee-europe", excerpt: "Les plateformes ont six mois pour se mettre en conformité.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: false, dayOffset: 2, hour: 13, minute: 40),
        SeedEntry(title: "Pourquoi les grandes villes françaises repensent leurs réseaux de chaleur", host: lemonde, pathHint: "planete/reseaux-de-chaleur-villes", excerpt: "Une infrastructure discrète, mais décisive pour la transition.", colorHex: lemondeColor, initial: "L", sourceApp: "Messages", hasThumbnail: true, dayOffset: 3, hour: 10, minute: 15),
        SeedEntry(title: "Le marché de l'occasion, nouvel eldorado de la tech", host: lemonde, pathHint: "pixels/marche-occasion-tech", excerpt: "Reconditionnement et revente pèsent désormais plusieurs milliards.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: false, dayOffset: 4, hour: 12, minute: 48),
        SeedEntry(title: "Enquête : dans les coulisses d'un data center breton", host: lemonde, pathHint: "pixels/enquete-data-center-breton", excerpt: "Chaleur, eau, électricité : le vrai coût d'un service en ligne.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: true, dayOffset: 5, hour: 11, minute: 3),
        SeedEntry(title: "Les universités françaises face à l'essor des outils génératifs", host: lemonde, pathHint: "campus/universites-outils-generatifs", excerpt: "Entre interdiction et intégration, les postures varient beaucoup.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: false, dayOffset: 6, hour: 13, minute: 27),
        SeedEntry(title: "Climat : la sobriété numérique reste un angle mort des politiques publiques", host: lemonde, pathHint: "planete/sobriete-numerique-angle-mort", excerpt: "Peu de collectivités mesurent réellement l'empreinte de leurs services.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: true, dayOffset: 7, hour: 10, minute: 52),
        SeedEntry(title: "Portrait d'une entrepreneuse qui réinvente le recyclage électronique", host: lemonde, pathHint: "economie/portrait-recyclage-electronique", excerpt: "Une filière artisanale qui grandit plus vite que prévu.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: true, dayOffset: 8, hour: 12, minute: 30),
        SeedEntry(title: "Le retour en grâce du minitel comme objet culte", host: lemonde, pathHint: "m-le-mag/minitel-objet-culte", excerpt: "Une poignée de collectionneurs entretient encore le réseau.", colorHex: lemondeColor, initial: "L", sourceApp: "Safari", hasThumbnail: false, dayOffset: 9, hour: 14, minute: 9),
    ]

    private static let reutersItems: [SeedEntry] = [
        SeedEntry(title: "Chip Stocks Rally on Strong Demand Forecasts", host: reuters, pathHint: "technology/chip-stocks-rally-demand", excerpt: "Analysts raised targets across the board after the guidance update.", colorHex: reutersColor, initial: "R", sourceApp: "Safari", hasThumbnail: false, dayOffset: 0, hour: 17, minute: 45),
        SeedEntry(title: "EU Regulators Open Fresh Probe Into Cloud Computing Market", host: reuters, pathHint: "technology/eu-cloud-computing-probe", excerpt: "The inquiry focuses on egress fees and switching costs.", colorHex: reutersColor, initial: "R", sourceApp: "Safari", hasThumbnail: false, dayOffset: 2, hour: 16, minute: 33),
        SeedEntry(title: "Startup Raises $200 Million to Build AI Data Centers", host: reuters, pathHint: "technology/startup-ai-data-centers-funding", excerpt: "The round values the two-year-old company at $1.8 billion.", colorHex: reutersColor, initial: "R", sourceApp: "Safari", hasThumbnail: true, dayOffset: 4, hour: 15, minute: 58),
        SeedEntry(title: "Automakers Accelerate Software-Defined Vehicle Plans", host: reuters, pathHint: "technology/automakers-software-defined-vehicles", excerpt: "Several manufacturers moved up their platform timelines this quarter.", colorHex: reutersColor, initial: "R", sourceApp: "Safari", hasThumbnail: false, dayOffset: 6, hour: 17, minute: 11),
        SeedEntry(title: "Social Media Platforms Brace for New Content Rules", host: reuters, pathHint: "technology/social-media-new-content-rules", excerpt: "Compliance teams have until the end of the year to adjust.", colorHex: reutersColor, initial: "R", sourceApp: "Safari", hasThumbnail: false, dayOffset: 8, hour: 16, minute: 24),
    ]

    /// Real-world subdomain for each host (daringfireball.net and
    /// theverge.com don't use "www.", the others do).
    private static func urlHost(for host: String) -> String {
        switch host {
        case daringfireball, theverge: return host
        default: return "www.\(host)"
        }
    }

    /// A handful of extra links used to simulate an incoming share (there is
    /// no real Share Extension yet — see project notes).
    struct PoolEntry: Identifiable {
        let id = UUID()
        let title: String
        let host: String
        let pathHint: String
        let excerpt: String
        let colorHex: String
        let initial: String
        let sourceApp: String
        let hasThumbnail: Bool

        func makeLinkItem() -> LinkItem {
            LinkItem(
                title: title,
                urlString: "https://\(SeedData.urlHost(for: host))/\(pathHint)",
                host: host, initial: initial, colorHex: colorHex, dateAdded: Date(),
                sourceApp: sourceApp, excerpt: excerpt, hasThumbnail: hasThumbnail
            )
        }
    }

    static let pool: [PoolEntry] = [
        PoolEntry(title: "Apple Music Adds Lossless Spatial Audio Mixing for User Playlists", host: macrumors, pathHint: "apple-music-lossless-spatial-mixing", excerpt: "The feature rolls out gradually starting with iOS 26.1.", colorHex: macrumorsColor, initial: "M", sourceApp: "Safari", hasThumbnail: true),
        PoolEntry(title: "This Tiny USB-C Dongle Fixed My Biggest Travel Annoyance", host: theverge, pathHint: "usbc-dongle-travel-review", excerpt: "A $19 accessory that finally does what it promises.", colorHex: thevergeColor, initial: "V", sourceApp: "Safari", hasThumbnail: false),
        PoolEntry(title: "Regulators Weigh New Rules for AI-Generated Content Labeling", host: reuters, pathHint: "technology/ai-content-labeling-rules", excerpt: "A draft proposal could require disclosure on synthetic media.", colorHex: reutersColor, initial: "R", sourceApp: "Safari", hasThumbnail: false),
    ]

    /// The 6 test sources' own content templates, cycled to fill each
    /// source's randomly assigned quota below.
    private static var sourceTemplates: [[SeedEntry]] {
        [macrumorsItems, thevergeItems, daringfireballItems, nytimesItems, lemondeItems, reutersItems]
    }

    /// Splits `total` randomly into `buckets` positive integers summing to
    /// exactly `total` — each source ends up with at least one link.
    private static func randomQuantities(total: Int, buckets: Int) -> [Int] {
        guard buckets > 0 else { return [] }
        var quantities = Array(repeating: 1, count: buckets)
        for _ in 0..<(total - buckets) {
            quantities[Int.random(in: 0..<buckets)] += 1
        }
        return quantities.shuffled()
    }

    /// Builds 200 seed `LinkItem`s, anchored on `now` (defaults to the
    /// moment the store is seeded/regenerated). Each source's share of the
    /// 200 is re-randomized on every call — see the type's own doc comment.
    static func makeLinkItems(now: Date = Date()) -> [LinkItem] {
        let calendar = Calendar.current
        let quantities = randomQuantities(total: 200, buckets: sourceTemplates.count)

        var items: [LinkItem] = []
        var dayCursor = 0
        for (templates, quantity) in zip(sourceTemplates, quantities) {
            for i in 0..<quantity {
                let entry = templates[i % templates.count]
                // Spread across the last 30 days instead of all landing on
                // the same timestamp when a template repeats to fill quota.
                let day = calendar.date(byAdding: .day, value: -(dayCursor % 30), to: now) ?? now
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = entry.hour
                components.minute = (entry.minute + i) % 60
                let timestamp = calendar.date(from: components) ?? day

                let urlString = "https://\(Self.urlHost(for: entry.host))/\(entry.pathHint)"

                items.append(LinkItem(
                    title: entry.title,
                    urlString: urlString,
                    host: entry.host,
                    initial: entry.initial,
                    colorHex: entry.colorHex,
                    dateAdded: timestamp,
                    sourceApp: entry.sourceApp,
                    excerpt: entry.excerpt,
                    hasThumbnail: entry.hasThumbnail
                ))
                dayCursor += 1
            }
        }
        return items
    }
}
