import Foundation

// Builds a directory tree with aggregate sizes, for the Explore tab.
//
// Separate from DiskSizer on purpose: DiskSizer measures a handful of known
// paths precisely, this walks millions of entries and has to stay cheap. It
// uses fts(3) rather than FileManager.enumerator (measured ~35% faster) and
// keeps a node per *directory* only — files fold into their parent's total.
// On a 1.39M-file home directory that is ~188k nodes and ~46 MB, where a node
// per file would be an order of magnitude worse.

/// One directory in the scanned tree, holding the total for everything beneath it.
///
/// Only the directory's own name is stored; `path` is rebuilt by walking up to
/// the root. Storing a full path per node would dominate memory on a large scan.
public final class DirNode: Identifiable, @unchecked Sendable {
    public let name: String
    /// Allocated bytes for this directory and everything under it.
    public internal(set) var bytes: Int64 = 0
    /// Files directly in this directory and all descendants.
    public internal(set) var fileCount: Int = 0
    public internal(set) var children: [DirNode] = []
    /// True when the directory could not be read — almost always Full Disk
    /// Access. Its total is 0 because we could not look, not because it is empty.
    public internal(set) var isUnreadable = false
    public internal(set) weak var parent: DirNode?
    /// Set once a worker has totalled this subtree, so the roll-up pass does
    /// not add its children's bytes a second time.
    internal var isComplete = false

    // Identity is the object itself; no per-node UUID to pay for.
    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(name: String, parent: DirNode?) {
        self.name = name
        self.parent = parent
    }

    public var hasChildren: Bool { !children.isEmpty }

    /// Absolute path, rebuilt from the chain of names.
    public var path: String {
        var parts: [String] = []
        var node: DirNode? = self
        while let n = node, n.parent != nil {
            parts.append(n.name)
            node = n.parent
        }
        let rootPath = node?.name ?? "/"
        guard !parts.isEmpty else { return rootPath }
        let suffix = parts.reversed().joined(separator: "/")
        return rootPath == "/" ? "/" + suffix : rootPath + "/" + suffix
    }
}

public struct LargeFile: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public var name: String { (path as NSString).lastPathComponent }
}

public struct TreeScanProgress: Sendable {
    public let filesSeen: Int
    public let bytesSeen: Int64
    public let currentPath: String
}

public struct TreeScanResult: Sendable {
    public let root: DirNode
    public let largestFiles: [LargeFile]
    public let volume: VolumeInfo
    /// Directories that could not be read. Non-zero almost always means the
    /// app needs Full Disk Access, and the totals below are understated.
    public let unreadableCount: Int
    public let scannedBytes: Int64
    public let fileCount: Int
    public let duration: TimeInterval
    public let cancelled: Bool

    /// Space the volume reports as used that the scan did not account for:
    /// APFS snapshots, purgeable space, other users' data, and anything the
    /// app was not allowed to read.
    ///
    /// Reported rather than hidden — a scan total that silently disagrees with
    /// Finder is the single most confusing thing a disk analyser can do.
    public var unaccountedBytes: Int64 {
        max(0, volume.usedBytes - scannedBytes)
    }
}

// MARK: - Scanner

public enum TreeScanner {

