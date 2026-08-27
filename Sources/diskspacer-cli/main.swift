import Foundation
import DiskSpacerCore

// Terminal front end for the same engine the app uses. Exists so the scan and
// clean logic can be verified without launching a UI.

func usage() -> Never {
    print("""
    diskspacer — analyse and reclaim disk space on macOS

    USAGE
      diskspacer scan [--json] [--all]
      diskspacer clean --method <id> [--dry-run] [--yes]
      diskspacer methods

    scan     Analyse every method and report what could be reclaimed.
             --json  machine-readable output
             --all   include methods with nothing to clean
    clean    Reclaim one method. Dry run unless --yes is given.
    methods  List method ids.
    """)
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
let flags = Set(args.filter { $0.hasPrefix("--") })

func value(for flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

@Sendable func bar(_ fraction: Double, width: Int = 24) -> String {
    let filled = max(0, min(width, Int(fraction * Double(width))))
    return String(repeating: "█", count: filled)
         + String(repeating: "░", count: width - filled)
}

switch command {

case "methods":
    for c in Catalog.allCleaners() {
        print("\(c.id.padding(toLength: 28, withPad: " ", startingAt: 0)) \(c.title)")
    }

case "scan":
    let json = flags.contains("--json")
    if !json { FileHandle.standardError.write("Scanning…\n".data(using: .utf8)!) }

    let results = await ScanEngine.scan { p in
        guard !json else { return }
        FileHandle.standardError.write(
            "\r  \(bar(p.fraction)) \(p.completed)/\(p.total) \(p.currentTitle)\u{1B}[K"
                .data(using: .utf8)!)
    }
    if !json { FileHandle.standardError.write("\r\u{1B}[K".data(using: .utf8)!) }

    if json {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try enc.encode(results), encoding: .utf8)!)
        break
    }

    print("")
    for r in results.reports {
        let shown = flags.contains("--all") || r.isActionable
        guard shown else { continue }

        let size = r.isActionable
            ? (r.sizeIsUpperBound ? "≤ " : "") + formatBytes(r.totalSize)
            : "—"
        print("\(r.title)")
        print("  \(size.padding(toLength: 12, withPad: " ", startingAt: 0))"
            + "\(r.safety.label)   [\(r.category.rawValue)]  \(r.methodID)")

        switch r.status {
        case .needsFullDiskAccess:
            print("  ⚠︎ Needs Full Disk Access — figure is incomplete")
        case .toolUnavailable:
            print("  · \(r.detail ?? "tool unavailable")")
        case .empty:
            print("  · nothing to clean")
        case .failed:
            print("  ✗ \(r.detail ?? "failed")")
        case .ok:
            for item in r.items.prefix(5) {
                let n = item.note.map { " (\($0))" } ?? ""
                print("      \(formatBytes(item.size).padding(toLength: 10, withPad: " ", startingAt: 0))"
                    + "\(item.displayName)\(n)")
            }
            if r.items.count > 5 { print("      … \(r.items.count - 5) more") }
            print("      manually: \(r.manualCommand)")
        }
        print("")
    }

    print(String(repeating: "─", count: 60))
    print("Reclaimable: \(formatBytes(results.reclaimable))")
    if let avail = results.availableBefore {
        print("Free now:    \(formatBytes(avail))")
    }
    if results.needsFullDiskAccess {
        print("\n⚠︎  Some locations couldn't be read. Grant Full Disk Access to")
        print("   your terminal (or Disk Spacer.app) for a complete picture:")
        print("   System Settings → Privacy & Security → Full Disk Access")
    }

case "clean":
    guard let methodID = value(for: "--method") else {
        print("error: --method <id> is required (see: diskspacer methods)")
        exit(1)
    }
    let live = flags.contains("--yes")

    let cleaners = Catalog.allCleaners().filter { $0.id == methodID }
    guard !cleaners.isEmpty else {
        print("error: unknown method '\(methodID)' (see: diskspacer methods)")
        exit(1)
    }

    let results = await ScanEngine.scan(cleaners: cleaners)
    guard let report = results.reports.first else { exit(1) }

    guard report.isActionable else {
        print("\(report.title): nothing to clean (\(report.status.rawValue))")
        exit(0)
    }

    print("\(report.title) — \(formatBytes(report.totalSize)) across \(report.items.count) item(s)")
    print("\(report.action.verb):")
    for item in report.items {
        print("  \(formatBytes(item.size).padding(toLength: 10, withPad: " ", startingAt: 0))\(item.displayName)")
    }
    print("\nManual equivalent: \(report.manualCommand)")

    guard live else {
        print("\nDry run — nothing removed. Re-run with --yes to clean.")
        exit(0)
    }

    let selection = [report.methodID: Set(report.items.map(\.path))]
    let summary = await Remover.clean(reports: [report], selection: selection) { p in
        FileHandle.standardError.write(
            "\r  \(bar(p.fraction)) \(p.completed)/\(p.total)\u{1B}[K".data(using: .utf8)!)
    }
    FileHandle.standardError.write("\r\u{1B}[K".data(using: .utf8)!)

    print("Freed \(formatBytes(summary.freedBytes)) from \(summary.succeededCount) item(s).")
    for f in summary.failures {
        print("  ✗ \((f.path as NSString).lastPathComponent): \(f.error ?? "failed")")
    }

default:
    usage()
}
