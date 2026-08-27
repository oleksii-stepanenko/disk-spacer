import Foundation

/// Recognises folders the Clean tab already knows how to deal with.
///
/// This is what joins the two halves of the app: while exploring, a folder that
/// turns out to be Xcode's build cache is labelled as such and points at the
/// method that clears it, instead of leaving the user to work out whether a
/// 2 GB directory full of hex-named folders matters.
public struct CleanupHint: Sendable, Hashable {
    /// The `methodID` of the Clean tab method that handles this.
    public let methodID: String
    public let title: String
    public let safety: Safety
    /// One line on what the folder is, for the row subtitle.
    public let summary: String
}

public enum CleanupHints {

    /// Exact directory paths owned by a cleanup method.
    private static var exactPaths: [String: CleanupHint] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Developer/Xcode/DerivedData": CleanupHint(
                methodID: "xcode.deriveddata", title: "Xcode Derived Data",
                safety: .regenerable,
                summary: "Xcode build files — safe to clear, they rebuild"),
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport": CleanupHint(
                methodID: "xcode.devicesupport", title: "iOS Device Support",
                safety: .reviewNeeded,
                summary: "Debug symbols per iOS version — re-copied from a device"),
            "\(home)/Library/Developer/CoreSimulator/Caches": CleanupHint(
                methodID: "xcode.simulatorcaches", title: "Simulator Caches",
                safety: .regenerable,
                summary: "Simulator caches — rebuilt on next boot"),
            "\(home)/Library/Developer/CoreSimulator/Devices": CleanupHint(
                methodID: "xcode.unavailablesims", title: "Simulators",
                safety: .reviewNeeded,
                summary: "Simulator devices — unusable ones can be removed"),
            "\(home)/.npm": CleanupHint(
                methodID: "npm.cache", title: "npm Cache",
                safety: .regenerable,
                summary: "Downloaded npm packages — re-downloaded on demand"),
            "\(home)/.cache": CleanupHint(
                methodID: "cache.dotcache", title: "~/.cache",
                safety: .regenerable,
                summary: "Shared tool cache — pip, Puppeteer, Hugging Face"),
            "\(home)/.gradle/caches": CleanupHint(
                methodID: "gradle.caches", title: "Gradle Caches",
                safety: .regenerable,
                summary: "Gradle dependencies — re-downloaded on next build"),
            "\(home)/.cargo/registry": CleanupHint(
                methodID: "cargo.registry", title: "Cargo Registry",
                safety: .regenerable,
                summary: "Rust crates — re-downloaded on next build"),
            "\(home)/go/pkg/mod": CleanupHint(
                methodID: "go.modcache", title: "Go Module Cache",
                safety: .regenerable,
                summary: "Go modules — cleared with go clean -modcache"),
            "\(home)/Library/Caches": CleanupHint(
                methodID: "user.caches", title: "Application Caches",
                safety: .regenerable,
                summary: "Per-app caches — apps rebuild them as you work"),
            "\(home)/Library/Logs": CleanupHint(
                methodID: "user.logs", title: "Application Logs",
                safety: .regenerable,
                summary: "App diagnostic logs — safe to clear"),
            "\(home)/.Trash": CleanupHint(
                methodID: "system.trash", title: "Trash",
                safety: .irreversible,
                summary: "Still using disk space until emptied"),
        ]
    }

    /// Folders recognised by name wherever they appear. These are not Clean tab
    /// methods — a project's dependencies are the developer's call, not
    /// something to sweep automatically — but they are worth pointing out,
    /// because they are usually the answer to "what is eating my disk".
    private static let byName: [String: (title: String, summary: String)] = [
        "node_modules": ("Node dependencies",
                         "Reinstall with npm/yarn/pnpm install if you need it back"),
        "DerivedData": ("Build output", "Rebuilt by Xcode on the next build"),
        ".build": ("Swift build output", "Rebuilt by swift build"),
        "target": ("Rust build output", "Rebuilt by cargo build"),
        "Pods": ("CocoaPods dependencies", "Reinstall with pod install"),
        ".venv": ("Python virtual environment", "Recreate from requirements"),
        "venv": ("Python virtual environment", "Recreate from requirements"),
        "__pycache__": ("Python bytecode cache", "Regenerated automatically"),
    ]

    /// A hint for a directory, if there is one worth showing.
    public static func hint(forPath path: String) -> CleanupHint? {
        if let exact = exactPaths[path] { return exact }
        return nil
    }

    /// A softer label for well-known folder names that no cleanup method owns.
    public static func note(forName name: String) -> (title: String, summary: String)? {
        byName[name]
    }
}
