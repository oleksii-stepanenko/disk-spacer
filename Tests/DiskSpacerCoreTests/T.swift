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
