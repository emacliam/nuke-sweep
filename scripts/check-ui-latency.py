#!/usr/bin/env python3
"""Assert a recording from Nuke --measure-ui PATH. Drive scan/navigation through CUA."""
import json, sys
with open(sys.argv[1]) as source:
    result = json.load(source)
assert result['samples'] >= 100, 'Record at least 100 main-queue probes'
print(f"{result['samples']} probes: max {result['max_ms']:.1f} ms, p95 {result['p95_ms']:.1f} ms, {result['over_250ms']} over 250 ms")
sys.exit(1 if result['over_250ms'] else 0)
