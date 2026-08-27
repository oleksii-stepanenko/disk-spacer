<div align="center">

<img src="docs/assets/logo.png" width="120" alt="Disk Spacer logo" />

# Disk Spacer

**See what is using your disk. Clean it safely.**

A small, native macOS app that finds space you can get back — and shows you
exactly what it will delete **before** it deletes anything.

[![Download](https://img.shields.io/badge/Download-.dmg-5B6BF5?style=for-the-badge&logo=apple&logoColor=white)](../../releases/latest)
&nbsp;
[![Website](https://img.shields.io/badge/Website-disk--spacer-5B6BF5?style=for-the-badge&logo=githubpages&logoColor=white)](https://oleksii-stepanenko.github.io/disk-spacer/)
&nbsp;
![Platform](https://img.shields.io/badge/macOS-14%2B-111?style=for-the-badge&logo=apple)
[![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)

<img src="docs/assets/hero.png" width="760" alt="Disk Spacer" />

</div>

---

## 🧹 What it does

Your Mac fills up with files you never asked for: old build folders, caches,
downloaded packages, dead simulators, Docker layers. Most of them are safe to
delete. Some are not. It is hard to tell which is which.

Disk Spacer looks through all of it and gives you a clear list.

**For every item it finds, it tells you four things:**

| | |
|---|---|
| 💾 **How much space** | The real size you get back |
| 📋 **Exactly what** | Every single file and folder, by name |
| ♻️ **What happens next** | Does it come back on its own? Is it gone forever? |
| ⌨️ **How to do it yourself** | The Terminal command, ready to copy |

Then you choose. Tick what you want, untick what you don't, and press one
button. **Nothing is removed until you say so.**

<!-- SCREENSHOTS: capture with ⌘⇧4 then Space, click the window, and save as:
       docs/assets/screenshot-review.png   — the results list, one card expanded
       docs/assets/screenshot-confirm.png  — the confirmation sheet
       docs/assets/screenshot-result.png   — the "Reclaimed X" screen
     Then delete this comment and uncomment the images below.

<div align="center">
<img src="docs/assets/screenshot-review.png" width="760" alt="Reviewing what will be removed" />
<br /><br />
<img src="docs/assets/screenshot-confirm.png" width="620" alt="The confirmation step" />
</div>
-->

---

## 🚀 Install

### With Homebrew (easiest)

```sh
brew install --cask oleksii-stepanenko/tap/disk-spacer
```

### Or download it

**[Download the latest `.dmg`](../../releases/latest)**, open it, and drag
**Disk Spacer** into your **Applications** folder.

---

## 🔓 First launch

Disk Spacer is **not notarized** by Apple (that needs a paid Apple Developer
account), so macOS blocks it the first time. This is normal. To open it:

1. Double-click **Disk Spacer**. macOS will refuse.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to **Security** and click **Open Anyway**.
4. Confirm with Touch ID or your password.

You only need to do this once per update.

---

## 🔑 Full Disk Access (recommended)

Some folders on macOS are private. Apps cannot look inside them unless you
allow it. Your Trash and other apps' data are two examples.

Without permission, Disk Spacer **cannot see those folders**. It will say so
clearly — it will never pretend a folder is empty when it simply could not
look inside.

To give permission:

**System Settings → Privacy & Security → Full Disk Access →** turn on
**Disk Spacer**.

The app shows a banner with a button that takes you straight there.

> **Note:** because the app is signed with a self-signed certificate, this
> permission may reset after an update. If protected folders stop appearing,
> remove Disk Spacer from the list and add it again.

---

## 📦 What it cleans

| What | What it is | Safe to delete? |
|---|---|---|
| **Xcode Derived Data** | Build files Xcode makes while compiling | ✅ Yes — Xcode rebuilds them |
| **iOS Device Support** | Debug files, one per iOS version | ⚠️ Check first — re-copying takes minutes |
| **Simulator Caches** | Cached simulator data | ✅ Yes |
| **Dead Simulators** | Simulators you can no longer start | ✅ Yes — they are already broken |
| **npm Cache** | Downloaded npm packages | ✅ Yes — npm downloads again |
| **`~/.cache`** | Used by pip, Puppeteer, Hugging Face and others | ✅ Yes |
| **Gradle / Cargo / Go** | Downloaded code libraries | ✅ Yes |
| **App Caches** | Caches from every app you use | ✅ Yes — apps rebuild them |
| **App Logs** | Log files apps write | ✅ Yes |
| **Docker** | Stopped containers, unused images, build cache | ✅ Yes |
| **Homebrew** | Old downloads and old versions | ✅ Yes |
| **Trash** | Files waiting in your Trash | ❌ **Gone forever** |
| **Old Installers** | `.dmg` and `.pkg` files over 30 days old | ⚠️ Check first — moved to Trash |

Only the **✅ safe** ones are ticked for you. Anything risky starts unticked,
so you have to choose it on purpose.

---

## 🛡 How it keeps you safe

**It only deletes from a short, fixed list of folders.**
Every delete is checked against an allow-list first. Your Documents, Desktop,
Photos and Home folder are blocked outright. If a path is not on the list,
the app refuses. The check runs again right before deleting, not just when
scanning.

**It never asks for your password.**
Anything that would need admin rights is shown to you as a command to run
yourself. The app does not run anything as administrator, ever.

**The sizes are real.**
It measures the space you actually get back, not the size shown in Finder. It
does not follow shortcuts, and it counts shared files only once — so a number
is never inflated to look impressive. Where a figure can only be a maximum,
the app says so.

**No number is counted twice.**
When two cleaners find the same folder, only one of them keeps it. The total
you see is honest, not flattering.

**Delete or Trash is chosen on purpose.**
Caches are deleted for real, because moving them to the Trash would not free
any space. Your personal files, like old installers, go to the Trash instead,
so you can get them back.

---

## 🔨 Build it yourself

You need Xcode 16 or newer.

```sh
git clone https://github.com/oleksii-stepanenko/disk-spacer.git
cd disk-spacer

./scripts/make-app.sh --release            # builds build/Disk Spacer.app
./scripts/make-app.sh --release --install  # …and copies it to /Applications

open "build/Disk Spacer.app"
```

Run the tests:

```sh
swift test
```

The tests cover the parts that must not go wrong: the delete allow-list, the
double-counting rules, and the size measuring.

To redraw the icon and banner after changing them:

```sh
# icon → Resources/AppIcon.icns (used by the app)
swift scripts/make-icon.swift Resources
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

# logo + banner → docs/assets (used by this page and the website)
mv Resources/logo.png docs/assets/logo.png
sips -Z 512 docs/assets/logo.png
swift scripts/make-banner.swift docs/assets
sips -Z 1600 docs/assets/hero.png
```

---

## 📁 What is inside

```
disk-spacer/
├── Sources/
│   ├── DiskSpacerCore/    the engine — finds, measures, and removes
│   └── DiskSpacerApp/     the window you see
├── Tests/                 tests for the risky parts
├── scripts/
│   ├── make-app.sh        builds the .app
│   ├── make-icon.swift    draws the icon
│   └── make-banner.swift  draws the banner
├── Resources/AppIcon.icns the app icon
├── docs/                  the website
└── packaging/homebrew/    the Homebrew cask
```

---

<div align="center">

**[Website](https://oleksii-stepanenko.github.io/disk-spacer/)** ·
**[Download](../../releases/latest)** ·
**[Report a problem](../../issues)**

Made for macOS. [MIT licensed](LICENSE).

</div>
