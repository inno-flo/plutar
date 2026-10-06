import CloudKit
import Foundation
import SwiftData

/// The two backups. Each one is a single CloudKit record with a fixed name, so
/// there are exactly two of them for good — never a third, and a new backup of
/// a kind overwrites the previous one by saving over the same record ID.
enum BackupKind: String, CaseIterable {
    case manual
    case automatic

    var recordName: String {
        switch self {
        case .manual: "backup-manual"
        case .automatic: "backup-auto"
        }
    }

    /// Adjective used in the settings UI ("sauvegarde manuelle").
    var label: String {
        switch self {
        case .manual: "manuelle"
        case .automatic: "automatique"
        }
    }
}

enum BackupError: LocalizedError {
    case iCloudUnavailable
    case network
    case temporarilyUnavailable
    case noBackup
    case invalidFile
    case newerVersion
    case storeUnavailable
    case saveFailed
    case cloudKit(String)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: "iCloud n'est pas disponible. Vérifiez que vous êtes connecté à iCloud."
        case .network: "Connexion à iCloud impossible. Vérifiez votre connexion internet."
        case .temporarilyUnavailable: "iCloud est momentanément indisponible. Réessayez plus tard."
        case .noBackup: "Aucune sauvegarde n'a été trouvée."
        case .invalidFile: "La sauvegarde est illisible."
        case .newerVersion: "Cette sauvegarde vient d'une version plus récente de Plutar."
        case .storeUnavailable: "Le stockage de Plutar est indisponible."
        case .saveFailed: "Les changements n'ont pas pu être enregistrés."
        case .cloudKit(let message): message
        }
    }
}

/// What a backup holds: every link (all its stored fields, thumbnails
/// excluded — they're re-downloaded after a restore) and the source ranking.
/// Plain value types, so it can be built on the main actor and encoded,
/// compressed and uploaded off it.
struct BackupFile: Codable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var links: [LinkRecord]
    var ranks: [RankRecord]

    struct LinkRecord: Codable {
        var id: UUID
        var title: String
        var urlString: String
        var host: String
        var initial: String
        var colorHex: String
        var dateAdded: Date
        var sourceApp: String
        var excerpt: String
        var isRead: Bool
        var thumbnailFileName: String?
        var metadataFetched: Bool
        var excerptFetchAttempted: Bool
        var isPinned: Bool
        var sourceName: String?
        var sourceNameFetchAttempted: Bool

        enum CodingKeys: String, CodingKey {
            case id, title, urlString, host, initial, colorHex, dateAdded, sourceApp, excerpt, isRead
            case thumbnailFileName, metadataFetched, excerptFetchAttempted, isPinned, sourceName
            case sourceNameFetchAttempted
        }

        /// Tolerant of absent keys: `LinkItem` has already grown fields over
        /// time (`isPinned`, `sourceName`…), so a backup written before one
        /// existed must still decode. A missing key takes `LinkItem`'s own
        /// default; only the identity (`id`, `urlString`) is required.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            urlString = try c.decode(String.self, forKey: .urlString)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
            initial = try c.decodeIfPresent(String.self, forKey: .initial) ?? ""
            colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#000000"
            dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date.now
            sourceApp = try c.decodeIfPresent(String.self, forKey: .sourceApp) ?? ""
            excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
            isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
            thumbnailFileName = try c.decodeIfPresent(String.self, forKey: .thumbnailFileName)
            metadataFetched = try c.decodeIfPresent(Bool.self, forKey: .metadataFetched) ?? true
            excerptFetchAttempted = try c.decodeIfPresent(Bool.self, forKey: .excerptFetchAttempted) ?? true
            isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
            sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
            sourceNameFetchAttempted = try c.decodeIfPresent(Bool.self, forKey: .sourceNameFetchAttempted) ?? false
        }
    }

    struct RankRecord: Codable {
        var host: String
        var count: Int
    }
}

