import Foundation

/// A disk the user can scan.
public struct VolumeInfo: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let totalBytes: Int64
    public let freeBytes: Int64
    /// True for the startup disk.
    public let isRootFileSystem: Bool
    public let isRemovable: Bool
    /// False for network shares, which are far too slow to walk casually.
    public let isLocal: Bool
    public let isReadOnly: Bool
    /// True when scanning this entry covers the entire volume.
    ///
    /// The home folder is a subset of its volume, so comparing a home scan
    /// against the volume's used space would report everything *outside* the
    /// home folder as "unaccounted for" — 115 GB of nonsense on this machine.
    public let coversWholeVolume: Bool

    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    public var usedFraction: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }

    /// Identity is the mount path. Free space drifts constantly on a live
    /// system, so a synthesized == over every field would make the same volume
    /// compare unequal to itself moments later — which silently blanks a
    /// SwiftUI Picker whose selection was captured earlier.
    public static func == (a: VolumeInfo, b: VolumeInfo) -> Bool { a.path == b.path }
    public func hash(into hasher: inout Hasher) { hasher.combine(path) }

    public init(
        name: String, path: String, totalBytes: Int64, freeBytes: Int64,
        isRootFileSystem: Bool, isRemovable: Bool, isLocal: Bool, isReadOnly: Bool,
        coversWholeVolume: Bool = true
    ) {
        self.coversWholeVolume = coversWholeVolume
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.isRootFileSystem = isRootFileSystem
        self.isRemovable = isRemovable
        self.isLocal = isLocal
        self.isReadOnly = isReadOnly
    }
}

public enum Volumes {

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsInternalKey, .volumeIsLocalKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey,
        .volumeIsBrowsableKey, .volumeIsReadOnlyKey,
    ]

    /// Volumes worth offering to the user.
    ///
    /// `skipHiddenVolumes` does the heavy lifting: on APFS the startup disk is
    /// really several volumes (System, Data, Preboot, VM…) plus any mounted
    /// simulator runtimes, and this collapses all of that into the single
    /// "Macintosh HD" that Finder shows.
    ///
    /// Network shares are excluded by default. Walking one is orders of
    /// magnitude slower than a local disk, and starting that by accident would
    /// look like a hang.
    public static func scannable(includeNetwork: Bool = false) -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]) ?? []

        var result: [VolumeInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard v.volumeIsBrowsable != false else { continue }

            let isLocal = v.volumeIsLocal ?? true
            if !isLocal && !includeNetwork { continue }

            let total = Int64(v.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }

            result.append(VolumeInfo(
                name: v.volumeName ?? url.lastPathComponent,
                path: url.path,
                totalBytes: total,
                freeBytes: v.volumeAvailableCapacityForImportantUsage ?? 0,
                isRootFileSystem: v.volumeIsRootFileSystem ?? (url.path == "/"),
                isRemovable: (v.volumeIsRemovable ?? false) || (v.volumeIsEjectable ?? false),
                isLocal: isLocal,
                isReadOnly: v.volumeIsReadOnly ?? false))
        }

        // Startup disk first, then everything else alphabetically.
        return result.sorted {
            $0.isRootFileSystem != $1.isRootFileSystem
                ? $0.isRootFileSystem
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The startup disk, or nil if it somehow isn't listed.
    public static func startupDisk() -> VolumeInfo? {
        scannable().first { $0.isRootFileSystem }
    }

    /// Convenience entry for scanning just the user's home folder, which is
    /// where most reclaimable space actually lives and which needs no special
    /// permission to read.
    public static func homeFolder() -> VolumeInfo {
        let home = NSHomeDirectory()
        let url = URL(fileURLWithPath: home)
        let v = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return VolumeInfo(
            name: "Home Folder",
            path: home,
            totalBytes: Int64(v?.volumeTotalCapacity ?? 0),
            freeBytes: v?.volumeAvailableCapacityForImportantUsage ?? 0,
            isRootFileSystem: false,
            isRemovable: false,
            isLocal: true,
            isReadOnly: false,
            coversWholeVolume: false)
    }
}
