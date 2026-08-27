# macOS disk cleanup: what's using space, and what to do about it

A reference for where space actually goes on a Mac, roughly ordered by how
often it's the culprit. For each item: what it is, whether it's safe to
delete, and how to reclaim it (manually or via a script in `scripts/`).

## 1. Developer caches & build artifacts

These are almost always safe to delete — they regenerate on next build/install.

| Location | What it is | Reclaim with |
|---|---|---|
| `~/Library/Developer/Xcode/DerivedData` | Build intermediates, indexes | `scripts/clean-xcode.sh` |
| `~/Library/Developer/Xcode/Archives` | Old app archives (only needed if you re-export/upload) | review manually, then `clean-xcode.sh` |
| `~/Library/Developer/CoreSimulator/Devices` | Simulator devices + their disk images | `xcrun simctl delete unavailable`, or `clean-xcode.sh` |
| `~/Library/Developer/Xcode/iOS DeviceSupport` | Per-iOS-version debug symbols, one folder per device/OS combo you've connected | `clean-xcode.sh` (keeps latest N) |
| `node_modules/` anywhere on disk | JS dependency trees, fully reproducible via `npm/yarn/pnpm install` | `scripts/find-node-modules.sh`, then delete stale ones by hand |
| `~/.npm`, `~/.cache/yarn`, `~/.pnpm-store` | Package manager caches | `scripts/clean-caches.sh` |
| `~/Library/Caches/pip`, `~/.cache/pip` | Python wheel cache | `scripts/clean-caches.sh` |
| `~/.cargo/registry` | Rust crate cache/sources | `cargo cache -a` (needs `cargo-cache`) or manual |
| `~/go/pkg/mod/cache` | Go module download cache | `go clean -modcache` |
| Docker images/containers/volumes/build cache | Can be tens of GB, especially build cache | `scripts/clean-docker.sh` |
| `~/Library/Caches/Homebrew`, old bottle downloads | Homebrew's own cache | `scripts/clean-homebrew.sh` |
| `.git` objects in old/unused repo clones | Full history, even for repos you no longer touch | `git gc --aggressive` per-repo, or just delete the clone if it's a duplicate |

## 2. System & app caches

Generally safe; apps rebuild what they need, but a few apps (rare) misbehave
if wiped while running — quit the app first if unsure.

- `~/Library/Caches/*` — per-app caches. `scripts/clean-caches.sh` clears
  this broadly; safe in the vast majority of cases.
- `~/Library/Logs/*`, `/private/var/log/*` — log files, safe to delete, low
  value target (rarely large).
- `/private/var/folders/**/T` — system temp files, macOS clears these
  automatically but a manual sweep can help.
- `~/Library/Application Support/*/Cache*` — some apps (Slack, Chrome, Spotify)
  keep multi-GB caches here in addition to `~/Library/Caches`.
- Browser caches/profiles (Chrome, Safari, Firefox) — safe to clear from the
  browser's own settings; clearing profile data (not just cache) loses saved
  logins, so use the browser's UI rather than deleting folders directly.

## 3. Trash & Time Machine

- `~/.Trash` — not actually freed until emptied. `scripts/empty-trash.sh`.
  **Irreversible** — confirms before running.
- Local Time Machine snapshots (`tmutil listlocalsnapshots /`) can silently
  hold several GB and are counted as "purgeable" — macOS reclaims them
  automatically under disk pressure, but you can force it:
  `sudo tmutil thinlocalsnapshots / <bytes-needed> 4`.

## 4. Large personal files (manual review required — not automated)

These are *not* covered by the cleanup scripts because deleting the wrong
one is costly. Use `scripts/find-large-files.sh` to locate candidates, then
review by hand:

- Old `.dmg` / `.pkg` installers in `~/Downloads`
- Duplicate photo/video exports, old `.ipa`/`.app` builds
- iOS backups: `~/Library/Application Support/MobileSync/Backup` — only
  delete if you don't need the backup; check date/device first.
- Mail attachments cache: `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`
- Old Time Machine *local* backups vs. your actual external/network backup —
  don't delete your only backup.

## 5. Finding the big stuff generically

Two complementary approaches, both scripted:

- `scripts/analyze-disk.sh` — coarse view: biggest top-level directories
  under `/`, `$HOME`, and `~/Library` via `du`.
- `scripts/find-large-files.sh` — fine view: every individual file above a
  size threshold (default 500MB), sorted descending.

For an interactive visual explorer, `ncdu` (`brew install ncdu`) or the
built-in **Storage Management** panel (`Apple menu → About This Mac →
Storage → Manage…`) are good complements to these scripts.

## Recommended order of operations

1. `analyze-disk.sh` — get the lay of the land.
2. `clean-all.sh` (dry run) — see what the automated scripts would reclaim.
3. `clean-all.sh --yes` — reclaim the safe/automatic stuff.
4. `find-large-files.sh` + `find-node-modules.sh` — hunt remaining large
   items manually.
5. Re-run `analyze-disk.sh` to confirm space was reclaimed.
