import Foundation

public struct CleanSummary: Sendable {
    public var results: [RemovalResult] = []

    public init(results: [RemovalResult] = []) { self.results = results }

    public var freedBytes: Int64 { results.filter(\.succeeded).reduce(0) { $0 + $1.freed } }
    public var failures: [RemovalResult] { results.filter { !$0.succeeded } }
    public var succeededCount: Int { results.filter(\.succeeded).count }
}

public struct CleanProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentPath: String
    public var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
}

public enum Remover {

    /// Removes the selected items from the given reports.
    ///
    /// Every filesystem removal is re-validated against `SafetyGuard`
    /// immediately before it happens — the check at scan time is not trusted,
    /// because paths and selections pass through the UI in between.
    ///
    /// Failures are collected rather than thrown: one undeletable file must not
    /// abort the rest of the clean, and the UI reports honestly what didn't work.
    public static func clean(
        reports: [MethodReport],
        selection: [String: Set<String>],
        onProgress: (@Sendable (CleanProgress) -> Void)? = nil
    ) async -> CleanSummary {

        var summary = CleanSummary()

        // Command-based methods run once each; path-based ones item by item.
        let plannedPaths = reports.flatMap { r -> [(MethodReport, CleanupItem)] in
            guard r.action != .command, let picked = selection[r.methodID] else { return [] }
            return r.items.filter { picked.contains($0.path) }.map { (r, $0) }
        }
        let plannedCommands = reports.filter {
            $0.action == .command && !(selection[$0.methodID] ?? []).isEmpty
        }
        let total = plannedPaths.count + plannedCommands.count
        var done = 0

        for (report, item) in plannedPaths {
            if Task.isCancelled { break }
            done += 1
            onProgress?(CleanProgress(completed: done, total: total, currentPath: item.path))
            summary.results.append(removePath(item, action: report.action))
        }

        for report in plannedCommands {
            if Task.isCancelled { break }
            done += 1
            let label = report.pruneTool.map { "\($0) \(report.pruneArgs.joined(separator: " "))" }
                ?? report.title
            onProgress?(CleanProgress(completed: done, total: total, currentPath: label))
            summary.results.append(runPrune(report))
        }

        return summary
    }

    private static func removePath(_ item: CleanupItem, action: RemovalAction) -> RemovalResult {
        do {
            // Re-validate at the point of no return.
            try SafetyGuard.validate(item.path)
        } catch {
            return RemovalResult(path: item.path, freed: 0, succeeded: false,
                                 error: "\(error)")
        }

        let url = URL(fileURLWithPath: item.path)
        do {
            switch action {
            case .trash:
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            case .delete, .command:
                try FileManager.default.removeItem(at: url)
            }
            return RemovalResult(path: item.path, freed: item.size, succeeded: true)
        } catch {
            return RemovalResult(
                path: item.path, freed: 0, succeeded: false,
                error: (error as NSError).localizedDescription)
        }
    }

    private static func runPrune(_ report: MethodReport) -> RemovalResult {
        guard let tool = report.pruneTool else {
            return RemovalResult(path: report.methodID, freed: 0, succeeded: false,
                                 error: "no prune command defined")
        }
        guard let out = Shell.run(tool, report.pruneArgs, timeout: 300) else {
            return RemovalResult(path: report.methodID, freed: 0, succeeded: false,
                                 error: "\(tool) not found")
        }
        guard out.ok else {
            let msg = out.stderr.isEmpty ? out.stdout : out.stderr
            return RemovalResult(
                path: report.methodID, freed: 0, succeeded: false,
                error: msg.split(separator: "\n").last.map(String.init) ?? "exit \(out.exitCode)")
        }
        return RemovalResult(path: report.methodID, freed: report.totalSize, succeeded: true)
    }
}

/// Detects whether the app can read TCC-protected locations.
public enum Permissions {

    /// Probes a path that is readable only with Full Disk Access.
    ///
    /// There is no API to *request* Full Disk Access — it can only be granted
    /// by hand in System Settings — so the app detects it and guides the user
    /// there rather than prompting.
    public static var hasFullDiskAccess: Bool {
        let probes = [
            NSHomeDirectory() + "/Library/Safari",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for p in probes {
            if FileManager.default.isReadableFile(atPath: p) { return true }
            if (try? FileManager.default.contentsOfDirectory(atPath: p)) != nil { return true }
        }
        return false
    }

    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