extension BackupFile.LinkRecord {
    init(_ item: LinkItem) {
        id = item.id
        title = item.title
        urlString = item.urlString
        host = item.host
        initial = item.initial
        colorHex = item.colorHex
        dateAdded = item.dateAdded
        sourceApp = item.sourceApp
        excerpt = item.excerpt
        isRead = item.isRead
        thumbnailFileName = item.thumbnailFileName
        metadataFetched = item.metadataFetched
        excerptFetchAttempted = item.excerptFetchAttempted
        isPinned = item.isPinned
        sourceName = item.sourceName
        sourceNameFetchAttempted = item.sourceNameFetchAttempted
    }

    func makeItem() -> LinkItem {
        LinkItem(
            id: id,
            title: title,
            urlString: urlString,
            host: host,
            initial: initial,
            colorHex: colorHex,
            dateAdded: dateAdded,
            sourceApp: sourceApp,
            excerpt: excerpt,
            isRead: isRead,
            thumbnailFileName: thumbnailFileName,
            metadataFetched: metadataFetched,
            excerptFetchAttempted: excerptFetchAttempted,
            isPinned: isPinned,
            sourceName: sourceName,
            sourceNameFetchAttempted: sourceNameFetchAttempted
        )
    }

    /// Overwrites `item` with this record's values — only the fields that
    /// actually differ. A blind write of all fifteen would mark every restored
    /// link as modified and make CloudKit re-export links that haven't changed.
    func apply(to item: LinkItem) {
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<LinkItem, T>, _ value: T) {
            if item[keyPath: keyPath] != value { item[keyPath: keyPath] = value }
        }
        set(\.title, title)
        set(\.urlString, urlString)
        set(\.host, host)
        set(\.initial, initial)
        set(\.colorHex, colorHex)
        set(\.dateAdded, dateAdded)
        set(\.sourceApp, sourceApp)
        set(\.excerpt, excerpt)
        set(\.isRead, isRead)
        set(\.thumbnailFileName, thumbnailFileName)
        set(\.metadataFetched, metadataFetched)
        set(\.excerptFetchAttempted, excerptFetchAttempted)
        set(\.isPinned, isPinned)
        set(\.sourceName, sourceName)
        set(\.sourceNameFetchAttempted, sourceNameFetchAttempted)
    }
}

/// JSON → LZFSE, and back. Dates are ISO 8601 with milliseconds so links
/// shared within the same second keep their order.
private enum BackupCoding {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plainFormatter = ISO8601DateFormatter()

    static func pack(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        let json = try encoder.encode(file)
        return try (json as NSData).compressed(using: .lzfse) as Data
    }

    static func unpack(_ data: Data) throws -> BackupFile {
        do {
            let json = try (data as NSData).decompressed(using: .lzfse) as Data
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let string = try decoder.singleValueContainer().decode(String.self)
                guard let date = fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(string)")
                    )
                }
                return date
            }
            return try decoder.decode(BackupFile.self, from: json)
        } catch {
            throw BackupError.invalidFile
        }
    }
}

struct RestoreSummary {
    /// Links in the store once the restore is done — the backup's own count.
    let linkCount: Int
    let added: Int
    let updated: Int
    let removed: Int
}

/// Manual and automatic backups of the store's content (links + ranking),
/// kept in CloudKit as two plain `CKRecord`s in the private database's default
/// zone — deliberately *outside* the SwiftData mirror: no schema change (so no
/// device has to be rebuilt), no uniqueness problem (two fixed record names),
/// and still readable when the mirror's own sync is broken.
@MainActor
enum BackupService {
    private nonisolated static let recordType = "Backup"

    private enum Field {
        static let payload = "payload"
        static let linkCount = "linkCount"
        static let version = "version"
    }

    private static let defaults = UserDefaults.standard
    private static let lastAutomaticSuccessKey = "backup.lastAutomaticSuccess"
    private static let attemptDayKey = "backup.automaticAttemptDay"
    private static let attemptCountKey = "backup.automaticAttemptCount"
    private static let maxAutomaticAttemptsPerDay = 2

    private static var isAutomaticRunning = false

    // MARK: - Dates shown in Réglages

