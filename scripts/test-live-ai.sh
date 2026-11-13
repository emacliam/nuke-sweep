#!/bin/zsh
set -eu
cd "${0:A:h:h}"

export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"

echo "Live provider tests skip unless these are set:
  NUKE_LIVE_OPENAI_KEY   [NUKE_LIVE_OPENAI_BASE] [NUKE_LIVE_OPENAI_MODEL]
  NUKE_LIVE_ANTHROPIC_KEY
  NUKE_LIVE_GEMINI_KEY
  NUKE_LIVE_DEEPSEEK_KEY
  NUKE_LIVE_LOCAL_BASE   [NUKE_LIVE_LOCAL_MODEL]
Keys are read from the environment and never written by the tests."

swift test --disable-sandbox --scratch-path .build --filter LiveProviderTests
