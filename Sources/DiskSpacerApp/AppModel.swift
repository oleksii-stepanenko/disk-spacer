import Foundation
import Observation
import DiskSpacerCore

enum Phase {
    case idle
    case scanning
    case reviewing
    case cleaning
    case finished
}

@MainActor
@Observable
final class AppModel {

    var phase: Phase = .idle
    var results: ScanResults?
    var scanProgress: ScanProgress?
    var cleanProgress: CleanProgress?
    var summary: CleanSummary?
    var expanded: Set<String> = []
    var showConfirm = false

    /// Selected item paths, keyed by method id.
    private(set) var selection: [String: Set<String>] = [:]

    private var scanTask: Task<Void, Never>?
    private var cleanTask: Task<Void, Never>?

    var hasFullDiskAccess: Bool = Permissions.hasFullDiskAccess

    // MARK: - Derived

    var reports: [MethodReport] { results?.reports ?? [] }
    var actionableReports: [MethodReport] { reports.filter(\.isActionable) }

    /// Methods that found nothing, or couldn't run — shown collapsed so the
    /// user can see the app looked rather than wondering if it skipped them.
    var inactiveReports: [MethodReport] { reports.filter { !$0.isActionable } }

    /// Bytes the user has actually ticked, which is what the button promises.
    var selectedBytes: Int64 {
        reports.reduce(0) { total, r in
            guard let picked = selection[r.methodID] else { return total }
            return total + r.items.filter { picked.contains($0.path) }
                                  .reduce(0) { $0 + $1.size }
        }
    }

    var selectedCount: Int {
        selection.values.reduce(0) { $0 + $1.count }
    }

    /// True when any selected method deletes irreversibly, so the confirm
    /// sheet can escalate its warning.
    var selectionIncludesIrreversible: Bool {
        reports.contains {
            $0.safety == .irreversible && !(selection[$0.methodID] ?? []).isEmpty
        }
    }

    var selectedReportsWithItems: [(MethodReport, [CleanupItem])] {
        reports.compactMap { r in
            guard let picked = selection[r.methodID], !picked.isEmpty else { return nil }
            let items = r.items.filter { picked.contains($0.path) }
            return items.isEmpty ? nil : (r, items)
        }
    }

    // MARK: - Selection

    func isSelected(_ report: MethodReport, _ item: CleanupItem) -> Bool {
        selection[report.methodID]?.contains(item.path) ?? false
    }

    func selectionState(_ report: MethodReport) -> SelectionState {
        let picked = selection[report.methodID] ?? []
        if picked.isEmpty { return .none }
        return picked.count == report.items.count ? .all : .some
    }

    func toggle(_ report: MethodReport, _ item: CleanupItem) {
        var picked = selection[report.methodID] ?? []
        if picked.contains(item.path) { picked.remove(item.path) }
        else { picked.insert(item.path) }
        selection[report.methodID] = picked.isEmpty ? nil : picked
    }

    func toggleAll(_ report: MethodReport) {
        if selectionState(report) == .all {
            selection[report.methodID] = nil
        } else {
            selection[report.methodID] = Set(report.items.map(\.path))
        }
    }

    /// Preselects only what is safe to remove without thought. Anything marked
    /// "review first" or irreversible starts unticked — the user opts in.
    private func applyDefaultSelection(_ results: ScanResults) {
        var next: [String: Set<String>] = [:]
        for r in results.reports where r.isActionable && r.safety == .regenerable {
            next[r.methodID] = Set(r.items.map(\.path))
        }
        selection = next
    }

    // MARK: - Actions

    func scan() {
        scanTask?.cancel()
        phase = .scanning
        scanProgress = nil
        summary = nil
        hasFullDiskAccess = Permissions.hasFullDiskAccess

        // AppModel is @MainActor and therefore Sendable, so capturing it
        // strongly here is safe; the task is cancelled before a new one starts.
        scanTask = Task { @MainActor [self] in
            let results = await ScanEngine.scan { p in
                Task { @MainActor in self.scanProgress = p }
            }
            guard !Task.isCancelled else { return }
            self.results = results
            applyDefaultSelection(results)
            scanProgress = nil
            phase = .reviewing
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        phase = results == nil ? .idle : .reviewing
        scanProgress = nil
    }

    func clean() {
        guard let results else { return }
        showConfirm = false
        phase = .cleaning
        cleanProgress = nil

        let reports = results.reports
        let selection = self.selection

        cleanTask = Task { @MainActor [self] in
            let summary = await Remover.clean(reports: reports, selection: selection) { p in
                Task { @MainActor in self.cleanProgress = p }
            }
            guard !Task.isCancelled else { return }
            self.summary = summary
            cleanProgress = nil
            phase = .finished
        }
    }

    func reset() {
        results = nil
        summary = nil
        selection = [:]
        expanded = []
        phase = .idle
    }

    func toggleExpanded(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

enum SelectionState { case none, some, all }
