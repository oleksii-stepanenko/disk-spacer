import Foundation

public struct ScanProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentTitle: String
    public var fraction: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }
}

public struct ScanResults: Sendable, Codable {
    public let reports: [MethodReport]
    public let availableBefore: Int64?
    public let totalCapacity: Int64?

    public init(reports: [MethodReport], availableBefore: Int64?, totalCapacity: Int64?) {
        self.reports = reports
        self.availableBefore = availableBefore
        self.totalCapacity = totalCapacity
    }

    /// Total reclaimable across every actionable method.
    public var reclaimable: Int64 {
        reports.filter(\.isActionable).reduce(0) { $0 + $1.totalSize }
    }
    public var needsFullDiskAccess: Bool {
        reports.contains { $0.status == .needsFullDiskAccess }
    }
}

public enum ScanEngine {

    /// Scans every method concurrently, reporting progress as each finishes.
    ///
    /// Methods run in parallel because the slow ones are I/O-bound directory
    /// walks — `~/Library/Caches` alone can be 18 GB — and running them
    /// sequentially would make the app feel hung.
    public static func scan(
        cleaners: [any Cleaner] = Catalog.allCleaners(),
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResults {

        let before = DiskSizer.availableCapacity()
        let capacity = DiskSizer.totalCapacity()
        let total = cleaners.count

        var collected: [MethodReport] = []
        collected.reserveCapacity(total)

        await withTaskGroup(of: MethodReport.self) { group in
            for cleaner in cleaners {
                group.addTask { await cleaner.scan() }
            }
            var done = 0
            for await report in group {
                done += 1
                onProgress?(ScanProgress(
                    completed: done, total: total, currentTitle: report.title))
                collected.append(report)
            }
        }

        let deduped = deduplicate(collected, cleaners: cleaners)
        let ordered = deduped.sorted { a, b in
            if a.isActionable != b.isActionable { return a.isActionable }
            return a.totalSize > b.totalSize
        }
        return ScanResults(reports: ordered, availableBefore: before, totalCapacity: capacity)
    }

    /// Drops items already claimed by a higher-priority method, so the same
    /// bytes are never counted twice in the headline figure.
    ///
    /// `~/Library/Caches/Homebrew` is a concrete case: both the Homebrew
    /// method and the generic application-caches method see it. Homebrew has
    /// the higher priority, so the generic bucket gives it up.
    static func deduplicate(
        _ reports: [MethodReport], cleaners: [any Cleaner]
    ) -> [MethodReport] {
        let priority = Dictionary(
            uniqueKeysWithValues: cleaners.map { ($0.id, $0.priority) })

        // Highest priority first; ties broken by id for a stable result.
        let order = reports.sorted {
            let (pa, pb) = (priority[$0.methodID] ?? 0, priority[$1.methodID] ?? 0)
            return pa == pb ? $0.methodID < $1.methodID : pa > pb
        }

        var claimed: [String] = []
        var result: [String: MethodReport] = [:]

        for r in order {
            var kept: [CleanupItem] = []
            for item in r.items {
                guard item.isFilesystemPath else { kept.append(item); continue }
                let path = item.path
                // Drop the item if a higher-priority method already claimed the
                // same path, an ancestor of it, or anything inside it. The last
                // case matters: the Homebrew method claims individual files
                // under ~/Library/Caches/Homebrew, so the generic caches bucket
                // must give up that whole directory rather than counting the
                // same bytes a second time.
                let overlaps = claimed.contains {
                    path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/")
                }
                if !overlaps { kept.append(item) }
            }
            claimed.append(contentsOf: kept.filter(\.isFilesystemPath).map(\.path))

            // Preserve the original status unless dedupe emptied the method.
            let status: ScanStatus = (r.status == .ok && kept.isEmpty) ? .empty : r.status
            result[r.methodID] = MethodReport(
                methodID: r.methodID, title: r.title, category: r.category,
                safety: r.safety, action: r.action, whatItIs: r.whatItIs,
                whatRegenerates: r.whatRegenerates, manualCommand: r.manualCommand,
                items: kept, status: status, detail: r.detail,
                sizeIsUpperBound: r.sizeIsUpperBound,
                pruneTool: r.pruneTool, pruneArgs: r.pruneArgs)
        }

        return reports.compactMap { result[$0.methodID] }
    }
}
