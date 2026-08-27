import SwiftUI
import DiskSpacerCore

enum AppTab: String, CaseIterable, Identifiable {
    case clean = "Clean"
    case explore = "Explore"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .clean:   return "sparkles"
        case .explore: return "chart.bar.doc.horizontal"
        }
    }
}

struct ContentView: View {
    @State private var model = AppModel()
    @State private var explore = ExploreModel()
    @State private var tab: AppTab = .clean

    var body: some View {
        VStack(spacing: 0) {
            TabBar(tab: $tab)
            Divider()

            switch tab {
            case .clean:
                CleanTab(model: model)
            case .explore:
                ExploreView(model: explore) { methodID in
                    // Following a folder to the method that cleans it: switch
                    // tabs, scan if this is the first visit, and open that
                    // method's card so the user lands on the right thing.
                    tab = .clean
                    model.focus(methodID: methodID)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(.background)
        .sheet(isPresented: $model.showConfirm) {
            ConfirmSheet(model: model)
        }
    }
}

struct TabBar: View {
    @Binding var tab: AppTab

    var body: some View {
        HStack {
            Picker("", selection: $tab) {
                ForEach(AppTab.allCases) { t in
                    Label(t.rawValue, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// The original single-screen flow, now one of two tabs.
struct CleanTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)

            Divider()

            Group {
                switch model.phase {
                case .idle:
                    IdleView(model: model)
                case .scanning:
                    ScanningView(model: model)
                case .reviewing:
                    ReviewView(model: model)
                case .cleaning:
                    CleaningView(model: model)
                case .finished:
                    ResultView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.phase == .reviewing {
                Divider()
                ActionBar(model: model)
            }
        }
    }
}

// MARK: - Header

struct HeaderView: View {
    @Bindable var model: AppModel

    private var free: Int64 { model.results?.availableBefore ?? DiskSizer.availableCapacity() ?? 0 }
    private var total: Int64 { model.results?.totalCapacity ?? DiskSizer.totalCapacity() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disk Spacer")
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.phase == .reviewing || model.phase == .finished {
                    Button {
                        model.scan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                }
            }

            CapacityBar(
                total: total,
                free: free,
                reclaimable: model.phase == .reviewing ? model.selectedBytes : 0)

            if !model.hasFullDiskAccess {
                FullDiskAccessBanner()
            }
        }
        .padding(Theme.gutter)
    }

    private var subtitle: String {
        switch model.phase {
        case .idle:      return "Analyse what's using space before removing anything"
        case .scanning:  return "Analysing…"
        case .reviewing:
            let r = model.results?.reclaimable ?? 0
            return r > 0
                ? "\(formatBytes(r)) can be reclaimed across \(model.actionableReports.count) methods"
                : "Nothing to reclaim — your disk is already tidy"
        case .cleaning:  return "Reclaiming space…"
        case .finished:  return "Done"
        }
    }
}

/// Free / used bar, with the pending reclaim highlighted inside the used
/// portion so the user can see what they're about to get back.
struct CapacityBar: View {
    let total: Int64
    let free: Int64
    let reclaimable: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let usedFrac = total > 0 ? Double(total - free) / Double(total) : 0
                let reclaimFrac = total > 0 ? Double(reclaimable) / Double(total) : 0

                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: max(0, w * usedFrac))
                    // The slice that's about to come back, drawn at the boundary.
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, w * reclaimFrac))
                        .offset(x: max(0, w * (usedFrac - reclaimFrac)))
                        .animation(.easeOut(duration: 0.25), value: reclaimable)
                }
            }
            .frame(height: 8)

            HStack(spacing: 14) {
                legend(color: .secondary.opacity(0.45), text: "\(formatBytes(total - free)) used")
                if reclaimable > 0 {
                    legend(color: .accentColor, text: "\(formatBytes(reclaimable)) selected")
                }
                Spacer()
                Text("\(formatBytes(free)) free of \(formatBytes(total))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Some locations can't be read")
                    .font(.callout.weight(.medium))
                Text("Grant Full Disk Access for a complete picture. Sizes below may be understated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(Permissions.settingsURL)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25)))
    }
}

// MARK: - Phases

struct IdleView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "internaldrive")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("Find space to reclaim")
                    .font(.title3.weight(.medium))
                Text("Disk Spacer looks through developer caches, package managers,\ncontainers and your Trash — and shows you exactly what it found\nbefore anything is removed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Analyse Disk") { model.scan() }
                .controlSize(.extraLarge)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

struct ScanningView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: model.scanProgress?.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 260)
            Text(model.scanProgress.map { "\($0.currentTitle)  ·  \($0.completed) of \($0.total)" }
                 ?? "Starting…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("Cancel") { model.cancelScan() }
                .controlSize(.small)
            Spacer()
        }
    }
}

struct CleaningView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView(value: model.cleanProgress?.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 260)
            Text(model.cleanProgress.map {
                "\($0.completed) of \($0.total)  ·  \(($0.currentPath as NSString).lastPathComponent)"
            } ?? "Starting…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 420)
            Spacer()
        }
    }
}

// MARK: - Review

struct ReviewView: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.reports.isEmpty {
            ContentUnavailableViewCompat(
                title: "Nothing found",
                message: "No reclaimable space was detected.",
                systemImage: "checkmark.circle")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.actionableReports) { report in
                            MethodCard(model: model, report: report)
                                .id(report.methodID)
                        }

                        if !model.inactiveReports.isEmpty {
                            InactiveSection(reports: model.inactiveReports)
                        }
                    }
                    .padding(Theme.gutter)
                }
                // Arriving from Explore: bring the requested method into view.
                .onChange(of: model.focusedMethod) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                    model.focusedMethod = nil
                }
                .onAppear {
                    guard let id = model.focusedMethod else { return }
                    proxy.scrollTo(id, anchor: .top)
                    model.focusedMethod = nil
                }
            }
        }
    }
}

/// Methods that found nothing. Shown so it's obvious the app checked them,
/// rather than leaving the user to wonder whether Docker was even looked at.
struct InactiveSection: View {
    let reports: [MethodReport]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("\(reports.count) methods found nothing to clean")
                        .font(.callout)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(reports) { r in
                        HStack(spacing: 8) {
                            Image(systemName: Theme.icon(for: r.status))
                                .font(.caption)
                                .foregroundStyle(r.status == .needsFullDiskAccess
                                                 ? Color.orange
                                                 : Color.secondary.opacity(0.6))
                                .frame(width: 14)
                            Text(r.title).font(.caption)
                            Text(r.detail ?? statusText(r.status))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.top, 6)
    }

    private func statusText(_ s: ScanStatus) -> String {
        switch s {
        case .empty:               return "nothing to clean"
        case .needsFullDiskAccess: return "needs Full Disk Access"
        case .toolUnavailable:     return "not installed"
        case .failed:              return "failed"
        case .ok:                  return ""
        }
    }
}

/// Fallback for ContentUnavailableView, which is macOS 14+ but awkward to
/// style consistently here.
struct ContentUnavailableViewCompat: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.medium))
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Action bar

struct ActionBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack {
            if model.selectedCount > 0 {
                Text("\(model.selectedCount) item\(model.selectedCount == 1 ? "" : "s") selected")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Select what to remove")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.showConfirm = true
            } label: {
                Text(model.selectedBytes > 0
                     ? "Reclaim \(formatBytes(model.selectedBytes))"
                     : "Reclaim")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selectedBytes == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
