import XCTest
@testable import DiskSpacerCore

/// The guard and the dedupe are the two places where a bug is expensive:
/// one deletes the wrong thing, the other lies about how much you'll get back.
final class SafetyGuardTests: XCTestCase {

    private let home = NSHomeDirectory()

    func testRefusesProtectedLocations() {
        for path in ["/", home, "\(home)/Documents", "\(home)/Desktop",
                     "\(home)/Library", "\(home)/.ssh", "\(home)/Pictures"] {
            XCTAssertThrowsError(try SafetyGuard.validate(path),
                                 "should refuse \(path)")
        }
    }

    func testRefusesPathsOutsideAllowlist() {
        for path in ["/System/Library/Kernels", "/usr/bin/swift", "/etc/passwd",
                     "\(home)/Work/project/src", "\(home)/Movies/holiday.mov",
                     "/Applications/Xcode.app"] {
            XCTAssertThrowsError(try SafetyGuard.validate(path),
                                 "should refuse \(path)")
        }
    }

    func testRefusesAllowedRootItself() {
        // Emptying a cache directory is fine; removing the directory is not.
        XCTAssertThrowsError(try SafetyGuard.validate("\(home)/Library/Caches"))
        XCTAssertThrowsError(try SafetyGuard.validate("\(home)/.Trash"))
        XCTAssertThrowsError(try SafetyGuard.validate("\(home)/Downloads"))
    }

    func testAcceptsDescendantsOfAllowedRoots() {
        for path in ["\(home)/Library/Caches/Spotify",
                     "\(home)/Library/Developer/Xcode/DerivedData/App-abc",
                     "\(home)/.npm/_cacache",
                     "\(home)/.Trash/old.zip",
                     "\(home)/Downloads/installer.dmg"] {
            XCTAssertNoThrow(try SafetyGuard.validate(path), "should allow \(path)")
        }
    }

    func testRefusesTraversalEscape() {
        // A relative escape must not slip past by textually starting inside a root.
        XCTAssertThrowsError(
            try SafetyGuard.validate("\(home)/Library/Caches/../../Documents/taxes"))
    }

    func testPrefixMatchIsPathAware() {
        // "~/Downloads-old" must not be treated as inside "~/Downloads".
        XCTAssertThrowsError(try SafetyGuard.validate("\(home)/Downloads-old/file.dmg"))
        XCTAssertThrowsError(try SafetyGuard.validate("\(home)/.Trashcan/file"))
    }
}

final class DeduplicationTests: XCTestCase {

    /// Minimal cleaner used only to supply an id/priority to the dedupe.
    private struct Stub: Cleaner {
        let id: String
        let priority: Int
        let title = "stub"
        let category = MethodCategory.caches
        let safety = Safety.regenerable
        let action = RemovalAction.delete
        let whatItIs = ""
        let whatRegenerates = ""
        let manualCommand = ""
        func scan() async -> MethodReport { report(items: [], status: .empty) }
    }

    private func makeReport(_ id: String, _ paths: [(String, Int64)]) -> MethodReport {
        MethodReport(
            methodID: id, title: id, category: .caches, safety: .regenerable,
            action: .delete, whatItIs: "", whatRegenerates: "", manualCommand: "",
            items: paths.map { CleanupItem(path: $0.0, size: $0.1) },
            status: .ok)
    }

    func testHigherPriorityMethodKeepsContestedPath() {
        let low  = makeReport("low",  [("/a/shared", 100)])
        let high = makeReport("high", [("/a/shared", 100)])
        let out = ScanEngine.deduplicate(
            [low, high],
            cleaners: [Stub(id: "low", priority: 0), Stub(id: "high", priority: 10)])

        let byID = Dictionary(uniqueKeysWithValues: out.map { ($0.methodID, $0) })
        XCTAssertEqual(byID["high"]?.items.count, 1)
        XCTAssertEqual(byID["low"]?.items.count, 0)
        XCTAssertEqual(out.reduce(0) { $0 + $1.totalSize }, 100, "counted twice")
    }

