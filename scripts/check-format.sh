#!/bin/zsh
# Lint gate.
#
# `swift-format lint` reports two very different things through one channel:
#
#   1. Rule violations -- force unwraps, naming, enum shape, over-long lines.
#      These are judgements about the code and are worth failing a build over.
#   2. Pretty-printer diffs -- AddLines, Indentation, Spacing, RemoveLine,
#      TrailingComma, TrailingWhitespace. These are the formatter saying it would
#      have laid the file out differently.
#
# This codebase is deliberately dense and was not written to the formatter's
# layout, so (2) fires about 1,250 times on untouched, working code. Gating on it
# would mean reformatting the entire project -- including the safety-critical
# review and executor paths -- for no behavioural gain.
#
# So the gate is on (1) only, and says so rather than quietly passing everything.
# Run `./scripts/check-format.sh --all` to see the layout diffs too.
set -eu
cd "${0:A:h:h}"

FORMATTER=$(/usr/bin/xcrun --find swift-format 2>/dev/null || true)
if [[ -z "$FORMATTER" ]]; then
  echo "SKIP: swift-format not found in the active toolchain."
  exit 0
fi

# Rules reported by the pretty-printer rather than by a lint rule.
LAYOUT='\[(AddLines|RemoveLine|Indentation|Spacing|TrailingComma|TrailingWhitespace)\]'

RAW=$("$FORMATTER" lint --configuration .swift-format --recursive Sources Tests 2>&1 || true)

if [[ "${1:-}" == "--all" ]]; then
  echo "$RAW"
  exit 0
fi

SEMANTIC=$(echo "$RAW" | /usr/bin/grep -Ev "$LAYOUT" | /usr/bin/grep -E 'warning:|error:' || true)
LAYOUT_COUNT=$(echo "$RAW" | /usr/bin/grep -Ec "$LAYOUT" || true)

if [[ -n "$SEMANTIC" ]]; then
  echo "$SEMANTIC"
  COUNT=$(echo "$SEMANTIC" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
  echo ""
  echo "FAIL: $COUNT lint violation(s). ($LAYOUT_COUNT layout diffs not gated; see --all.)" >&2
  exit 1
fi

echo "PASS: no lint violations. ($LAYOUT_COUNT layout diffs not gated; see --all.)"
