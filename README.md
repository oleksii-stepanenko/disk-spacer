# Disk Spacer

A native macOS app for reclaiming disk space — plus the CLI and shell scripts
behind it.

The rule the whole thing is built around: **analyse first, explain, then let
you decide.** Every method tells you what it found, how much it will free,
exactly which files go, what regenerates afterwards, and the Terminal command
to do the same thing by hand. Nothing is removed until you confirm.

## What it looks for

| Method | What it is | Safety |
|---|---|---|
| Xcode Derived Data | Build intermediates and indexes | Safe |
| iOS Device Support | Debug symbols per iOS version | Review |
| Simulator Caches | CoreSimulator runtime caches | Safe |
| Unavailable Simulators | Devices whose runtime is gone | Safe |
| npm Cache | `~/.npm` package tarballs | Safe |
| `~/.cache` | pip, uv, Puppeteer, Hugging Face | Safe |
| Gradle / Cargo / Go caches | Downloaded dependencies | Safe |
| Application Caches | `~/Library/Caches` per-app | Safe |
| Application Logs | `~/Library/Logs` | Safe |
| Docker Reclaimable | Stopped containers, dangling images, build cache | Safe |
| Homebrew Cleanup | Old bottles and cask downloads | Safe |
| Trash | `~/.Trash` | **Permanent** |
| Old Installers | `.dmg`/`.pkg`/`.iso` in Downloads over 30d old | Review |

Only **Safe** methods are preselected. Review-first and permanent ones start
unticked — you opt in deliberately.

## Build and run

```bash
./Scripts/make-app.sh --release            # build Disk Spacer.app into ./build
./Scripts/make-app.sh --release --install  # …and copy it to /Applications
open "build/Disk Spacer.app"
```

Requires Xcode / Swift 6 toolchain. No dependencies.

## CLI

The same engine, driven from the terminal:

```bash
swift build -c release
./.build/release/diskspacer scan            # analyse and report
./.build/release/diskspacer scan --json     # machine-readable
./.build/release/diskspacer scan --all      # include methods that found nothing
./.build/release/diskspacer methods         # list method ids

./.build/release/diskspacer clean --method xcode.deriveddata          # dry run
./.build/release/diskspacer clean --method xcode.deriveddata --yes    # do it
```

`clean` is a dry run unless you pass `--yes`.

## Full Disk Access

Some locations (`~/.Trash`, other apps' containers, Mail, Safari) are readable
only with Full Disk Access. macOS provides **no API to request it** — it can
only be granted by hand.

The app detects the situation and shows a banner with a button to the right
settings pane. A path it cannot read is always reported as *"needs Full Disk
Access"*, never as `0 B` — a cleaner that silently reports nothing where it
simply could not look is worse than one that admits the gap.

Grant it under *System Settings → Privacy & Security → Full Disk Access*.
Because the app is ad-hoc signed, a rebuild can invalidate the grant; if
protected paths stop appearing, remove and re-add the entry.

## Safety design

- **Every deletion passes one choke point.** `SafetyGuard.validate` refuses any
  path that isn't a strict descendant of an explicit allowlist, rejects `$HOME`
  and its top-level folders outright, and resolves symlinks in the parent chain
  so a symlinked ancestor can't be used to escape. It fails closed, and it is
  re-checked immediately before removal, not merely at scan time.
- **No admin, ever.** Anything needing `sudo` is shown as a manual command
  only. The app never asks for your password and never runs a privileged helper.
- **Sizes are what you actually get back.** Allocated size, not logical size.
  Symlinks aren't followed. Hard-linked files are counted once, so a pnpm store
  or Homebrew Cellar isn't wildly overstated. Where a figure is still an upper
  bound the UI says so.
- **No double counting.** When two methods claim overlapping paths the more
  specific one wins and the generic bucket surrenders those bytes, so the
  headline total is honest rather than flattering.
- **Delete vs. Trash is deliberate.** Regenerable caches are deleted outright,
  because moving them to the Trash wouldn't free any space. Personal files
  (old installers) go to the Trash instead, where you can get them back.

## Layout

```
Disk_Spacer/
├── Package.swift
├── Sources/
│   ├── DiskSpacerCore/       engine — scanning, sizing, safety, removal
│   │   ├── Model.swift        types, safety levels, formatting
│   │   ├── SafetyGuard.swift  the deletion allowlist
│   │   ├── DiskSizer.swift    allocated-size walking, hard-link dedupe
│   │   ├── Cleaner.swift      protocol + generic directory cleaners
│   │   ├── Catalog.swift      the methods themselves
│   │   ├── ScanEngine.swift   concurrent scan + overlap dedupe
│   │   ├── Remover.swift      removal + Full Disk Access detection
│   │   └── Shell.swift        locating and running docker/brew/xcrun
│   ├── diskspacer-cli/       terminal front end
│   └── DiskSpacerApp/        SwiftUI interface
├── Tests/                    guard, dedupe and sizing tests
├── Scripts/
│   ├── make-app.sh           builds the .app bundle
│   └── *.sh                  standalone shell scripts (see below)
└── docs/cleanup-methods.md   what uses space on macOS and why
```

## The shell scripts

`scripts/*.sh` predate the app and remain as the dependency-free manual path —
useful over SSH, in a CI box, or when you'd rather read a command than trust a
GUI. They're dry-run by default and take `--yes` to act:

```bash
./scripts/analyze-disk.sh          # coarse usage report
./scripts/find-large-files.sh      # individual files over a threshold
./scripts/find-node-modules.sh     # locate and size node_modules dirs
./scripts/clean-all.sh             # dry run everything
./scripts/clean-all.sh --yes       # actually clean
```

They're written for macOS's stock bash 3.2, so no `mapfile`/`readarray`.

## Tests

```bash
swift test
```

Covers the safety allowlist (traversal escapes, similarly-named siblings,
protected locations), the overlap dedupe, and sizing behaviour (hard links
counted once, symlinks not followed).