    func testParentIsDroppedWhenChildIsClaimed() {
        // The real Homebrew case: the specific method claims files inside a
        // directory the generic bucket lists whole.
        let generic  = makeReport("generic",  [("/caches/Homebrew", 1_920)])
        let specific = makeReport("specific", [("/caches/Homebrew/Cask/x", 832)])
        let out = ScanEngine.deduplicate(
            [generic, specific],
            cleaners: [Stub(id: "generic", priority: 0), Stub(id: "specific", priority: 20)])

        let byID = Dictionary(uniqueKeysWithValues: out.map { ($0.methodID, $0) })
        XCTAssertEqual(byID["specific"]?.items.count, 1)
        XCTAssertEqual(byID["generic"]?.items.count, 0,
                       "parent must be surrendered, not double counted")
        XCTAssertEqual(out.reduce(0) { $0 + $1.totalSize }, 832)
    }

    func testChildIsDroppedWhenParentIsClaimed() {
        let parent = makeReport("parent", [("/caches/big", 500)])
        let child  = makeReport("child",  [("/caches/big/inner", 200)])
        let out = ScanEngine.deduplicate(
            [parent, child],
            cleaners: [Stub(id: "parent", priority: 20), Stub(id: "child", priority: 0)])

        XCTAssertEqual(out.reduce(0) { $0 + $1.totalSize }, 500)
    }

    func testSiblingPathsAreBothKept() {
        let a = makeReport("a", [("/caches/one", 10)])
        let b = makeReport("b", [("/caches/two", 20)])
        let out = ScanEngine.deduplicate(
            [a, b], cleaners: [Stub(id: "a", priority: 0), Stub(id: "b", priority: 10)])
        XCTAssertEqual(out.reduce(0) { $0 + $1.totalSize }, 30)
    }

    func testSimilarlyNamedSiblingIsNotTreatedAsNested() {
        // "/caches/big2" must not be swallowed by a claim on "/caches/big".
        let a = makeReport("a", [("/caches/big", 10)])
        let b = makeReport("b", [("/caches/big2", 20)])
        let out = ScanEngine.deduplicate(
            [a, b], cleaners: [Stub(id: "a", priority: 10), Stub(id: "b", priority: 0)])
        XCTAssertEqual(out.reduce(0) { $0 + $1.totalSize }, 30)
    }

    func testCommandItemsAreNeverDeduped() {
        // docker:// ids aren't paths and must survive.
        let a = makeReport("a", [("docker://build-cache", 400)])
        let b = makeReport("b", [("docker://images", 100)])
        let out = ScanEngine.deduplicate(
            [a, b], cleaners: [Stub(id: "a", priority: 0), Stub(id: "b", priority: 0)])
        XCTAssertEqual(out.reduce(0) { $0 + $1.totalSize }, 500)
    }
}

final class SizingTests: XCTestCase {

    func testMeasuresDirectoryAndCountsHardLinkOnce() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskspacer-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let payload = Data(repeating: 0x41, count: 200_000)
        let original = tmp.appendingPathComponent("original.bin")
        try payload.write(to: original)

        let single = DiskSizer.measure(tmp)
        XCTAssertGreaterThanOrEqual(single.bytes, 200_000)
        XCTAssertEqual(single.fileCount, 1)

        // A hard link to the same inode must not add to the total.
        let link = tmp.appendingPathComponent("hardlink.bin")
        try FileManager.default.linkItem(at: original, to: link)

        let linked = DiskSizer.measure(tmp)
        XCTAssertTrue(linked.sawHardLinks)
        XCTAssertEqual(linked.bytes, single.bytes,
                       "hard-linked inode counted more than once")
    }

    func testSymlinkIsNotFollowed() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskspacer-test-\(UUID().uuidString)")
        let target = tmp.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data(repeating: 0x42, count: 300_000)
            .write(to: target.appendingPathComponent("big.bin"))

        let before = DiskSizer.measure(tmp)
        try FileManager.default.createSymbolicLink(
            at: tmp.appendingPathComponent("alias"), withDestinationURL: target)
        let after = DiskSizer.measure(tmp)

        XCTAssertEqual(before.bytes, after.bytes, "symlink was followed")
    }

    func testMissingPathMeasuresZero() {
        let m = DiskSizer.measure(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertEqual(m.bytes, 0)
        XCTAssertFalse(m.accessDenied)
    }
}

