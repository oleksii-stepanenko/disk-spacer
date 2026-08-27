import SwiftUI
import DiskSpacerCore

/// Visual vocabulary for the app. Kept in one place so the safety colours mean
/// exactly the same thing everywhere they appear.
enum Theme {

    static let cardCorner: CGFloat = 12
    static let gutter: CGFloat = 20

    static func color(for safety: Safety) -> Color {
        switch safety {
        case .regenerable:  return .green
        case .reviewNeeded: return .orange
        case .irreversible: return .red
        }
    }

    static func icon(for category: MethodCategory) -> String {
        switch category {
        case .developer:  return "hammer.fill"
        case .caches:     return "shippingbox.fill"
        case .containers: return "cube.transparent.fill"
        case .system:     return "gearshape.fill"
        case .personal:   return "person.crop.circle.fill"
        }
    }

    static func icon(for status: ScanStatus) -> String {
        switch status {
        case .ok:                  return "checkmark.circle.fill"
        case .empty:               return "checkmark.circle"
        case .needsFullDiskAccess: return "lock.fill"
        case .toolUnavailable:     return "minus.circle"
        case .failed:              return "exclamationmark.triangle.fill"
        }
    }
}

/// A rounded, subtly-bordered container used for every card in the app.
struct Card<Content: View>: View {
    var highlighted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(
                        highlighted ? Color.accentColor.opacity(0.6)
                                    : Color.primary.opacity(0.08),
                        lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

/// Small coloured pill, used for safety levels and category labels.
struct Badge: View {
    let text: String
    var color: Color = .secondary
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(filled ? 0.18 : 0.10))
            )
            .foregroundStyle(color)
            .overlay(
                Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5)
            )
    }
}

/// Tri-state checkbox: empty, partially selected, fully selected.
struct TriStateCheckbox: View {
    let state: SelectionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(state == .none ? Color.clear : Color.accentColor)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        state == .none ? Color.secondary.opacity(0.5) : Color.accentColor,
                        lineWidth: 1.2)
                switch state {
                case .none: EmptyView()
                case .some:
                    Rectangle().fill(.white).frame(width: 7, height: 1.8)
                        .clipShape(Capsule())
                case .all:
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

extension Safety {
    var shortLabel: String {
        switch self {
        case .regenerable:  return "Safe"
        case .reviewNeeded: return "Review"
        case .irreversible: return "Permanent"
        }
    }
}