    /// Scans one volume and returns its directory tree.
    ///
    /// Top-level subtrees are walked concurrently — measured ~2.9x faster than
    /// a single walk (80k vs 25k files/sec) because the work is I/O bound.
    public static func scan(
        volume: VolumeInfo,
        topFileCount: Int = 1000,
        onProgress: (@Sendable (TreeScanProgress) -> Void)? = nil
    ) async -> TreeScanResult {

        let state = ScanState(topFileCapacity: topFileCount)

        // Report progress on a timer rather than per entry — at 80k files/sec
        // a callback per file would cost more than the scan.
        let poller = Task { @Sendable in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { break }
                onProgress?(state.snapshot())
            }
        }

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<TreeScanResult, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: performScan(volume: volume, state: state))
                }
            }
        } onCancel: {
            state.cancel()
        }

        poller.cancel()
        return result
    }

    private static func performScan(volume: VolumeInfo, state: ScanState) -> TreeScanResult {
        let started = Date()
        let rootPath = volume.path
        let root = DirNode(name: rootPath, parent: nil)

        // Directories to skip entirely.
        //
        // /System/Volumes/Data is the important one: on APFS it is the *same*
        // storage as /Users, /Applications and friends, reachable through
        // firmlinks. Both paths report the same device id, so FTS_XDEV does not
        // stop us, and walking both would count every user file twice.
        // /Volumes holds other mounted disks, each scanned on its own.
        var pruneBuilder: Set<String> = []
        if volume.isRootFileSystem {
            pruneBuilder.insert("/System/Volumes/Data")
            pruneBuilder.insert("/Volumes")
            pruneBuilder.insert("/dev")
            // macOS keeps several magic directories at the root that lead
            // straight back to "/". Walking one re-walks the entire disk:
            // /.nofollow alone reported an extra 654 GB before it was pruned.
            // fts spots the cycle within a single walk, but the skeleton below
            // starts a fresh walk per subtree, so these must be excluded here.
            pruneBuilder.insert("/.vol")
            pruneBuilder.insert("/.nofollow")
            pruneBuilder.insert("/.resolve")
            pruneBuilder.insert("/.file")
        }
        // Immutable from here on: the walkers read it concurrently.
        let prune = pruneBuilder

        // Splitting only at the top level is not enough: scanning "/" would put
        // all of /Users — 1.4M files here — in a single walker, and the whole
        // scan would take as long as that one thread (measured 50s vs 20s).
        // So expand the first few levels cheaply, then hand every leaf of that
        // skeleton to the pool, which balances the work far better.
        let leaves = buildSkeleton(root: root, rootPath: rootPath,
                                   prune: prune, state: state)

        // No leaves means the skeleton reached the bottom on its own (a small
        // tree) or the volume root could not be read. Either way it has already
        // recorded everything it could, and roll-up below finishes the job.
        if !leaves.isEmpty {
            DispatchQueue.concurrentPerform(iterations: leaves.count) { i in
                guard !state.isCancelled else { return }
                let leaf = leaves[i]
                let built = walkSubtree(path: leaf.path, name: leaf.node.name,
                                        prune: prune, state: state)
                // Each leaf is owned by exactly one worker, so attaching its
                // results needs no lock.
                for child in built.children { child.parent = leaf.node }
                leaf.node.children = built.children
                leaf.node.bytes += built.bytes
                leaf.node.fileCount += built.fileCount
                leaf.node.isComplete = true
                if built.isUnreadable { leaf.node.isUnreadable = true }
            }
        }

        rollUp(root)
        sortTree(root)

        return TreeScanResult(
            root: root,
            largestFiles: state.topFiles(),
            volume: volume,
            unreadableCount: state.unreadableCount,
            scannedBytes: root.bytes,
            fileCount: root.fileCount,
            duration: Date().timeIntervalSince(started),
            cancelled: state.isCancelled)
    }

    /// Sorts every level largest-first, so drilling down always leads with the
    /// biggest thing.
    private static func sortTree(_ node: DirNode) {
        node.children.sort { $0.bytes > $1.bytes }
        for c in node.children { sortTree(c) }
    }

    private struct WorkLeaf {
        let node: DirNode
        let path: String
    }

    /// Walks the first few levels breadth-first, creating nodes as it goes,
    /// until there are enough independent subtrees to keep every core busy.
    /// Files found along the way are charged to their directory immediately.
    ///
    /// Returns the frontier: the subtrees still to be walked.
    private static func buildSkeleton(
        root: DirNode, rootPath: String, prune: Set<String>, state: ScanState
    ) -> [WorkLeaf] {

        // What matters is unit *balance*, not unit count. Stopping as soon as
        // there were "enough" units left /Users/<name> as a single unit holding
        // 1.4M files, and the whole scan waited on that one thread. So keep
        // expanding by depth — listing a directory is far cheaper than walking
        // it — and stop only when the frontier is genuinely wide.
        let frontierCap = 4096
        let maxDepth = 5

        var frontier: [(node: DirNode, path: String, depth: Int)] = [(root, rootPath, 0)]
        var leaves: [WorkLeaf] = []

        // Directories already claimed, by identity rather than by path.
        //
        // The same directory is reachable under more than one name on macOS:
        // /Users and /System/Volumes/Data/Users are literally the same inode
        // (16925 on this machine), and the magic roots above alias "/". Keying
        // on (device, inode) catches every such alias generically, including
        // ones not on the prune list, so nothing is counted twice.
        var claimedDirs = Set<ScanState.InodeKey>()
        let rootStat = statOf(rootPath)
        if let rs = rootStat {
            claimedDirs.insert(ScanState.InodeKey(ino: rs.st_ino, dev: rs.st_dev))
        }
        // Stay on the chosen volume. The fts walks below pass FTS_XDEV, but
        // this skeleton uses readdir, which happily crosses mount points — and
        // that quietly added ~21 GB of Preboot and mounted simulator runtimes
        // to a scan of "/".
        let rootDev = rootStat?.st_dev

        while !frontier.isEmpty && !state.isCancelled {
            // Wide enough — everything left becomes a unit as-is.
            if frontier.count >= frontierCap {
                leaves.append(contentsOf: frontier.map { WorkLeaf(node: $0.node, path: $0.path) })
                break
            }

            var next: [(node: DirNode, path: String, depth: Int)] = []

            for item in frontier {
                guard item.depth < maxDepth else {
                    leaves.append(WorkLeaf(node: item.node, path: item.path))
                    continue
                }
                guard let names = try? FileManager.default
                        .contentsOfDirectory(atPath: item.path) else {
                    // Can't list it — record it and let the UI say so rather
                    // than reporting an empty folder.
                    item.node.isUnreadable = true
                    item.node.isComplete = true
                    state.noteUnreadable()
                    continue
                }

                for name in names {
                    let childPath = item.path == "/" ? "/" + name : item.path + "/" + name
                    if prune.contains(childPath) { continue }

                    var st = stat()
                    guard lstat(childPath, &st) == 0 else { continue }
                    switch st.st_mode & S_IFMT {
                    case S_IFDIR:
                        if let rd = rootDev, st.st_dev != rd { continue }   // another volume
                        guard claimedDirs.insert(
                                ScanState.InodeKey(ino: st.st_ino, dev: st.st_dev)).inserted
                        else { continue }   // already reached under another name
                        let child = DirNode(name: name, parent: item.node)
                        item.node.children.append(child)
                        next.append((child, childPath, item.depth + 1))
                    case S_IFREG:
                        if let rd = rootDev, st.st_dev != rd { continue }
                        let bytes = Int64(st.st_blocks) * 512
                        if st.st_nlink > 1,
                           !state.claimInode(st.st_ino, dev: st.st_dev) { continue }
                        item.node.bytes += bytes
                        item.node.fileCount += 1
                        state.considerTopFile(size: bytes, path: childPath)
                    default:
                        break   // symlinks and specials carry no size here
                    }
                }
            }

            frontier = next
        }

        // Only directories the skeleton did NOT expand become work units.
        //
        // An expanded directory has already had its own files counted here, so
        // handing it to a walker as well would count them twice — which is
        // exactly what happened when the loop bailed out early and reused a
        // frontier it had just consumed.
        return leaves
    }

    private static func statOf(_ path: String) -> stat? {
        var st = stat()
        return lstat(path, &st) == 0 ? st : nil
    }

    /// Adds each subtree's total into its parent, skipping nodes a worker has
    /// already totalled.
    private static func rollUp(_ node: DirNode) {
        guard !node.isComplete else { return }
        for child in node.children {
            rollUp(child)
            node.bytes += child.bytes
            node.fileCount += child.fileCount
        }
    }

    // MARK: fts walk

    /// Walks one subtree with fts(3), returning its root node.
    ///
    /// Runs on exactly one thread; the node graph it builds is not touched by
    /// anyone else until it is merged back on the caller's thread.
    private static func walkSubtree(
        path: String, name: String, prune: Set<String>, state: ScanState
    ) -> DirNode {

        let subtreeRoot = DirNode(name: name, parent: nil)
        var stack: [DirNode] = [subtreeRoot]

        var localFiles = 0
        var localBytes: Int64 = 0
        var localUnreadable = 0
        var localTop = TopFileBuffer(capacity: state.topFileCapacity)
        var sinceCheck = 0

        path.withCString { cpath in
            let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
            argv[0] = UnsafeMutablePointer(mutating: cpath)
            argv[1] = nil
            defer { argv.deallocate() }

            // PHYSICAL: never follow symlinks (they would double-count and can
            // escape the volume). XDEV: stay on this filesystem.
            guard let fts = fts_open(argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
                subtreeRoot.isUnreadable = true
                localUnreadable += 1
                return
            }
            defer { fts_close(fts) }

            while let ent = fts_read(fts) {
                sinceCheck += 1
                if sinceCheck >= 2048 {
                    sinceCheck = 0
                    state.publish(files: localFiles, bytes: localBytes, path: path)
                    if state.isCancelled { break }
                }

                let info = Int32(ent.pointee.fts_info)
                let level = ent.pointee.fts_level

                switch info {
                case FTS_D:
                    if level == 0 { continue }   // the subtree root, already on the stack
                    let fullPath = String(cString: ent.pointee.fts_path)
                    if prune.contains(fullPath) {
                        fts_set(fts, ent, FTS_SKIP)
                        continue
                    }
                    let node = DirNode(name: entryName(ent), parent: stack.last)
                    stack.last?.children.append(node)
                    stack.append(node)

                case FTS_DP:
                    guard level > 0, stack.count > 1 else { continue }
                    let done = stack.removeLast()
                    stack.last?.bytes += done.bytes
                    stack.last?.fileCount += done.fileCount

                case FTS_F:
                    guard let st = ent.pointee.fts_statp else { continue }
                    // Allocated blocks, not logical size — this is what the
                    // file actually occupies.
                    let bytes = Int64(st.pointee.st_blocks) * 512

                    // A hard-linked file has one copy on disk under several
                    // names. Count it once, or a tree containing both names
                    // reports twice the space it really uses.
                    if st.pointee.st_nlink > 1 {
                        if !state.claimInode(st.pointee.st_ino, dev: st.pointee.st_dev) {
                            continue
                        }
                    }

                    stack.last?.bytes += bytes
                    stack.last?.fileCount += 1
                    localFiles += 1
                    localBytes += bytes
                    localTop.consider(size: bytes) { String(cString: ent.pointee.fts_path) }

                case FTS_DNR, FTS_ERR:
                    // An unreadable directory is reported TWICE: once as FTS_D,
                    // which pushed it, and then here instead of being descended
                    // into — with no matching FTS_DP. Pop it explicitly, or the
                    // stack leaks and every later sibling is attached to the
                    // wrong parent.
                    localUnreadable += 1
                    if level > 0, stack.count > 1 {
                        let done = stack.removeLast()
                        done.isUnreadable = true
                        stack.last?.bytes += done.bytes
                        stack.last?.fileCount += done.fileCount
                    } else if level == 0 {
                        subtreeRoot.isUnreadable = true
                    }

                case FTS_NS:
                    // Entry exists but could not be stat'd — size unknown.
                    localUnreadable += 1

                default:
                    // Symlinks, sockets, fifos and cycles carry no size worth
                    // attributing here.
                    break
                }
            }
        }

        state.publish(files: localFiles, bytes: localBytes, path: path)
        state.commit(files: localFiles, bytes: localBytes,
                     unreadable: localUnreadable, top: localTop.items)
        return subtreeRoot
    }

    /// The entry's own name, sliced out of fts_path without building a String
    /// for the whole path. (fts_name is a C flexible array member, which Swift
    /// cannot import.)
    private static func entryName(_ ent: UnsafeMutablePointer<FTSENT>) -> String {
        let pathLen = Int(ent.pointee.fts_pathlen)
        let nameLen = Int(ent.pointee.fts_namelen)
        guard let base = ent.pointee.fts_path, nameLen > 0, pathLen >= nameLen else {
            return "?"
        }
        let start = base + (pathLen - nameLen)
        return String(decoding: UnsafeRawBufferPointer(start: start, count: nameLen)
                        .bindMemory(to: UInt8.self), as: UTF8.self)
    }
}

