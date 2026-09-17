#!/usr/bin/env python3
"""CLI for the A18 L1 request-distribution checker.

Local only. No device, no Host rebuild, no performance claims.
"""
from __future__ import print_function

import argparse
import os
import sys


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from analysis.stage2n_a18_l1.workload_analyzer import (  # noqa: E402
    format_records,
    format_summary,
    run_scenario,
)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "L1 request-distribution check. ident and rr are the same "
            "table_id%%B stripe. coaccess copies a row index onto pairs; "
            "it does not change which tables co-occur. Not FPGA HBM latency."))
    parser.add_argument("--tables", type=int, default=4, choices=(4, 8, 16))
    parser.add_argument(
        "--mapping", default="ident", choices=("ident", "rr", "cap"),
        help="ident and rr are aliases of table_id %% B; cap is capacity packing")
    parser.add_argument(
        "--pattern", default="e0",
        choices=("e0", "uniform", "hotspot", "coaccess", "forced_conflict"),
        help="coaccess = same numeric row index on designated pairs, not co-occurrence")
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cap-skew", action="store_true")
    parser.add_argument("--records", action="store_true",
                        help="print per-lookup CSV after the summary")
    args = parser.parse_args(argv)
    if args.pattern == "e0":
        args.tables = 4
        args.mapping = "ident"
        args.rounds = 1
    records, summary = run_scenario(
        n_tables=args.tables,
        mapping=args.mapping,
        pattern=args.pattern,
        n_rounds=args.rounds,
        seed=args.seed,
        cap_skew=args.cap_skew,
    )
    sys.stdout.write(format_summary(summary))
    if args.records:
        sys.stdout.write(format_records(records))
    return 0


if __name__ == "__main__":
    sys.exit(main())
