import Foundation

/// How risky removing a method's items is. Drives the badge shown in the UI
/// and whether the app will ever preselect the method.
public enum Safety: String, Sendable, Codable, CaseIterable {
    /// Rebuilt automatically by the tool that made it. Safe to delete.
    case regenerable
    /// Might matter to you. Look at the file list before deleting.
    case reviewNeeded
    /// Gone for good, or represents real work/data. Never preselected.
    case irreversible

    public var label: String {
        switch self {
        case .regenerable:  return "Safe — regenerates"
        case .reviewNeeded: return "Review first"
        case .irreversible: return "Irreversible"
        }
    }
}

/// What removal actually does. The distinction matters: trashing does not
/// free space until the Trash is emptied.
public enum RemovalAction: String, Sendable, Codable {
    /// Deleted outright. Frees space immediately.
    case delete
    /// Moved to the Trash, recoverable. Frees space only once Trash is emptied.
    case trash
    /// Reclaimed by running the method's own tool (docker prune, brew cleanup)
    /// rather than by removing paths directly.
    case command

    public var verb: String {
        switch self {
        case .delete:  return "Delete"
        case .trash:   return "Move to Trash"
        case .command: return "Run cleanup"
        }
    }
}

public enum MethodCategory: String, Sendable, Codable, CaseIterable {
    case developer  = "Developer"
    case caches     = "Caches"
    case containers = "Containers"
    case system     = "System"
    case personal   = "Personal"
}

/// One removable thing: usually a directory, occasionally a single file.
public struct CleanupItem: Sendable, Codable, Identifiable, Hashable {
    public var id: String { path }
    /// Filesystem path, or a synthetic `docker://…` identifier for
    /// command-reclaimed items that don't correspond to one path.
    public let path: String
    /// Allocated size in bytes — what actually comes back when it's removed.
    public let size: Int64
    /// Short context, e.g. "modified 8mo ago".
    public let note: String?
    /// Overrides the name shown in the UI. Used by command-based methods.
    public let label: String?

    public init(path: String, size: Int64, note: String? = nil, label: String? = nil) {
        self.path = path
        self.size = size
        self.note = note
        self.label = label
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var isFilesystemPath: Bool { path.hasPrefix("/") }
    public var displayName: String { label ?? url.lastPathComponent }
}

/// Why a method produced nothing, so the UI never silently shows "0 B" for
/// something it simply could not look at.
public enum ScanStatus: String, Sendable, Codable {
    case ok
    /// Found nothing to clean. Genuinely empty.
    case empty
    /// Blocked by TCC. Needs Full Disk Access.
    case needsFullDiskAccess
    /// The tool this method drives (docker, brew…) isn't installed/running.
    case toolUnavailable
    case failed
}

/// The result of scanning one method.
public struct MethodReport: Sendable, Codable, Identifiable {
    public var id: String { methodID }
    public let methodID: String
    public let title: String
    public let category: MethodCategory
    public let safety: Safety
    public let action: RemovalAction
    public let whatItIs: String
    public let whatRegenerates: String
    public let manualCommand: String
    public let items: [CleanupItem]
    public let status: ScanStatus
    public let detail: String?
    /// True when hard links or nested structure mean the total is an upper bound.
    public let sizeIsUpperBound: Bool
    /// For `.command` methods: the tool and arguments that reclaim the space.
    public let pruneTool: String?
    public let pruneArgs: [String]

    public init(
        methodID: String, title: String, category: MethodCategory, safety: Safety,
        action: RemovalAction, whatItIs: String, whatRegenerates: String,
        manualCommand: String, items: [CleanupItem], status: ScanStatus,
        detail: String? = nil, sizeIsUpperBound: Bool = false,
        pruneTool: String? = nil, pruneArgs: [String] = []
    ) {
        self.pruneTool = pruneTool
        self.pruneArgs = pruneArgs
        self.methodID = methodID
        self.title = title
        self.category = category
        self.safety = safety
        self.action = action
        self.whatItIs = whatItIs
        self.whatRegenerates = whatRegenerates
        self.manualCommand = manualCommand
        self.items = items
        self.status = status
        self.detail = detail
        self.sizeIsUpperBound = sizeIsUpperBound
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var isActionable: Bool { status == .ok && !items.isEmpty }

    /// Command-reclaimed methods run a single tool that decides for itself what
    /// to remove, so individual items can't be opted out of. Selection is
    /// all-or-nothing, and the UI must not offer per-item checkboxes that the
    /// clean would then ignore.
    public var supportsPartialSelection: Bool { action != .command }
}

/// Outcome of one removal attempt, so the UI can report honestly rather than
/// assuming everything worked.
public struct RemovalResult: Sendable, Codable {
    public let path: String
    public let freed: Int64
    public let succeeded: Bool
    public let error: String?

    public init(path: String, freed: Int64, succeeded: Bool, error: String? = nil) {
        self.path = path
        self.freed = freed
        self.succeeded = succeeded
        self.error = error
    }
}

public func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
    return f.string(fromByteCount: bytes)
}
