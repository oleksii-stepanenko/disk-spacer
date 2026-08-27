import Foundation

/// Every cleanup method the app knows about.
///
/// `priority` resolves overlap: `~/Library/Caches/Homebrew` is claimed by the
/// Homebrew method (priority 10) and therefore excluded from the generic user
/// caches bucket (priority 0), so its bytes are never counted twice.
public enum Catalog {

    public static func allCleaners() -> [any Cleaner] {
        let home = NSHomeDirectory()
        var cleaners: [any Cleaner] = []

        // ── Developer ────────────────────────────────────────────────────────
        cleaners.append(DirectoryChildrenCleaner(
            id: "xcode.deriveddata",
            title: "Xcode Derived Data",
            category: .developer,
            safety: .regenerable,
            whatItIs: "Build intermediates, module caches and code indexes Xcode "
                    + "writes while compiling. One folder per project.",
            whatRegenerates: "Rebuilt automatically on your next build. The first "
                           + "build after cleaning is slower; nothing is lost.",
            manualCommand: "rm -rf ~/Library/Developer/Xcode/DerivedData/*",
            root: "\(home)/Library/Developer/Xcode/DerivedData",
            priority: 10))

        cleaners.append(DirectoryChildrenCleaner(
            id: "xcode.devicesupport",
            title: "iOS Device Support",
            category: .developer,
            safety: .reviewNeeded,
            whatItIs: "Debug symbols Xcode copies the first time you attach a "
                    + "device — one folder per iOS version you've ever connected.",
            whatRegenerates: "Re-copied from the device next time you attach one "
                           + "running that iOS version. That takes a few minutes. "
                           + "Keep the versions you still debug against.",
            manualCommand: "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/<version>",
            root: "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            priority: 10))

        cleaners.append(DirectoryChildrenCleaner(
            id: "xcode.simulatorcaches",
            title: "Simulator Caches",
            category: .developer,
            safety: .regenerable,
            whatItIs: "Cached simulator runtime data and dyld caches under "
                    + "CoreSimulator.",
            whatRegenerates: "Rebuilt when you next boot a simulator.",
            manualCommand: "rm -rf ~/Library/Developer/CoreSimulator/Caches/*",
            root: "\(home)/Library/Developer/CoreSimulator/Caches",
            priority: 10))

        cleaners.append(UnavailableSimulatorsCleaner())

        // ── Package manager caches ───────────────────────────────────────────
        cleaners.append(DirectoryChildrenCleaner(
            id: "npm.cache",
            title: "npm Cache",
            category: .caches,
            safety: .regenerable,
            whatItIs: "Tarballs npm keeps so repeat installs don't re-download.",
            whatRegenerates: "Re-downloaded on demand. Installs are slower once, "
                           + "then back to normal.",
            manualCommand: "npm cache clean --force",
            root: "\(home)/.npm",
            priority: 10))

        cleaners.append(SinglePathCleaner(
            id: "cache.dotcache",
            title: "~/.cache",
            category: .caches,
            safety: .regenerable,
            whatItIs: "Shared cache directory used by pip, uv, Puppeteer, "
                    + "Hugging Face and many CLI tools.",
            whatRegenerates: "Each tool re-downloads what it needs.",
            manualCommand: "rm -rf ~/.cache/*",
            path: "\(home)/.cache",
            priority: 10))

        cleaners.append(SinglePathCleaner(
            id: "gradle.caches",
            title: "Gradle Caches",
            category: .caches,
            safety: .regenerable,
            whatItIs: "Downloaded dependencies and build caches for Gradle/Android "
                    + "projects.",
            whatRegenerates: "Re-downloaded on the next Gradle build.",
            manualCommand: "rm -rf ~/.gradle/caches",
            path: "\(home)/.gradle/caches",
            priority: 10))

        cleaners.append(SinglePathCleaner(
            id: "cargo.registry",
            title: "Cargo Registry",
            category: .caches,
            safety: .regenerable,
            whatItIs: "Rust crate sources and downloaded .crate archives.",
            whatRegenerates: "Re-downloaded by the next cargo build.",
            manualCommand: "rm -rf ~/.cargo/registry/cache ~/.cargo/registry/src",
            path: "\(home)/.cargo/registry",
            priority: 10))

        // Go writes its module cache read-only (most directories are dr-xr-xr-x),
        // so a plain removeItem fails partway through. `go clean -modcache` is
        // the only reliable way to clear it.
        cleaners.append(SinglePathCleaner(
            id: "go.modcache",
            title: "Go Module Cache",
            category: .caches,
            safety: .regenerable,
            action: .command,
            whatItIs: "Downloaded Go modules. Often several GB, and written "
                    + "read-only, which is why plain rm fails on it.",
            whatRegenerates: "Re-downloaded by the next go build.",
            manualCommand: "go clean -modcache",
            path: "\(home)/go/pkg/mod",
            priority: 10,
            pruneTool: "go", pruneArgs: ["clean", "-modcache"]))

        // ── Generic user caches (lowest priority; the above win on overlap) ──
        cleaners.append(DirectoryChildrenCleaner(
            id: "user.caches",
            title: "Application Caches",
            category: .caches,
            safety: .regenerable,
            whatItIs: "Per-app caches in ~/Library/Caches. Browsers, Slack, "
                    + "Spotify and Xcode are usually the largest.",
            whatRegenerates: "Apps rebuild their caches as you use them. Quit an "
                           + "app before clearing its cache if you can.",
            manualCommand: "rm -rf ~/Library/Caches/*",
            root: "\(home)/Library/Caches",
            priority: 0))

        cleaners.append(DirectoryChildrenCleaner(
            id: "user.logs",
            title: "Application Logs",
            category: .system,
            safety: .regenerable,
            whatItIs: "Diagnostic logs written by apps into ~/Library/Logs.",
            whatRegenerates: "Regenerated as apps run. Only worth clearing if a "
                           + "misbehaving app has written gigabytes.",
            manualCommand: "rm -rf ~/Library/Logs/*",
            root: "\(home)/Library/Logs",
            priority: 10))

        // ── Command-reclaimed tools ─────────────────────────────────────────
        cleaners.append(DockerCleaner())
        cleaners.append(HomebrewCleaner())

        // ── Personal, review required ───────────────────────────────────────
        cleaners.append(TrashCleaner())
        cleaners.append(InstallerDownloadsCleaner())

        return cleaners
    }
}

// MARK: - Unavailable simulators

/// Simulator devices whose runtime is no longer installed. `simctl` reports
/// these as "unavailable"; they keep their full disk image around regardless.
struct UnavailableSimulatorsCleaner: Cleaner {
    let id = "xcode.unavailablesims"
    let title = "Unavailable Simulators"
    let category = MethodCategory.developer
    let safety = Safety.regenerable
    let action = RemovalAction.command
    let whatItIs = "Simulator devices left behind by Xcode versions or runtimes "
                 + "you've since removed. They can't be booted but still hold "
                 + "their full disk image."
    let whatRegenerates = "Nothing — these devices are already unusable. Xcode "
                        + "creates fresh simulators as needed."
    let manualCommand = "xcrun simctl delete unavailable"
    let priority = 20

    func scan() async -> MethodReport {
        guard Shell.which("xcrun") != nil else {
            return report(items: [], status: .toolUnavailable,
                          detail: "Xcode command line tools not found")
        }
        guard let out = Shell.run("xcrun", ["simctl", "list", "devices", "-j"]),
              out.ok,
              let data = out.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]]
        else {
            return report(items: [], status: .toolUnavailable,
                          detail: "Couldn't query simctl")
        }

        let deviceRoot = NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices"
        var items: [CleanupItem] = []

        for (runtime, devices) in byRuntime {
            for d in devices {
                let available = d["isAvailable"] as? Bool ?? true
                guard !available, let udid = d["udid"] as? String else { continue }
                let path = deviceRoot + "/" + udid
                let size = DiskSizer.measure(URL(fileURLWithPath: path)).bytes
                let name = d["name"] as? String ?? udid
                let shortRuntime = runtime
                    .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                items.append(CleanupItem(
                    path: path, size: size,
                    note: shortRuntime, label: name))
            }
        }

        return report(items: items, status: items.isEmpty ? .empty : .ok,
                      pruneTool: "xcrun", pruneArgs: ["simctl", "delete", "unavailable"])
    }
}

