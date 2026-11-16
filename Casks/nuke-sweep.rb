cask "nuke-sweep" do
  version "0.9.3"
  sha256 "b404ee1e901c66225324a26a90dc380d980211074ce405439a27fc7e59be9355"

  url "https://sweep.zyncraft.com/downloads/Nuke-Sweep-#{version}.dmg"
  name "Nuke Sweep"
  desc "Storage inspection and reviewed cleanup for Mac"
  homepage "https://sweep.zyncraft.com/"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Nuke Sweep.app"
  binary "#{appdir}/Nuke Sweep.app/Contents/MacOS/Nuke", target: "nuke"
end
