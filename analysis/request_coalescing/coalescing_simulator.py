"""CLI wrapper around the bounded coalescing model."""

import argparse
import json
from pathlib import Path

from analysis.embedding_trace import load_trace
from analysis.request_coalescing.bounded_coalescer import CoalescerConfig, simulate_coalescing


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    parser.add_argument("--policy", choices=("none", "fixed_count", "fixed_time", "dual", "adaptive"), default="dual")
    parser.add_argument("--max-requests", type=int, default=8)
    parser.add_argument("--max-wait", type=float, default=8.0)
    parser.add_argument("--max-unique", type=int, default=256)
    parser.add_argument("--arrival-rate", type=float, default=1.0)
    parser.add_argument("--embedding-latency", type=float, default=8.0)
    parser.add_argument("--broadcast-cost", type=float, default=0.25)
    parser.add_argument("--reorder-cost", type=float, default=0.1)
    parser.add_argument("--output", default="results/coalescing_summary.json")
    args = parser.parse_args()
    config = CoalescerConfig(
        policy=args.policy, max_requests=args.max_requests, max_wait=args.max_wait,
        max_unique=args.max_unique, arrival_rate=args.arrival_rate,
        embedding_latency=args.embedding_latency, broadcast_cost=args.broadcast_cost,
        reorder_cost=args.reorder_cost,
    )
    report, _ = simulate_coalescing(load_trace(args.trace), config)
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
