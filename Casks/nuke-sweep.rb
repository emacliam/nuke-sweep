cask "nuke-sweep" do
  version "0.9.7"
  sha256 "4513fb4959f9ff485bd82ee8196c2a17464ce02fd09dd601b0f4b0fd41dbb41d"

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