final class ParsingTests: XCTestCase {

    func testFormatBytesIsHumanReadable() {
        // Unit names are localized ("GB" vs "Go"), so assert on scale, not text.
        XCTAssertFalse(formatBytes(0).isEmpty)
        let big = formatBytes(5_000_000_000)
        XCTAssertTrue(big.contains("5"), "expected a 5-something figure, got \(big)")
        XCTAssertNotEqual(formatBytes(5_000_000_000), formatBytes(5_000_000))
    }
}

/// Exercises the actual removal path end to end. Everything else tests the
/// guard in isolation; this drives validate → removeItem → summary against a
/// real directory, inside an allowlisted root so the guard permits it.
final class RemoverTests: XCTestCase {

    private let sandbox = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Caches/diskspacer-selftest")

    override func setUpWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
        try FileManager.default.createDirectory(
            at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func makeVictim(_ name: String, bytes: Int) throws -> CleanupItem {
        let dir = sandbox.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes)
            .write(to: dir.appendingPathComponent("payload.bin"))
        let size = DiskSizer.measure(dir).bytes
        return CleanupItem(path: dir.path, size: size)
    }

    private func report(_ items: [CleanupItem],
                        action: RemovalAction = .delete) -> MethodReport {
        MethodReport(
            methodID: "selftest", title: "Self Test", category: .caches,
            safety: .regenerable, action: action, whatItIs: "", whatRegenerates: "",
            manualCommand: "", items: items, status: .ok)
    }