// MARK: - Docker

struct DockerCleaner: Cleaner {
    let id = "docker.prune"
    let title = "Docker Reclaimable"
    let category = MethodCategory.containers
    let safety = Safety.regenerable
    let action = RemovalAction.command
    let whatItIs = "Stopped containers, dangling images and the BuildKit build "
                 + "cache. The build cache alone is routinely tens of GB."
    let whatRegenerates = "Images are re-pulled and layers rebuilt on demand — "
                        + "slower the first time. Tagged images and named volumes "
                        + "are left alone."
    // Must match pruneArgs exactly, so the command shown is the command run.
    let manualCommand = "docker system prune -f"
    let priority = 20

    /// `docker system df` reports reclaimable space for categories that
    /// `system prune -f` will not touch. Volumes are the important one: prune
    /// without `--volumes` never removes them, so listing them would promise
    /// space the clean can't deliver.
    private static let prunedTypes: Set<String> = ["Containers", "Build Cache", "Images"]

    func scan() async -> MethodReport {
        guard Shell.which("docker") != nil else {
            return report(items: [], status: .toolUnavailable,
                          detail: "Docker isn't installed")
        }
        guard let df = Shell.run("docker", ["system", "df", "--format", "{{json .}}"], timeout: 20),
              df.ok, !df.stdout.isEmpty else {
            return report(items: [], status: .toolUnavailable,
                          detail: "Docker isn't running — start Docker Desktop to scan")
        }

        var items: [CleanupItem] = []
        for line in df.stdout.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = o["Type"] as? String,
                  let reclaimable = o["Reclaimable"] as? String else { continue }
            guard Self.prunedTypes.contains(type) else { continue }
            let bytes = parseDockerSize(reclaimable)
            guard bytes > 0 else { continue }
            items.append(CleanupItem(
                path: "docker://\(type)", size: bytes,
                note: (o["Size"] as? String).map { "of \($0) total" },
                label: type))
        }

