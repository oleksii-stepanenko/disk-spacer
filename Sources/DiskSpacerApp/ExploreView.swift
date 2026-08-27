import SwiftUI
import DiskSpacerCore

/// "What is using my space" — a size-sorted, drillable view of the disk.
///
/// Read-only by design. Every row can be opened in Finder, and folders the
/// Clean tab knows about link across to it, but nothing is removed here.
struct ExploreView: View {
    @Bindable var model: ExploreModel
    /// Called when the user follows a folder to the method that cleans it.
    var onOpenCleanMethod: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()

            switch model.phase {
            case .idle:     idle
            case .scanning: scanning
            case .browsing: browsing
            }
        }
        .onAppear { model.loadVolumes() }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $model.selectedVolume) {
                ForEach(model.volumes) { v in
                    Text(v.name).tag(Optional(v))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            .disabled(model.phase == .scanning)

            if model.phase == .browsing {
                Picker("", selection: $model.mode) {
                    ForEach(ExploreModel.Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }

            Spacer()

            if model.phase == .scanning {
                Button("Stop") { model.cancelScan() }
            } else {
                Button(model.result == nil ? "Scan" : "Rescan") { model.scan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 10)
    }

    // MARK: Phases

    private var idle: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.pie")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("See what is using your space")
                    .font(.title3.weight(.medium))
                Text("Pick a disk and scan. Every folder shows the total size of\neverything inside it, biggest first, so you can find the\nheavy things quickly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Scan") { model.scan() }
                .controlSize(.extraLarge)
                .buttonStyle(.borderedProminent)
            Text("Nothing is deleted here — this tab only looks.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            if let p = model.progress {
                Text("\(p.filesSeen.formatted()) files · \(formatBytes(p.bytesSeen))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text((p.currentPath as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 420)
            } else {
                Text("Starting…").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var browsing: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            Divider()

            if model.mode == .folders {
                folderList
            } else {
                largestFilesList
            }

            Divider()
            summaryBar
        }
    }

    // MARK: Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canGoBack)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(model.breadcrumb.enumerated()), id: \.element.id) { idx, node in
                        if idx > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            model.jump(to: idx)
                        } label: {
                            Text(idx == 0 ? displayRootName(node) : node.name)
                                .font(.callout)
                                .foregroundStyle(idx == model.breadcrumb.count - 1
                                                 ? Color.primary : Color.accentColor)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 8)

            if let current = model.current {
                Button {
                    model.revealInFinder(current.path)
                } label: {
                    Label("Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Open this folder in Finder")
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
    }

    private func displayRootName(_ node: DirNode) -> String {
        node.path == NSHomeDirectory() ? "Home" : (node.name == "/" ? "Macintosh HD" : node.name)
    }

    // MARK: Folder list

    @ViewBuilder
    private var folderList: some View {
        if model.rows.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: model.current?.isUnreadable == true ? "lock.fill" : "folder")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(model.current?.isUnreadable == true
                     ? "This folder can't be read without Full Disk Access"
                     : "No folders inside — only files")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let c = model.current, c.fileCount > 0 {
                    Text("\(c.fileCount.formatted()) files · \(formatBytes(c.bytes))")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { node in
                        FolderRow(
                            node: node,
                            fraction: model.fraction(of: node),
                            hint: model.hint(for: node),
                            note: model.note(for: node),
                            onOpen: { model.drill(into: node) },
                            onReveal: { model.revealInFinder(node.path) },
                            onClean: { id in onOpenCleanMethod(id) })
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }

    // MARK: Largest files

    @ViewBuilder
    private var largestFilesList: some View {
        let files = model.result?.largestFiles ?? []
        if files.isEmpty {
            VStack {
                Spacer()
                Text("No large files found").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(abbreviate((file.path as NSString).deletingLastPathComponent))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 8)

                            Text(formatBytes(file.size))
                                .font(.callout.weight(.medium))
                                .monospacedDigit()

                            Button {
                                model.revealInFinder(file.path)
                            } label: {
                                Image(systemName: "magnifyingglass").font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                            .help("Reveal in Finder")
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.vertical, 7)
                        .help(file.path)
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryBar: some View {
        if let r = model.result {
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    Text("\(formatBytes(r.scannedBytes)) scanned")
                        .font(.callout.weight(.medium))
                    Text("\(r.fileCount.formatted()) files")
                        .font(.caption).foregroundStyle(.secondary)
                    if r.cancelled {
                        Badge(text: "stopped early", color: .orange)
                    }
                    Spacer()
                    Text(String(format: "%.1fs", r.duration))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }

                // The scan will never match what Finder reports, because of
                // APFS snapshots, purgeable space and anything unreadable.
                // Saying so is better than leaving the numbers to disagree
                // quietly.
                if r.volume.coversWholeVolume && r.volume.totalBytes > 0
                    && r.unaccountedBytes > 1_000_000_000 {
                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(formatBytes(r.unaccountedBytes)) not accounted for — snapshots, purgeable space\(r.unreadableCount > 0 ? ", and folders this app can't read" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if r.unreadableCount > 0 && !model.hasFullDiskAccess {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption).foregroundStyle(.orange)
                        Text("\(r.unreadableCount) folders couldn't be read — sizes are understated")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Grant Access") {
                            NSWorkspace.shared.open(Permissions.settingsURL)
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func abbreviate(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory())
            ? "~" + path.dropFirst(NSHomeDirectory().count)
            : path
    }
}

// MARK: - Row

private struct FolderRow: View {
    let node: DirNode
    let fraction: Double
    let hint: CleanupHint?
    let note: (title: String, summary: String)?
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onClean: (String) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.isUnreadable ? "lock.fill"
                            : (node.hasChildren ? "folder.fill" : "folder"))
                .font(.caption)
                .foregroundStyle(node.isUnreadable ? Color.orange
                                 : (hint.map { Theme.color(for: $0.safety) } ?? .secondary))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let hint {
                        Badge(text: hint.title, color: Theme.color(for: hint.safety))
                    } else if let note {
                        Badge(text: note.title, color: .secondary)
                    }
                }

                // A bar relative to this level, so it reads as "share of what
                // I'm looking at" rather than share of the whole disk.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(hint.map { Theme.color(for: $0.safety) } ?? Color.accentColor)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(node.isUnreadable ? "—" : formatBytes(node.bytes))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                Text("\(Int(fraction * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .frame(width: 78, alignment: .trailing)

            HStack(spacing: 2) {
                if let hint {
                    Button {
                        onClean(hint.methodID)
                    } label: {
                        Image(systemName: "sparkles").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("Clean this in the Clean tab")
                }
                Button(action: onReveal) {
                    Image(systemName: "magnifyingglass").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Reveal in Finder")

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(node.hasChildren ? .secondary : .quaternary)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
        .help(node.path)
    }

    private var subtitle: String? {
        if node.isUnreadable { return "Needs Full Disk Access" }
        if let hint { return hint.summary }
        if let note { return note.summary }
        if node.fileCount > 0 {
            return "\(node.fileCount.formatted()) files"
                + (node.hasChildren ? " · \(node.children.count) folders" : "")
        }
        return nil
    }
}
