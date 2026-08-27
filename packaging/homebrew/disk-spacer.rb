cask "disk-spacer" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/oleksii-stepanenko/disk-spacer/releases/download/v#{version}/DiskSpacer.dmg"
  name "Disk Spacer"
  desc "See what is using your disk, and clean it safely"
  homepage "https://github.com/oleksii-stepanenko/disk-spacer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Disk Spacer.app"

  zap trash: [
    "~/Library/Preferences/io.stepanenko.DiskSpacer.plist",
    "~/Library/Saved Application State/io.stepanenko.DiskSpacer.savedState",
  ]

  caveats <<~EOS
    Disk Spacer is signed with a self-signed certificate (it is not notarized by
    Apple), so the first time you launch it macOS says it "cannot be opened
    because Apple cannot check it for malicious software". To allow it:

      1. Open  System Settings -> Privacy & Security
      2. Scroll to Security and click "Open Anyway" next to Disk Spacer
      3. Confirm with Touch ID or your password

    This step reappears after each update.

    For a complete picture of your disk, give Disk Spacer Full Disk Access:
    System Settings -> Privacy & Security -> Full Disk Access. Without it the
    app cannot read your Trash or other apps' data, and it will tell you so
    rather than reporting those folders as empty.
  EOS
end