        // The Images figure includes tagged-but-unused images, which prune -f
        // leaves in place, so the total is an upper bound rather than a promise.
        return report(items: items, status: items.isEmpty ? .empty : .ok,
                      upperBound: true,
                      pruneTool: "docker",
                      pruneArgs: ["system", "prune", "-f"])
    }

    /// Parses "12.3GB (45%)" or "1.1MB" into bytes.
    private func parseDockerSize(_ s: String) -> Int64 {
        let head = s.split(separator: " ").first.map(String.init) ?? s
        let units: [(String, Double)] = [
            ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1),
        ]
        for (suffix, mult) in units where head.hasSuffix(suffix) {
            let n = head.dropLast(suffix.count)
            if let v = Double(n) { return Int64(v * mult) }
        }
        return 0
    }
}

// MARK: - Homebrew

struct HomebrewCleaner: Cleaner {
    let id = "brew.cleanup"
    let title = "Homebrew Cleanup"
    let category = MethodCategory.caches
    let safety = Safety.regenerable
    let action = RemovalAction.command
    let whatItIs = "Downloaded bottles and cask archives Homebrew keeps after "
                 + "installing, plus superseded versions of installed formulae."
    let whatRegenerates = "Re-downloaded if you reinstall or downgrade a package. "
                        + "Nothing currently installed stops working."
    // Scan and execute must use identical flags: --prune=all would discard
    // more than `brew cleanup --dry-run` listed, removing what the confirm
    // sheet never showed.
    let manualCommand = "brew cleanup"
    let priority = 20