    /// The server-side modification date of each backup, as last seen on this
    /// device — shown immediately, then refreshed by `lastBackupDates()`, so
    /// the settings still say something while offline.
    static func cachedDates() -> [BackupKind: Date] {
        BackupKind.allCases.reduce(into: [:]) { dates, kind in
            dates[kind] = defaults.object(forKey: cacheKey(kind)) as? Date
        }
    }

    /// Reads both backups' modification dates from CloudKit (without
    /// downloading their payload). Falls back to the cache when offline; a
    /// backup CloudKit says doesn't exist is dropped from the cache.
    static func lastBackupDates() async -> [BackupKind: Date] {
        do {
            let fetched = try await fetchDates()
            for kind in BackupKind.allCases {
                if let date = fetched.found[kind] {
                    defaults.set(date, forKey: cacheKey(kind))
                } else if fetched.missing.contains(kind) {
                    defaults.removeObject(forKey: cacheKey(kind))
                }
            }
        } catch {
            PlutarLog.store.notice("Backup dates unavailable, showing cached ones: \(String(describing: error), privacy: .public)")
        }
        return cachedDates()
    }

    private static func cacheKey(_ kind: BackupKind) -> String { "backup.lastDate.\(kind.rawValue)" }

    // MARK: - Back up

    /// Writes `kind`'s backup from the store's current content, replacing the
    /// previous one. Returns the date CloudKit recorded.
    @discardableResult
    static func backUp(_ kind: BackupKind, from context: ModelContext) async throws -> Date {
        try requireRealStore(context)
        let file = try snapshot(of: context)
        do {
            let date = try await upload(file, as: kind)
            defaults.set(date, forKey: cacheKey(kind))
            if kind == .automatic { defaults.set(Date(), forKey: lastAutomaticSuccessKey) }
            return date
        } catch {
            throw mapped(error)
        }
    }

    private static func snapshot(of context: ModelContext) throws -> BackupFile {
        let items = try context.fetch(FetchDescriptor<LinkItem>(sortBy: [SortDescriptor(\.dateAdded)]))
        let ranks = try context.fetch(FetchDescriptor<SourceRank>())
        return BackupFile(
            version: BackupFile.currentVersion,
            exportedAt: Date.now,
            links: items.map { BackupFile.LinkRecord($0) },
            ranks: SourceRank.aggregated(ranks).map { BackupFile.RankRecord(host: $0.host, count: $0.count) }
        )
    }

    // MARK: - Restore

    /// Replaces the store's whole content (links + ranking) with `kind`'s
    /// backup. Nothing is touched unless the backup downloaded and decoded
    /// cleanly.
    @discardableResult
    static func restore(_ kind: BackupKind, into context: ModelContext) async throws -> RestoreSummary {
        try requireRealStore(context)
        let file: BackupFile
        do {
            file = try await download(kind)
        } catch {
            throw mapped(error)
        }
        return try apply(file, to: context)
    }

