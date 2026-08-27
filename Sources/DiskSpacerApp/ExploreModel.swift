import Foundation
import Observation
import AppKit
import DiskSpacerCore

/// State for the Explore tab.
///
/// Deliberately read-only: this tab answers "what is using my space", and the
/// only actions it offers are looking. Removing anything is the Clean tab's
/// job, where every path is checked against an allow-list first.
@MainActor
@Observable
final class ExploreModel {

    enum Phase { case idle, scanning, browsing }

    enum Mode: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case files = "Largest Files"
        var id: String { rawValue }
    }

    var phase: Phase = .idle
    var mode: Mode = .folders
    var volumes: [VolumeInfo] = []
    var selectedVolume: VolumeInfo?
    var result: TreeScanResult?
    var progress: TreeScanProgress?
    var errorMessage: String?

    /// Navigation stack; the first entry is always the scan root.
    private(set) var stack: [DirNode] = []

    private var scanTask: Task<Void, Never>?

    var current: DirNode? { stack.last }
    var canGoBack: Bool { stack.count > 1 }
    var hasFullDiskAccess: Bool = Permissions.hasFullDiskAccess

    /// Rows for the current directory, largest first (already sorted by the scanner).
    var rows: [DirNode] { current?.children ?? [] }

    /// Breadcrumb entries, root first.
    var breadcrumb: [DirNode] { stack }

    func loadVolumes() {
        // The home folder comes first: it holds most of what a person can
        // actually act on, and unlike the whole disk it needs no extra
        // permission to read.
        var list: [VolumeInfo] = [Volumes.homeFolder()]
        list.append(contentsOf: Volumes.scannable())
        volumes = list
        if selectedVolume == nil { selectedVolume = list.first }
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    func scan() {
        guard let volume = selectedVolume else { return }
        scanTask?.cancel()
        phase = .scanning
        progress = nil
        errorMessage = nil
        result = nil
        stack = []

        scanTask = Task { @MainActor [self] in
            let scanned = await TreeScanner.scan(volume: volume) { p in
                Task { @MainActor in self.progress = p }
            }
            guard !Task.isCancelled else { return }
            result = scanned
            stack = [scanned.root]
            progress = nil
            phase = .browsing
            hasFullDiskAccess = Permissions.hasFullDiskAccess
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = result == nil ? .idle : .browsing
        progress = nil
    }

    // MARK: Navigation

    func drill(into node: DirNode) {
        guard node.hasChildren else { return }
        stack.append(node)
    }

    func goBack() {
        guard stack.count > 1 else { return }
        stack.removeLast()
    }

    /// Jumps to a breadcrumb entry.
    func jump(to index: Int) {
        guard index >= 0, index < stack.count else { return }
        stack.removeSubrange((index + 1)...)
    }

    // MARK: Read-only actions

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// A folder the Clean tab knows how to deal with, if any.
    func hint(for node: DirNode) -> CleanupHint? {
        CleanupHints.hint(forPath: node.path)
    }

    /// A softer note for well-known folder names no cleanup method owns.
    func note(for node: DirNode) -> (title: String, summary: String)? {
        CleanupHints.note(forName: node.name)
    }

    /// Fraction of the *current* directory, so the bars in a level are
    /// relative to what is on screen rather than to the whole disk.
    func fraction(of node: DirNode) -> Double {
        guard let parent = current, parent.bytes > 0 else { return 0 }
        return min(1, Double(node.bytes) / Double(parent.bytes))
    }
}
