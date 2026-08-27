import SwiftUI
import DiskSpacerCore

/// The last gate before anything is removed. Enumerates every method and every
/// item that is about to go, so "clean" is never a leap of faith.
struct ConfirmSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var groups: [(MethodReport, [CleanupItem])] { model.selectedReportsWithItems }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.0.methodID) { report, items in
                        group(report, items)
                    }
                }
                .padding(Theme.gutter)
            }
            .frame(maxHeight: 340)

            Divider()
            footer
        }
        .frame(width: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reclaim \(formatBytes(model.selectedBytes))?")
                .font(.title3.weight(.semibold))
            Text("\(model.selectedCount) item\(model.selectedCount == 1 ? "" : "s") across \(groups.count) method\(groups.count == 1 ? "" : "s"). Nothing is removed until you confirm.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if model.selectionIncludesIrreversible {
                Label(
                    "Your selection includes items that cannot be recovered.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.gutter)
    }

    private func group(_ report: MethodReport, _ items: [CleanupItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: Theme.icon(for: report.category))
                    .font(.caption)
                    .foregroundStyle(Theme.color(for: report.safety))
                Text(report.title).font(.callout.weight(.semibold))
                Badge(text: report.action.verb,
                      color: report.action == .trash ? .secondary
                                                     : Theme.color(for: report.safety))
                Spacer()
                Text(formatBytes(items.reduce(0) { $0 + $1.size }))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(items.prefix(6)) { item in
                    HStack(spacing: 6) {
                        Text("•").foregroundStyle(.tertiary)
                        Text(item.isFilesystemPath
                             ? abbreviate(item.path)
                             : item.displayName)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(formatBytes(item.size))
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                if items.count > 6 {
                    Text("  … and \(items.count - 6) more")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 4)

            if report.safety != .regenerable {
                Text(report.whatRegenerates)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                model.clean()
            } label: {
                Text("Reclaim \(formatBytes(model.selectedBytes))")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.selectionIncludesIrreversible ? .red : .accentColor)
            .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.gutter)
    }

    /// Shortens `/Users/name/Library/…` to `~/Library/…` for readability.
    private func abbreviate(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory())
            ? "~" + path.dropFirst(NSHomeDirectory().count)
            : path
    }
}

// MARK: - Result

struct ResultView: View {
    @Bindable var model: AppModel

    private var summary: CleanSummary { model.summary ?? CleanSummary() }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: summary.failures.isEmpty
                  ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundStyle(summary.failures.isEmpty ? .green : .orange)

            VStack(spacing: 6) {
                Text("Reclaimed \(formatBytes(summary.freedBytes))")
                    .font(.title2.weight(.semibold))
                Text("\(summary.succeededCount) item\(summary.succeededCount == 1 ? "" : "s") removed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !summary.failures.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(summary.failures.count) item\(summary.failures.count == 1 ? "" : "s") couldn't be removed")
                        .font(.callout.weight(.medium))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(summary.failures, id: \.path) { f in
                                HStack(alignment: .top, spacing: 6) {
                                    Text((f.path as NSString).lastPathComponent)
                                        .font(.caption.weight(.medium))
                                    Text(f.error ?? "failed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                .padding(12)
                .frame(maxWidth: 420)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
            }

            HStack(spacing: 10) {
                Button("Scan Again") { model.scan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Done") { model.reset() }
                    .controlSize(.large)
            }

            Spacer()
        }
        .padding(Theme.gutter)
    }
}