    func testDeletesSelectedAndReportsFreedBytes() async throws {
        let a = try makeVictim("alpha", bytes: 120_000)
        let b = try makeVictim("beta",  bytes: 80_000)
        let r = report([a, b])

        let summary = await Remover.clean(
            reports: [r], selection: ["selftest": Set([a.path, b.path])])

        XCTAssertEqual(summary.succeededCount, 2)
        XCTAssertTrue(summary.failures.isEmpty, "\(summary.failures)")
        XCTAssertEqual(summary.freedBytes, a.size + b.size)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))
    }

    func testUnselectedItemsSurvive() async throws {
        let keep = try makeVictim("keep",   bytes: 60_000)
        let go   = try makeVictim("remove", bytes: 60_000)
        let r = report([keep, go])

        let summary = await Remover.clean(
            reports: [r], selection: ["selftest": Set([go.path])])

        XCTAssertEqual(summary.succeededCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path),
                      "an unselected item was removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: go.path))
    }

    func testEmptySelectionRemovesNothing() async throws {
        let a = try makeVictim("untouched", bytes: 50_000)
        let summary = await Remover.clean(reports: [report([a])], selection: [:])

        XCTAssertEqual(summary.results.count, 0)
        XCTAssertEqual(summary.freedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    /// The guard must still refuse a path smuggled in via a crafted report,
    /// because selections pass through the UI between scan and clean.
    func testRefusesPathOutsideAllowlistEvenIfReportClaimsIt() async throws {
        let outside = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/diskspacer-must-not-touch")
        let item = CleanupItem(path: outside.path, size: 999)

        let summary = await Remover.clean(
            reports: [report([item])], selection: ["selftest": Set([item.path])])

        XCTAssertEqual(summary.succeededCount, 0)
        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertEqual(summary.freedBytes, 0)
    }
}

/// The tree scanner's failure modes are all silent — a wrong total looks like
/// a right one. These pin the cases that actually went wrong while building it.
final class TreeScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("diskspacer-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions on anything made unreadable, or cleanup fails.
        let denied = root.appendingPathComponent("denied")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: denied.path)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ relative: String, megabytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x7A, count: megabytes * 1_000_000).write(to: url)
        return url
    }

    private func scan() async -> TreeScanResult {
        let volume = VolumeInfo(
            name: "test", path: root.path, totalBytes: 0, freeBytes: 0,
            isRootFileSystem: false, isRemovable: false, isLocal: true, isReadOnly: false)
        return await TreeScanner.scan(volume: volume, topFileCount: 10)
    }

    /// Every directory's total must equal its own files plus its children's
    /// totals. A roll-up that double-counts or misses a subtree breaks this.
    private func assertTotalsConsistent(_ node: DirNode, file: StaticString = #filePath,
                                        line: UInt = #line) {
        let childSum = node.children.reduce(Int64(0)) { $0 + $1.bytes }
        XCTAssertGreaterThanOrEqual(node.bytes, childSum,
            "\(node.name): total \(node.bytes) < children \(childSum)", file: file, line: line)
        for c in node.children { assertTotalsConsistent(c, file: file, line: line) }
    }

    func testAggregatesUpTheTree() async throws {
        _ = try makeFile("a/big.bin", megabytes: 8)
        _ = try makeFile("a/sub/small.bin", megabytes: 2)
        _ = try makeFile("top.bin", megabytes: 4)

        let r = await scan()
        XCTAssertEqual(r.fileCount, 3)
        // ~14 MB, allowing for allocation rounding.
        XCTAssertGreaterThanOrEqual(r.scannedBytes, 14_000_000)
        XCTAssertLessThan(r.scannedBytes, 16_000_000)
        assertTotalsConsistent(r.root)

        let a = try XCTUnwrap(r.root.children.first { $0.name == "a" })
        XCTAssertGreaterThanOrEqual(a.bytes, 10_000_000, "subtree total must include a/sub")
    }

    func testChildrenSortedLargestFirst() async throws {
        _ = try makeFile("small/f.bin", megabytes: 1)
        _ = try makeFile("large/f.bin", megabytes: 9)
        _ = try makeFile("medium/f.bin", megabytes: 5)

        let r = await scan()
        XCTAssertEqual(r.root.children.map(\.name), ["large", "medium", "small"])
    }

    func testHardLinkCountedOnce() async throws {
        let original = try makeFile("a/original.bin", megabytes: 10)
        let dir = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.linkItem(
            at: original, to: dir.appendingPathComponent("same.bin"))

        let r = await scan()
        // One copy on disk, reachable under two names.
        XCTAssertLessThan(r.scannedBytes, 12_000_000,
                          "hard-linked file counted more than once")
    }

    func testSymlinkedDirectoryIsNotFollowed() async throws {
        _ = try makeFile("real/payload.bin", megabytes: 6)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("alias"),
            withDestinationURL: root.appendingPathComponent("real"))

        let r = await scan()
        XCTAssertLessThan(r.scannedBytes, 8_000_000, "symlinked directory was followed")
        assertTotalsConsistent(r.root)
    }

    /// An unreadable directory is reported by fts twice — once entering, then
    /// again as an error instead of being descended into, with no matching
    /// close. Mishandling that leaked the stack and silently reparented every
    /// later sibling, which showed up as a total of zero.
    func testUnreadableDirectoryDoesNotCorruptTheTree() async throws {
        _ = try makeFile("denied/secret.bin", megabytes: 5)
        _ = try makeFile("after/visible.bin", megabytes: 7)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: root.appendingPathComponent("denied").path)

        let r = await scan()

        XCTAssertGreaterThan(r.unreadableCount, 0, "unreadable directory not reported")
        assertTotalsConsistent(r.root)

        // The sibling scanned after it must still be attached to the root with
        // its real size — that is what the stack leak used to destroy.
        let after = try XCTUnwrap(r.root.children.first { $0.name == "after" })
        XCTAssertGreaterThanOrEqual(after.bytes, 7_000_000)
        XCTAssertGreaterThanOrEqual(r.scannedBytes, 7_000_000,
                                    "totals collapsed after an unreadable directory")
    }

    func testLargestFilesAreBoundedAndSorted() async throws {
        for i in 1...15 { _ = try makeFile("files/f\(i).bin", megabytes: i) }

        let r = await scan()
        XCTAssertEqual(r.largestFiles.count, 10, "top-N list not capped")
        XCTAssertEqual(r.largestFiles, r.largestFiles.sorted { $0.size > $1.size })
        XCTAssertEqual(r.largestFiles.first?.name, "f15.bin")
        // Every entry must be a real path.
        for f in r.largestFiles {
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.path), "\(f.path)")
        }
    }

    func testPathIsRebuiltFromNames() async throws {
        _ = try makeFile("one/two/three/deep.bin", megabytes: 3)
        let r = await scan()

        var node = r.root
        for _ in 0..<3 { node = try XCTUnwrap(node.children.first) }
        XCTAssertEqual(node.path, root.appendingPathComponent("one/two/three").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: node.path))
    }

    func testEmptyDirectoryScansCleanly() async throws {
        let r = await scan()
        XCTAssertEqual(r.scannedBytes, 0)
        XCTAssertEqual(r.fileCount, 0)
        XCTAssertFalse(r.cancelled)
    }
}

