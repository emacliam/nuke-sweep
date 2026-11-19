cask "nuke-sweep" do
  version "0.9.6"
  sha256 "e354cfb06232eedace64398d19eeaa751c1c0265cd1252fa85a01758136e8ffa"

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
