cask "nuke-sweep" do
  version "0.9.8"
  sha256 "9de19d115aa1cba78f7ccf4cac99c44c4bdf21c7fac2a203514696953cd9fbad"

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
