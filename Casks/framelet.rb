cask "framelet" do
  version :latest
  sha256 :no_check

  url "https://github.com/mcxen/Framelet/releases/latest/download/Framelet-macOS-arm64.zip",
      verified: "github.com/mcxen/Framelet/"
  name "Framelet"
  desc "Native macOS lossless video trimming workflow"
  homepage "https://github.com/mcxen/Framelet"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Framelet.app"

  zap trash: [
    "~/Library/Preferences/dev.openspring.Framelet.plist",
    "~/Library/Saved Application State/dev.openspring.Framelet.savedState",
  ]
end
