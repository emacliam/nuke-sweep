cask "nuke-sweep" do
  version "0.9.5"
  sha256 "49dcd143c8be02a564a645fc8e43aeb947d7dc97fe68f127829730317a5b779b"

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