final class CleanupHintTests: XCTestCase {

    /// The hint table exists to link Explore back to a Clean method. A typo in
    /// a path or an id would silently break that link, so check they resolve.
    func testHintsPointAtRealCleanupMethods() {
        let home = NSHomeDirectory()
        let knownIDs = Set(Catalog.allCleaners().map(\.id))
        let probes = [
            "\(home)/Library/Caches",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/.npm",
            "\(home)/go/pkg/mod",
            "\(home)/.Trash",
        ]
        for path in probes {
            let hint = CleanupHints.hint(forPath: path)
            XCTAssertNotNil(hint, "no hint for \(path)")
            if let h = hint {
                XCTAssertTrue(knownIDs.contains(h.methodID),
                              "\(h.methodID) is not a real cleanup method")
            }
        }
    }

    func testUnknownPathHasNoHint() {
        XCTAssertNil(CleanupHints.hint(forPath: "/some/random/place"))
        XCTAssertNotNil(CleanupHints.note(forName: "node_modules"))
    }
}

final class VolumeTests: XCTestCase {

    /// The home folder is only part of its volume. Comparing a home scan
    /// against the volume's used space would report everything outside the
    /// home folder as "unaccounted for" — 115 GB of nonsense on a real Mac,
    /// shown by default because Home is the first entry in the picker.
    func testHomeFolderIsNotTreatedAsAWholeVolume() {
        let home = Volumes.homeFolder()
        XCTAssertFalse(home.coversWholeVolume,
                       "a home scan must not be compared against whole-volume usage")
        XCTAssertEqual(home.path, NSHomeDirectory())
    }

    func testRealVolumesCoverTheirWholeVolume() throws {
        let volumes = Volumes.scannable()
        XCTAssertFalse(volumes.isEmpty, "no scannable volumes found")
        for v in volumes {
            XCTAssertTrue(v.coversWholeVolume, "\(v.name) should cover its volume")
        }
        // The startup disk must be offered, and listed first.
        XCTAssertTrue(volumes.first?.isRootFileSystem == true)
    }

    /// Free space changes constantly. If equality covered it, the same volume
    /// would stop matching itself between two calls, and a SwiftUI Picker
    /// holding the earlier value would silently render blank.
    func testVolumeIdentityIgnoresChangingFreeSpace() throws {
        let a = try XCTUnwrap(Volumes.scannable().first)
        let drifted = VolumeInfo(
            name: a.name, path: a.path, totalBytes: a.totalBytes,
            freeBytes: a.freeBytes - 4096, isRootFileSystem: a.isRootFileSystem,
            isRemovable: a.isRemovable, isLocal: a.isLocal, isReadOnly: a.isReadOnly)
        XCTAssertEqual(a, drifted, "free-space drift must not change identity")
        XCTAssertEqual(a.hashValue, drifted.hashValue)
        XCTAssertEqual(Set([a, drifted]).count, 1)
    }

    /// Re-entering the tab re-lists volumes; the previously selected value has
    /// to still match one of them or the picker loses its selection.
    func testSelectionSurvivesReListing() throws {
        let first = try XCTUnwrap(Volumes.scannable().first)
        let second = Volumes.scannable()
        XCTAssertTrue(second.contains(first),
                      "a volume from an earlier listing no longer matches")
    }

    func testNetworkVolumesAreExcludedByDefault() {
        for v in Volumes.scannable() {
            XCTAssertTrue(v.isLocal, "\(v.name) is a network share and would be slow to walk")
        }
    }
}
