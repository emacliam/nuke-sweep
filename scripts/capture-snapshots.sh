#!/bin/zsh
set -eu
cd "${0:A:h:h}"

APP="$PWD/dist/Nuke Sweep.app"
[[ -d "$APP" ]] || { echo "Build the app first." >&2; exit 1; }
BEFORE_APPEARANCE=$(defaults read com.zyncraft.nukesweep nuke.appearance 2>/dev/null || echo system)
BEFORE_AI=$(defaults read com.zyncraft.nukesweep nuke.ai.enabled 2>/dev/null || echo 0)
BEFORE_GROWTH_ROOT=$(defaults read com.zyncraft.nukesweep nuke.growthRoot 2>/dev/null || echo "")
BEFORE_GROWTH_RANGE=$(defaults read com.zyncraft.nukesweep nuke.growthRange 2>/dev/null || echo 30)
BEFORE_GROWTH_BASELINE=$(defaults read com.zyncraft.nukesweep nuke.growthBaseline 2>/dev/null || echo "")
BEFORE_GROWTH_CATEGORIES=$(defaults read com.zyncraft.nukesweep nuke.growthCategories 2>/dev/null || echo 0)
mkdir -p snapshots/current snapshots/baseline
defaults write com.zyncraft.nukesweep nuke.ai.enabled -bool false
defaults write com.zyncraft.nukesweep nuke.growthRoot -string ""
defaults write com.zyncraft.nukesweep nuke.growthRange -int 30
defaults write com.zyncraft.nukesweep nuke.growthBaseline -string ""
defaults write com.zyncraft.nukesweep nuke.growthCategories -bool false

capture() {
  local mode="$1" page="$2" slug="$3"
  defaults write com.zyncraft.nukesweep nuke.appearance -string "$mode"
  pkill -f "$APP/Contents/MacOS/Nuke" 2>/dev/null || true
  sleep 1
  swift scripts/warp-mouse.swift >/dev/null 2>&1 || true
  rm -f /tmp/nuke-*.png
  if [[ "${4:-}" == "ai" ]]; then
    "$APP/Contents/MacOS/Nuke" --compact --capture --without-status-item --capture-page "$page" --capture-fresh --demo-fixtures --demo-ai >/tmp/nuke-snapshot.log 2>&1 &
  else
    "$APP/Contents/MacOS/Nuke" --compact --capture --without-status-item --capture-page "$page" --capture-fresh --demo-fixtures >/tmp/nuke-snapshot.log 2>&1 &
  fi
  local pid=$!
  sleep 8
  local pagefile="/tmp/nuke-${(L)page}.png"
  if [[ -f "$pagefile" ]]; then
    cp "$pagefile" "snapshots/current/$mode-$slug.png"
  else
    cp /tmp/nuke-compact.png "snapshots/current/$mode-$slug.png"
  fi
  kill "$pid" 2>/dev/null || true
  pkill -f "$APP/Contents/MacOS/Nuke" 2>/dev/null || true
}

for mode in light dark; do
  capture "$mode" "AI assist" "ai-assist"
  capture "$mode" "AI assist" "ai-assist-enabled" ai
  capture "$mode" "Storage" "storage"
  capture "$mode" "Projects" "projects"
  capture "$mode" "History" "history"
  capture "$mode" "Growth" "growth"
  capture "$mode" "Processes" "processes"
  capture "$mode" "Developer" "developer"
  capture "$mode" "Docker" "docker"
done

defaults write com.zyncraft.nukesweep nuke.appearance -string "$BEFORE_APPEARANCE"
defaults write com.zyncraft.nukesweep nuke.growthRoot -string "$BEFORE_GROWTH_ROOT"
defaults write com.zyncraft.nukesweep nuke.growthRange -int "$BEFORE_GROWTH_RANGE"
defaults write com.zyncraft.nukesweep nuke.growthBaseline -string "$BEFORE_GROWTH_BASELINE"
if [[ "$BEFORE_GROWTH_CATEGORIES" == "1" ]]; then
  defaults write com.zyncraft.nukesweep nuke.growthCategories -bool true
else
  defaults write com.zyncraft.nukesweep nuke.growthCategories -bool false
fi
if [[ "$BEFORE_AI" == "1" ]]; then
  defaults write com.zyncraft.nukesweep nuke.ai.enabled -bool true
else
  defaults write com.zyncraft.nukesweep nuke.ai.enabled -bool false
fi

if [[ "${1:-}" == "--bless" ]]; then
  for file in snapshots/current/*.png; do
    [[ -f "$file" ]] && cp "$file" "snapshots/baseline/${file:t}"
  done
  echo "Baselines updated."
fi
echo "Snapshots captured in snapshots/current."
