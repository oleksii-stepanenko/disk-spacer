import Foundation

/// The single gate every deletion passes through.
///
/// The app computes paths from globs, `du` walks and tool output, so one bad
/// join between a computed path and `removeItem` would be a disaster. Rather
/// than trusting each call site, all removal funnels through `validate` here,
/// which fails closed: a path is refused unless it is a *strict descendant* of
/// an explicitly allowlisted root.
public enum SafetyGuard {

    public struct Violation: Error, CustomStringConvertible {
        public let path: String
        public let reason: String
        public var description: String { "refused to remove \(path): \(reason)" }
    }

    /// Roots under which removal is permitted. Deliberately specific — adding
    /// a broad root here (e.g. `~/Library`) would defeat the guard.
    public static var allowedRoots: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/watchOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/tvOS DeviceSupport",
            "\(home)/Library/Developer/CoreSimulator/Caches",
            "\(home)/Library/Developer/CoreSimulator/Devices",
            "\(home)/Library/Application Support/CrashReporter",
            "\(home)/.npm",
            "\(home)/.cache",
            "\(home)/.yarn/cache",
            "\(home)/.gradle/caches",
            "\(home)/.cargo/registry",
            "\(home)/.rustup/toolchains",
            "\(home)/go/pkg/mod",
            "\(home)/.Trash",
            "\(home)/Downloads",
        ]
    }

    /// Paths that must never be removed even if they land inside an allowed
    /// root by some accident of path construction.
    private static var neverRemove: Set<String> {
        let home = NSHomeDirectory()
        return [
            "/", home,
            "\(home)/Library", "\(home)/Documents", "\(home)/Desktop",
            "\(home)/Pictures", "\(home)/Movies", "\(home)/Music",
            "\(home)/Downloads", "\(home)/Applications", "\(home)/Public",
            "\(home)/.ssh", "\(home)/.gnupg", "\(home)/.config",
        ]
    }

    /// Resolves symlinks in the *parent* chain only, so a symlinked ancestor
    /// can't be used to escape an allowed root, while a symlink that is itself
    /// the removal target still resolves to itself (we delete the link, not
    /// whatever it points at).
    public static func canonicalize(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.appendingPathComponent(url.lastPathComponent).path
    }

    /// Throws unless `path` is safe to remove. Call this immediately before
    /// any destructive filesystem operation — never trust an earlier check.
    public static func validate(_ path: String) throws {
        let resolved = canonicalize(path)

        guard resolved.hasPrefix("/") else {
            throw Violation(path: path, reason: "not an absolute path")
        }
        guard !resolved.contains("/../") && !resolved.hasSuffix("/..") else {
            throw Violation(path: path, reason: "contains a parent traversal")
        }
        guard !neverRemove.contains(resolved) else {
            throw Violation(path: path, reason: "protected location")
        }

        // Must be a *strict* descendant of an allowed root: equal-to-root is
        // refused so we empty a cache directory rather than deleting it.
        let isDescendant = allowedRoots.contains { root in
            let canonicalRoot = URL(fileURLWithPath: root)
                .standardizedFileURL.resolvingSymlinksInPath().path
            return resolved.hasPrefix(canonicalRoot + "/")
                && resolved.count > canonicalRoot.count + 1
        }
        guard isDescendant else {
            throw Violation(path: path, reason: "outside every allowlisted root")
        }
    }

    /// Non-throwing form, for filtering candidate lists before display.
    public static func isRemovable(_ path: String) -> Bool {
        (try? validate(path)) != nil
    }
}
