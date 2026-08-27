import Foundation

/// One cleanup method the app can offer.
///
/// Every cleaner carries its own explanation and, crucially, the shell command
/// that does the same job by hand — the app always shows you how to do it
/// yourself rather than asking you to trust a black box.
public protocol Cleaner: Sendable {
    var id: String { get }
    var title: String { get }
    var category: MethodCategory { get }
    var safety: Safety { get }
    var action: RemovalAction { get }
    /// What this actually is, in one or two sentences.
    var whatItIs: String { get }
    /// What happens after it's gone — how (or whether) it comes back.
    var whatRegenerates: String { get }
    /// The equivalent command to run in Terminal.
    var manualCommand: String { get }
    /// Higher wins when two cleaners claim the same path. Prevents the same
    /// bytes being counted twice in the headline total.
    var priority: Int { get }

    func scan() async -> MethodReport
}

public extension Cleaner {
    var priority: Int { 0 }

    /// Builds a report carrying this cleaner's metadata.
    func report(
        items: [CleanupItem], status: ScanStatus,
        detail: String? = nil, upperBound: Bool = false,
        pruneTool: String? = nil, pruneArgs: [String] = []
    ) -> MethodReport {
        MethodReport(
            methodID: id, title: title, category: category, safety: safety,
            action: action, whatItIs: whatItIs, whatRegenerates: whatRegenerates,
            manualCommand: manualCommand,
            items: items.sorted { $0.size > $1.size },
            status: status, detail: detail, sizeIsUpperBound: upperBound,
            pruneTool: pruneTool, pruneArgs: pruneArgs
        )
    }
}

/// The common case: a directory whose immediate children are each removable.
///
/// Covers DerivedData, `~/Library/Caches`, DeviceSupport and friends — anything
/// where you empty the container but keep the container itself.
public struct DirectoryChildrenCleaner: Cleaner {
    public let id: String
    public let title: String
    public let category: MethodCategory
    public let safety: Safety
    public let action: RemovalAction
    public let whatItIs: String
    public let whatRegenerates: String
    public let manualCommand: String
    public let priority: Int

    /// Directory whose children are the removable items.
    let root: String
    /// Child names to leave alone (usually because a dedicated cleaner owns them).
    let excluding: Set<String>
    /// Skip children smaller than this, to keep the list readable.
    let minimumSize: Int64

    public init(
        id: String, title: String, category: MethodCategory, safety: Safety,
        action: RemovalAction = .delete, whatItIs: String, whatRegenerates: String,
        manualCommand: String, root: String, excluding: Set<String> = [],
        minimumSize: Int64 = 1_000_000, priority: Int = 0
    ) {
        self.id = id; self.title = title; self.category = category
        self.safety = safety; self.action = action; self.whatItIs = whatItIs
        self.whatRegenerates = whatRegenerates; self.manualCommand = manualCommand
        self.root = root; self.excluding = excluding
        self.minimumSize = minimumSize; self.priority = priority
    }

    public func scan() async -> MethodReport {
        let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            return report(items: [], status: .empty, detail: "\(rootURL.path) doesn't exist")
        }

        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: nil, options: [])
        } catch {
            // On macOS an unreadable directory in ~/Library is virtually always
            // TCC rather than POSIX permissions.
            return report(
                items: [], status: .needsFullDiskAccess,
                detail: "Can't read \(rootURL.path)")
        }

        var items: [CleanupItem] = []
        var denied = false
        var hardLinks = false

        for child in children where !excluding.contains(child.lastPathComponent) {
            if Task.isCancelled { break }
            guard SafetyGuard.isRemovable(child.path) else { continue }

            let m = DiskSizer.measure(child)
            denied = denied || m.accessDenied
            hardLinks = hardLinks || m.sawHardLinks
            guard m.bytes >= minimumSize else { continue }

            items.append(CleanupItem(
                path: child.path, size: m.bytes, note: DiskSizer.ageNote(child)))
        }

        let status: ScanStatus = items.isEmpty ? (denied ? .needsFullDiskAccess : .empty) : .ok
        return report(
            items: items, status: status,
            detail: denied && !items.isEmpty
                ? "Some subfolders couldn't be read — grant Full Disk Access for a complete figure."
                : nil,
            upperBound: hardLinks)
    }
}

/// A single directory that is removed whole (or emptied), rather than one whose
/// children are listed individually.
public struct SinglePathCleaner: Cleaner {
    public let id: String
    public let title: String
    public let category: MethodCategory
    public let safety: Safety
    public let action: RemovalAction
    public let whatItIs: String
    public let whatRegenerates: String
    public let manualCommand: String
    public let priority: Int

    let path: String
    /// When true the directory itself is kept and its children are the items.
    let emptyContents: Bool
    /// Skip children smaller than this, so marker files like `CACHEDIR.TAG`
    /// don't clutter the list.
    let minimumSize: Int64

    public init(
        id: String, title: String, category: MethodCategory, safety: Safety,
        action: RemovalAction = .delete, whatItIs: String, whatRegenerates: String,
        manualCommand: String, path: String, emptyContents: Bool = true,
        minimumSize: Int64 = 1_000_000, priority: Int = 0
    ) {
        self.id = id; self.title = title; self.category = category
        self.safety = safety; self.action = action; self.whatItIs = whatItIs
        self.whatRegenerates = whatRegenerates; self.manualCommand = manualCommand
        self.path = path; self.emptyContents = emptyContents
        self.minimumSize = minimumSize; self.priority = priority
    }

    public func scan() async -> MethodReport {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return report(items: [], status: .empty, detail: "\(url.path) doesn't exist")
        }

        if emptyContents {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: []) else {
                return report(items: [], status: .needsFullDiskAccess,
                              detail: "Can't read \(url.path)")
            }
            var items: [CleanupItem] = []
            var denied = false, hardLinks = false
            for child in children {
                if Task.isCancelled { break }
                guard SafetyGuard.isRemovable(child.path) else { continue }
                let m = DiskSizer.measure(child)
                denied = denied || m.accessDenied
                hardLinks = hardLinks || m.sawHardLinks
                guard m.bytes >= minimumSize else { continue }
                items.append(CleanupItem(
                    path: child.path, size: m.bytes, note: DiskSizer.ageNote(child)))
            }
            let status: ScanStatus = items.isEmpty ? (denied ? .needsFullDiskAccess : .empty) : .ok
            return report(items: items, status: status, upperBound: hardLinks)
        }

        guard SafetyGuard.isRemovable(url.path) else {
            return report(items: [], status: .failed,
                          detail: "\(url.path) is outside the allowlist")
        }
        let m = DiskSizer.measure(url)
        if m.bytes == 0 {
            return report(items: [], status: m.accessDenied ? .needsFullDiskAccess : .empty)
        }
        return report(
            items: [CleanupItem(path: url.path, size: m.bytes, note: DiskSizer.ageNote(url))],
            status: .ok, upperBound: m.sawHardLinks)
    }
}