    func scan() async -> MethodReport {
        guard Shell.which("brew") != nil else {
            return report(items: [], status: .toolUnavailable,
                          detail: "Homebrew isn't installed")
        }
        // --dry-run reports exactly what a real cleanup would remove.
        guard let out = Shell.run("brew", ["cleanup", "--dry-run"], timeout: 90) else {
            return report(items: [], status: .toolUnavailable, detail: "brew failed to run")
        }

        var items: [CleanupItem] = []
        for line in out.stdout.split(separator: "\n") {
            let s = String(line)
            guard s.hasPrefix("Would remove:") else { continue }
            // "Would remove: /path/to/thing (1,067 files, 9.8MB)"
            let rest = s.dropFirst("Would remove:".count).trimmingCharacters(in: .whitespaces)
            guard let open = rest.lastIndex(of: "("), rest.hasSuffix(")") else { continue }
            let path = String(rest[rest.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            let sizeText = String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])
            let bytes = parseBrewSize(sizeText)
            guard bytes > 0 else { continue }
            items.append(CleanupItem(path: path, size: bytes,
                                     label: (path as NSString).lastPathComponent))
        }

        return report(items: items, status: items.isEmpty ? .empty : .ok,
                      pruneTool: "brew", pruneArgs: ["cleanup"])
    }

    /// Parses the trailing "(1,067 files, 9.8MB)" or "(13.8KB)" fragment.
    private func parseBrewSize(_ s: String) -> Int64 {
        let token = s.split(separator: ",").last.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? s
        let units: [(String, Double)] = [
            ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("B", 1),
        ]
        for (suffix, mult) in units where token.hasSuffix(suffix) {
            if let v = Double(token.dropLast(suffix.count)) { return Int64(v * mult) }
        }
        return 0
    }
}

// MARK: - Trash

struct TrashCleaner: Cleaner {
    let id = "system.trash"
    let title = "Trash"
    let category = MethodCategory.personal
    let safety = Safety.irreversible
    let action = RemovalAction.delete
    let whatItIs = "Everything sitting in ~/.Trash. Files here still occupy disk "
                 + "space until the Trash is emptied."
    let whatRegenerates = "Nothing. Emptying the Trash is permanent — check the "
                        + "list before you confirm."
    let manualCommand = "rm -rf ~/.Trash/*"
    let priority = 20

    func scan() async -> MethodReport {
        let trash = URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: []) else {
            return report(items: [], status: .needsFullDiskAccess,
                          detail: "Reading the Trash needs Full Disk Access")
        }
        var items: [CleanupItem] = []
        for child in children where SafetyGuard.isRemovable(child.path) {
            if Task.isCancelled { break }
            let m = DiskSizer.measure(child)
            items.append(CleanupItem(path: child.path, size: m.bytes,
                                     note: DiskSizer.ageNote(child)))
        }
        return report(items: items, status: items.isEmpty ? .empty : .ok)
    }
}

// MARK: - Installers in Downloads

struct InstallerDownloadsCleaner: Cleaner {
    let id = "downloads.installers"
    let title = "Old Installers in Downloads"
    let category = MethodCategory.personal
    let safety = Safety.reviewNeeded
    let action = RemovalAction.trash   // recoverable: these are personal files
    let whatItIs = "Disk images and installer packages in ~/Downloads older than "
                 + "30 days. The app is already installed; the installer isn't needed."
    let whatRegenerates = "Nothing — but these are re-downloadable from wherever "
                        + "you got them. Moved to the Trash, not deleted outright."
    let manualCommand = "find ~/Downloads -maxdepth 1 \\( -name '*.dmg' -o -name '*.pkg' \\) -mtime +30"
    let priority = 20

    private static let extensions: Set<String> = ["dmg", "pkg", "iso", "xip"]

    func scan() async -> MethodReport {
        let downloads = URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]) else {
            return report(items: [], status: .needsFullDiskAccess,
                          detail: "Reading Downloads needs Full Disk Access")
        }

        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        var items: [CleanupItem] = []
        for child in children {
            guard Self.extensions.contains(child.pathExtension.lowercased()) else { continue }
            guard let mod = DiskSizer.modifiedDate(child), mod < cutoff else { continue }
            guard SafetyGuard.isRemovable(child.path) else { continue }
            let m = DiskSizer.measure(child)
            items.append(CleanupItem(path: child.path, size: m.bytes,
                                     note: DiskSizer.ageNote(child)))
        }
        return report(items: items, status: items.isEmpty ? .empty : .ok)
    }
}