    /// Reconciles the store with `file` by `id` rather than deleting
    /// everything and re-inserting it: the end state is identical, but a link
    /// that's in both keeps its row (and its thumbnail file — no network to
    /// get it back) and CloudKit only has to export what really changed.
    ///
    /// No `await` in here on purpose: the whole reconciliation has to land in
    /// one `persist()` before the context's autosave can see a half-done one.
    private static func apply(_ file: BackupFile, to context: ModelContext) throws -> RestoreSummary {
        let backupIDs = Set(file.links.map(\.id))
        let existing: [LinkItem]
        let existingRanks: [SourceRank]
        do {
            existing = try context.fetch(FetchDescriptor<LinkItem>())
            existingRanks = try context.fetch(FetchDescriptor<SourceRank>())
        } catch {
            PlutarLog.store.error("Restore: could not read the store: \(String(describing: error), privacy: .public)")
            throw BackupError.storeUnavailable
        }

        var kept: [UUID: LinkItem] = [:]
        var removedThumbnails: [String] = []
        var removed = 0
        for item in existing {
            if backupIDs.contains(item.id), kept[item.id] == nil {
                kept[item.id] = item
            } else {
                // Not in the backup — or an extra row for an id already kept
                // (CloudKit can duplicate a record).
                if let name = item.thumbnailFileName { removedThumbnails.append(name) }
                context.delete(item)
                removed += 1
            }
        }

        var added = 0
        var updated = 0
        var seen = Set<UUID>()
        for record in file.links where seen.insert(record.id).inserted {
            if let item = kept[record.id] {
                record.apply(to: item)
                updated += 1
            } else {
                context.insert(record.makeItem())
                added += 1
            }
        }

        var keptRanks: [String: SourceRank] = [:]
        let backupCounts = Dictionary(file.ranks.map { ($0.host, $0.count) }, uniquingKeysWith: { _, last in last })
        for rank in existingRanks {
            if backupCounts[rank.host] != nil, keptRanks[rank.host] == nil {
                keptRanks[rank.host] = rank
            } else {
                context.delete(rank)
            }
        }
        for (host, count) in backupCounts {
            if let rank = keptRanks[host] {
                if rank.count != count { rank.count = count }
            } else {
                context.insert(SourceRank(host: host, count: count))
            }
        }

        guard context.persist("restore") else {
            context.rollback()
            throw BackupError.saveFailed
        }

        // Only now: `deleteLinks` would remove these files *before* the save
        // and a failed save couldn't bring them back. A duplicate row shares
        // its kept twin's `<id>.jpg`, hence the filter.
        let stillReferenced = Set(file.links.compactMap(\.thumbnailFileName))
        for name in removedThumbnails where !stillReferenced.contains(name) {
            SharedStore.deleteThumbnailFile(named: name)
        }
        return RestoreSummary(linkCount: seen.count, added: added, updated: updated, removed: removed)
    }

    // MARK: - Automatic backup

