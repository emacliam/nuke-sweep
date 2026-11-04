"""Check that the current build reached a rendered native window (--capture launch)."""
from pathlib import Path
import sys
binary = Path('dist/Nuke Sweep.app/Contents/MacOS/Nuke')
capture = Path('/tmp/nuke-compact.png' if '--compact' in sys.argv else '/tmp/nuke-overview.png')
passed = capture.exists() and capture.stat().st_mtime >= binary.stat().st_mtime
print('PASS: current build rendered a window' if passed else 'FAIL: current build has not rendered its window')
sys.exit(0 if passed else 1)