// MARK: - Shared scan state

/// Counters shared by the concurrent subtree walkers.
final class ScanState: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var current = ""
    private var unreadable = 0
    private var cancelled = false
    private var seenInodes = Set<InodeKey>()
    private var merged = TopFileBuffer(capacity: 0)

    let topFileCapacity: Int

    init(topFileCapacity: Int) {
        self.topFileCapacity = topFileCapacity
        self.merged = TopFileBuffer(capacity: topFileCapacity)
    }

    struct InodeKey: Hashable { let ino: UInt64; let dev: Int32 }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    var unreadableCount: Int {
        lock.lock(); defer { lock.unlock() }
        return unreadable
    }

    func noteUnreadable() {
        lock.lock(); unreadable += 1; lock.unlock()
    }

    /// Offers a file found during skeleton building to the largest-files list.
    func considerTopFile(size: Int64, path: String) {
        lock.lock()
        merged.consider(size: size) { path }
        lock.unlock()
    }

    /// Claims a hard-linked inode. Returns false if another walker already
    /// counted it.
    func claimInode(_ ino: UInt64, dev: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return seenInodes.insert(InodeKey(ino: ino, dev: dev)).inserted
    }

    /// Running totals for the progress display. Called every few thousand
    /// entries per walker, so contention stays negligible.
    func publish(files f: Int, bytes b: Int64, path: String) {
        lock.lock()
        // Each walker reports its own running totals; the snapshot is the sum
        // of the last value seen from each, which is close enough for a
        // progress line and avoids double counting on the final commit.
        progressByPath[path] = (f, b)
        current = path
        lock.unlock()
    }

    private var progressByPath: [String: (Int, Int64)] = [:]

    func snapshot() -> TreeScanProgress {
        lock.lock(); defer { lock.unlock() }
        var f = 0, b: Int64 = 0
        for (_, v) in progressByPath { f += v.0; b += v.1 }
        return TreeScanProgress(filesSeen: f, bytesSeen: b, currentPath: current)
    }

    func commit(files f: Int, bytes b: Int64, unreadable u: Int, top: [LargeFile]) {
        lock.lock()
        files += f; bytes += b; unreadable += u
        for item in top { merged.insert(item) }
        lock.unlock()
    }

    func topFiles() -> [LargeFile] {
        lock.lock(); defer { lock.unlock() }
        return merged.items
    }
}

/// Bounded largest-files list. Keeps the top N by size without holding a
/// record for every file on the volume.
private struct TopFileBuffer {
    private(set) var items: [LargeFile] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        items.reserveCapacity(min(capacity, 1024))
    }

    /// The path is built lazily: constructing a String for every file on disk
    /// would cost more than the rest of the walk.
    mutating func consider(size: Int64, path: () -> String) {
        guard capacity > 0 else { return }
        if items.count < capacity {
            insert(LargeFile(path: path(), size: size))
        } else if size > items[items.count - 1].size {
            insert(LargeFile(path: path(), size: size))
        }
    }

    mutating func insert(_ file: LargeFile) {
        guard capacity > 0 else { return }
        // Binary insertion keeps the list ordered without re-sorting.
        var lo = 0, hi = items.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if items[mid].size > file.size { lo = mid + 1 } else { hi = mid }
        }
        items.insert(file, at: lo)
        if items.count > capacity { items.removeLast() }
    }
}