    /// Backs up automatically if one is due and it's safe to — a cheap call
    /// made at launch, on every return to the foreground and on every
    /// successful CloudKit import (`StoreLifecycle`), and only does real work
    /// when everything lines up:
    ///
    /// - due: this device hasn't made one today;
    /// - synced: an import has succeeded today — until then the store may
    ///   only hold part of the iCloud content, and backing it up would
    ///   overwrite a good backup with a partial one. The backup is simply put
    ///   off (no attempt is spent) and the next successful import wakes it up;
    /// - at most two attempts a day: a failed upload is retried once, at the
    ///   next call, then left to tomorrow.
    ///
    /// A failure is logged and never shown.
    static func runAutomaticIfDue(in context: ModelContext) async {
        guard !isAutomaticRunning, isAutomaticDue else { return }
        guard SyncMonitor.shared.hasSuccessfulImportToday else {
            PlutarLog.store.notice("Automatic backup put off: no successful CloudKit import yet today")
            return
        }
        guard !context.container.configurations.contains(where: \.isStoredInMemoryOnly),
              ((try? context.fetchCount(FetchDescriptor<LinkItem>())) ?? 0) > 0,
              consumeAutomaticAttempt()
        else { return }

        isAutomaticRunning = true
        defer { isAutomaticRunning = false }
        do {
            try await backUp(.automatic, from: context)
            PlutarLog.store.notice("Automatic backup done")
        } catch {
            PlutarLog.store.error("Automatic backup failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static var isAutomaticDue: Bool {
        guard let last = defaults.object(forKey: lastAutomaticSuccessKey) as? Date else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    /// Spends one of today's attempts; `false` once both are gone.
    private static func consumeAutomaticAttempt() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        var count = defaults.integer(forKey: attemptCountKey)
        if (defaults.object(forKey: attemptDayKey) as? Date) != today { count = 0 }
        guard count < maxAutomaticAttemptsPerDay else { return false }
        defaults.set(today, forKey: attemptDayKey)
        defaults.set(count + 1, forKey: attemptCountKey)
        return true
    }

    // MARK: - Guards and errors

    /// The in-memory fallback store (`AppContainerBootstrap`) holds nothing
    /// worth backing up, and restoring into it would be lost on quit.
    private static func requireRealStore(_ context: ModelContext) throws {
        if context.container.configurations.contains(where: \.isStoredInMemoryOnly) {
            throw BackupError.storeUnavailable
        }
    }

    private nonisolated static func mapped(_ error: Error) -> Error {
        if error is BackupError { return error }
        guard let cloudKitError = error as? CKError else { return error }
        switch cloudKitError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable, .permissionFailure:
            return BackupError.iCloudUnavailable
        case .networkUnavailable, .networkFailure, .serverResponseLost:
            return BackupError.network
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return BackupError.temporarilyUnavailable
        case .quotaExceeded:
            return BackupError.cloudKit("Votre stockage iCloud est plein.")
        case .unknownItem:
            return BackupError.noBackup
        default:
            return BackupError.cloudKit(cloudKitError.localizedDescription)
        }
    }

    // MARK: - CloudKit (off the main actor)

    private nonisolated static var container: CKContainer {
        CKContainer(identifier: SharedStore.cloudKitContainerID)
    }

    /// Bounds a whole operation. The `async` CloudKit calls would otherwise
    /// wait on a bad network for far longer than anyone wants to watch a
    /// spinner (the default resource timeout is days).
    private nonisolated static func configuration(timeout: TimeInterval) -> CKOperation.Configuration {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return configuration
    }

    private nonisolated static func upload(_ file: BackupFile, as kind: BackupKind) async throws -> Date {
        guard try await container.accountStatus() == .available else { throw BackupError.iCloudUnavailable }

        // A `CKAsset` is a file, so the payload takes a trip through a
        // temporary one.
        let packed = try BackupCoding.pack(file)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(kind.recordName)-\(UUID().uuidString).lzfse")
        try packed.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let recordID = CKRecord.ID(recordName: kind.recordName)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[Field.payload] = CKAsset(fileURL: temporaryURL)
        record[Field.linkCount] = Int64(file.links.count)
        record[Field.version] = Int64(file.version)

        // `.allKeys` overwrites whatever is there, whichever device wrote it —
        // that's the "écrase la précédente" of the spec.
        let results = try await container.privateCloudDatabase.configuredWith(
            configuration: configuration(timeout: 30)
        ) { database in
            try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
        }
        guard let result = results.saveResults[recordID] else {
            throw BackupError.cloudKit("La sauvegarde n'a pas pu être envoyée à iCloud.")
        }
        return try result.get().modificationDate ?? Date()
    }

    private nonisolated static func download(_ kind: BackupKind) async throws -> BackupFile {
        let recordID = CKRecord.ID(recordName: kind.recordName)
        let results = try await container.privateCloudDatabase.configuredWith(
            configuration: configuration(timeout: 60)
        ) { database in
            try await database.records(for: [recordID])
        }
        guard let result = results[recordID] else { throw BackupError.noBackup }
        let record = try result.get()
        // Checked on the record, before decoding: a newer format may not decode
        // at all, and "illisible" would hide the real reason.
        if let version = record[Field.version] as? Int64, version > Int64(BackupFile.currentVersion) {
            throw BackupError.newerVersion
        }
        guard let asset = record[Field.payload] as? CKAsset, let url = asset.fileURL else {
            throw BackupError.invalidFile
        }
        let file = try BackupCoding.unpack(try Data(contentsOf: url))
        guard file.version <= BackupFile.currentVersion else { throw BackupError.newerVersion }
        return file
    }

    private nonisolated static func fetchDates() async throws -> (found: [BackupKind: Date], missing: Set<BackupKind>) {
        let ids = BackupKind.allCases.map { CKRecord.ID(recordName: $0.recordName) }
        // `desiredKeys` without the payload: the dates cost a few bytes, not a
        // download of both backups.
        let results = try await container.privateCloudDatabase.configuredWith(
            configuration: configuration(timeout: 15)
        ) { database in
            try await database.records(for: ids, desiredKeys: [Field.linkCount])
        }
        var found: [BackupKind: Date] = [:]
        var missing = Set<BackupKind>()
        for kind in BackupKind.allCases {
            switch results[CKRecord.ID(recordName: kind.recordName)] {
            case .success(let record)?:
                if let date = record.modificationDate { found[kind] = date }
            case .failure(let error)?:
                if (error as? CKError)?.code == .unknownItem { missing.insert(kind) }
            case nil:
                break
            }
        }
        return (found, missing)
    }
}
