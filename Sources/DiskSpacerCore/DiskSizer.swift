import Foundation

/// Result of measuring one path on disk.
public struct SizeMeasurement: Sendable {
    public var bytes: Int64 = 0
    public var fileCount: Int = 0
    /// True if any file had a link count > 1. Hard links are counted once, but
    /// their presence means the figure can still differ from `du`'s.
    public var sawHardLinks: Bool = false
    /// True if any subtree could not be read — almost always TCC on macOS.
    public var accessDenied: Bool = false
}

/// Mutable flag shared with the enumerator's escaping error handler.
private final class DeniedFlag: @unchecked Sendable {
    var value = false
}

public enum DiskSizer {

    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .isDirectoryKey, .isSymbolicLinkKey, .linkCountKey,
    ]

    /// Device+inode pair identifying a physical file, for hard-link dedupe.
    private struct INode: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private static func inode(of path: String) -> INode? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return INode(dev: st.st_dev, ino: st.st_ino)
    }

    /// Measures the allocated size of `url`, recursing into directories.
    ///
    /// Uses *allocated* size (what the filesystem actually reserves) rather
    /// than logical size, because allocated size is what comes back when the
    /// file is removed. Symlinks are never followed, and hard-linked files are
    /// counted once, so a pnpm store or Homebrew Cellar isn't wildly inflated.
    ///
    /// Honours task cancellation — checked every 512 entries so a scan of a
    /// 100 GB tree stops promptly.
    public static func measure(_ url: URL) -> SizeMeasurement {
        var result = SizeMeasurement()
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return result }

        if !isDir.boolValue {
            if let v = try? url.resourceValues(forKeys: keys) {
                result.bytes = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                result.fileCount = 1
            } else {
                result.accessDenied = true
            }
            return result
        }

        let denied = DeniedFlag()
        guard let e = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                denied.value = true
                return true   // keep going; report the gap rather than aborting
            }
        ) else {
            result.accessDenied = true
            return result
        }

        var seen = Set<INode>()   // only hard-linked inodes land here
        var checked = 0

        for case let child as URL in e {
            checked += 1
            if checked % 512 == 0 && Task.isCancelled { break }

            guard let v = try? child.resourceValues(forKeys: keys) else {
                denied.value = true
                continue
            }
            if v.isSymbolicLink == true { continue }   // never follow
            if v.isDirectory == true { continue }      // size lives in the leaves

            // Count a hard-linked inode only once.
            if let n = v.linkCount, n > 1 {
                result.sawHardLinks = true
                if let id = inode(of: child.path), !seen.insert(id).inserted { continue }
            }

            result.bytes += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            result.fileCount += 1
        }

        result.accessDenied = result.accessDenied || denied.value
        return result
    }

    /// Free space on the volume containing `path`, in bytes.
    ///
    /// Uses "important usage" capacity, which is what Finder reports — it
    /// includes space macOS would purge under pressure.
    public static func availableCapacity(forPath path: String = NSHomeDirectory()) -> Int64? {
        let url = URL(fileURLWithPath: path)
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage
    }

    public static func totalCapacity(forPath path: String = NSHomeDirectory()) -> Int64? {
        let url = URL(fileURLWithPath: path)
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return v?.volumeTotalCapacity.map(Int64.init)
    }

    /// Last-modified date, used for "not touched in 8 months" style notes.
    public static func modifiedDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Human phrasing for how stale something is.
    public static func ageNote(_ url: URL) -> String? {
        guard let date = modifiedDate(url) else { return nil }
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1:     return "modified today"
        case 1..<30:   return "modified \(days)d ago"
        case 30..<365: return "modified \(days / 30)mo ago"
        default:       return "modified \(days / 365)y ago"
        }
    }
}
