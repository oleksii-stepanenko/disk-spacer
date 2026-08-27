import SwiftUI
import DiskSpacerCore

/// One cleanup method, collapsed to a summary row and expandable to reveal
/// exactly what would be removed, what it is, what comes back, and the
/// equivalent Terminal command.
struct MethodCard: View {
    @Bindable var model: AppModel
    let report: MethodReport

    private var isExpanded: Bool { model.expanded.contains(report.methodID) }
    private var state: SelectionState { model.selectionState(report) }
    private var accent: Color { Theme.color(for: report.safety) }

    var body: some View {
        Card(highlighted: state != .none) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    Divider().padding(.horizontal, 14)
                    details
                }
            }
        }
    }

    // MARK: Header row

    private var header: some View {
        HStack(spacing: 12) {
            TriStateCheckbox(state: state) { model.toggleAll(report) }

            Image(systemName: Theme.icon(for: report.category))
                .font(.system(size: 13))
                .foregroundStyle(accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(report.title).font(.body.weight(.medium))
                    Badge(text: report.safety.shortLabel, color: accent)
                    if report.action == .trash {
                        Badge(text: "to Trash", color: .secondary)
                    }
                }
                Text("\(report.items.count) item\(report.items.count == 1 ? "" : "s") · \(report.category.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text((report.sizeIsUpperBound ? "≤ " : "") + formatBytes(report.totalSize))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if report.sizeIsUpperBound {
                    Text("upper bound")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    model.toggleExpanded(report.methodID)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.toggleExpanded(report.methodID)
            }
        }
    }

    // MARK: Expanded detail

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {

            explanation

            if let detail = report.detail {
                Label(detail, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            itemList

            manualSection
        }
        .padding(14)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            labelled("What this is", report.whatItIs)
            labelled("After removing", report.whatRegenerates)
        }
    }

    private func labelled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("WILL BE \(report.action.verb.uppercased())D")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
                Button(state == .all ? "Deselect all" : "Select all") {
                    model.toggleAll(report)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            // Long lists scroll inside the card so one huge method can't push
            // everything else off screen.
            let rows = ForEach(report.items) { item in
                ItemRow(
                    item: item,
                    isSelected: model.isSelected(report, item),
                    isPath: item.isFilesystemPath,
                    toggle: { model.toggle(report, item) })
            }

            if report.items.count > 8 {
                ScrollView { VStack(spacing: 0) { rows } }
                    .frame(height: 220)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.03)))
            } else {
                VStack(spacing: 0) { rows }
            }
        }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DO IT YOURSELF")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            HStack(spacing: 8) {
                Text(report.manualCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05)))
                CopyButton(text: report.manualCommand)
            }
        }
    }
}

/// One removable item. Shows the full path on hover so the user can tell two
/// similarly-named folders apart before ticking either.
struct ItemRow: View {
    let item: CleanupItem
    let isSelected: Bool
    let isPath: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Text(item.displayName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            if let note = item.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(formatBytes(item.size))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if isPath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .help(isPath ? item.path : item.displayName)
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? .green : .secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Copy command")
    }
}
