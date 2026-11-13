#!/usr/bin/env python3
"""Assert a recording from `Nuke --measure-ui PATH` against a responsiveness budget.

The recorder probes the main queue every 100ms; each sample is how long that
probe waited. A sample over 250ms is a frame budget missed badly enough for a
person to notice, so the gate is expressed in those terms rather than in averages.

Usage: check-ui-latency.py REPORT [--max-p95 MS] [--max-over N] [--min-samples N]
"""
import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("report")
    parser.add_argument("--max-p95", type=float, default=120.0,
                        help="Fail if the 95th-percentile main-queue wait exceeds this (ms).")
    parser.add_argument("--max-ms", type=float, default=1000.0,
                        help="Fail if any single main-queue wait exceeded this (ms). "
                             "Only one probe is in flight at a time, so a multi-second "
                             "stall records as ONE very large sample rather than many "
                             "over-budget ones -- this is the threshold that sees it.")
    parser.add_argument("--max-over", type=int, default=2,
                        help="Fail if more than this many samples exceeded 250ms. "
                             "A small allowance covers scan start-up, which is real work. "
                             "This catches sustained choppiness; --max-ms catches hangs.")
    parser.add_argument("--min-samples", type=int, default=100,
                        help="Fail if the run was too short to be meaningful.")
    parser.add_argument("--require-scan", action="store_true",
                        help="Require evidence that a scan published results during the itinerary.")
    args = parser.parse_args()

    with open(args.report) as source:
        result = json.load(source)

    samples = result.get("samples", 0)
    p95 = result.get("p95_ms", 0.0)
    worst = result.get("max_ms", 0.0)
    over = result.get("over_250ms", 0)

    print(f"{samples} probes: p95 {p95:.1f} ms, max {worst:.1f} ms, {over} over 250 ms")

    failures = []
    if args.require_scan and not any(
        event.get("phase") == "scanPublished" for event in result.get("phases", [])
    ):
        failures.append("no scan result was published during the itinerary")
    if samples < args.min_samples:
        failures.append(f"only {samples} probes recorded (need {args.min_samples})")
    if p95 > args.max_p95:
        failures.append(f"p95 {p95:.1f} ms exceeds budget {args.max_p95:.1f} ms")
    if worst > args.max_ms:
        failures.append(f"worst main-queue wait {worst:.1f} ms exceeds budget {args.max_ms:.1f} ms")
    if over > args.max_over:
        failures.append(f"{over} samples over 250 ms exceeds allowance {args.max_over}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        for sample in result.get("slow_samples", [])[:5]:
            print(f"  slow sample: {sample.get('latency_ms', 0):.1f} ms", file=sys.stderr)
        return 1

    print("PASS: main thread stayed within budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
