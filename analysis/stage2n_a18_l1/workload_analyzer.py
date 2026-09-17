#!/usr/bin/env python3
"""L1 request-distribution checker (geometry only).

Full gather: every round looks up each of T tables once. Not HBM latency,
bandwidth, QPS, throughput, or speedup. The coaccess pattern only copies a
row index onto designated table pairs; it does not change which tables
appear together.
"""
from __future__ import print_function

import json
import random


N_BANKS = 4
NROWS_CANONICAL = 64
# E0 / A17 fixture in slot order: slot0→37, slot1→38, slot2→39, slot3→40.
A17_FIXED_ROWS = (37, 38, 39, 40)
# ident and rr are two names for table_id % B, not independent baselines.
STRIPE_MAPPINGS = ("ident", "rr")
MAPPINGS = ("ident", "rr", "cap")
PATTERNS = ("e0", "uniform", "hotspot", "coaccess", "forced_conflict")
FORBIDDEN_METRIC_TOKENS = ("GB/s", "GBs", "QPS", "throughput", "speedup", "加速比")
GATHER_MODE = "ONE_LOOKUP_PER_TABLE_PER_ROUND"


class AnalyzerError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise AnalyzerError(message)


def stripe_bank(table_id, n_banks):
    """Shared ident/rr mapping: bank = table_id % n_banks."""
    return int(table_id) % int(n_banks)


def ident_bank(table_id, n_banks):
    return stripe_bank(table_id, n_banks)


def rr_bank(table_id, n_banks):
    return stripe_bank(table_id, n_banks)


def cap_assignment(n_tables, n_banks, capacities):
    require(len(capacities) == n_tables, "capacity vector length")
    load = [0] * n_banks
    assign = [0] * n_tables
    order = sorted(range(n_tables), key=lambda t: (-int(capacities[t]), t))
    for table_id in order:
        bank = min(range(n_banks), key=lambda b: (load[b], b))
        assign[table_id] = bank
        load[bank] += int(capacities[table_id])
    return assign


def default_capacities(n_tables, skew):
    if not skew:
        return [1] * n_tables
    return [int(n_tables - t) for t in range(n_tables)]


def table_banks(n_tables, mapping, n_banks, capacities, force_pair=None):
    require(mapping in MAPPINGS, "mapping must be ident|rr|cap")
    require(n_tables in (4, 8, 16), "T must be 4, 8, or 16")
    require(n_banks == N_BANKS, "B is frozen at 4")
    if mapping in STRIPE_MAPPINGS:
        banks = [stripe_bank(t, n_banks) for t in range(n_tables)]
    else:
        banks = cap_assignment(n_tables, n_banks, capacities)
    if force_pair:
        hot_a, hot_b, hot_bank = force_pair
        banks[hot_a] = hot_bank
        banks[hot_b] = hot_bank
    return banks


def occupancy_vector(banks, n_banks):
    occ = [0] * int(n_banks)
    for bank in banks:
        occ[int(bank)] += 1
    idle = [idx for idx, count in enumerate(occ) if count == 0]
    return occ, idle


def zipf_index(rng, nrows, alpha):
    require(nrows > 0, "nrows")
    weights = []
    total = 0.0
    for rank in range(1, nrows + 1):
        weight = rank ** (-float(alpha))
        weights.append(weight)
        total += weight
    draw = rng.random() * total
    acc = 0.0
    for index, weight in enumerate(weights):
        acc += weight
        if draw <= acc:
            return index
    return nrows - 1


def same_row_index_pairs(n_tables):
    """Designated pairs that copy a row index. Not a co-occurrence model."""
    if n_tables >= 8:
        return [(0, 4), (1, 5)]
    return [(0, 1)]


def draw_indices(pattern, n_tables, rng, nrows, alpha):
    if pattern == "e0":
        require(n_tables == 4, "e0 is the T=4 A17 fixture")
        return list(A17_FIXED_ROWS)
    indices = [0] * n_tables
    if pattern == "uniform":
        for table_id in range(n_tables):
            indices[table_id] = rng.randint(0, nrows - 1)
        return indices
    if pattern == "hotspot" or pattern == "forced_conflict":
        # Zipf changes row_id only. Table request counts stay 1 per round.
        for table_id in range(n_tables):
            indices[table_id] = zipf_index(rng, nrows, alpha)
        return indices
    if pattern == "coaccess":
        # Same-row-index construction. Every table still appears once.
        # Equal numeric row ids are not the same physical address across tables.
        for table_id in range(n_tables):
            indices[table_id] = rng.randint(0, nrows - 1)
        for left, right in same_row_index_pairs(n_tables):
            indices[right] = indices[left]
        return indices
    raise AnalyzerError("unknown pattern " + pattern)


def round_geometry(table_ids, indices, banks):
    require(len(table_ids) == len(indices) == len(banks), "row alignment")
    n_requests = len(banks)
    counts = {}
    for bank in banks:
        counts[bank] = counts.get(bank, 0) + 1
    n_channels_used = len(counts)
    # Geometric only: extra requests beyond one per used channel.
    conflict_count = n_requests - n_channels_used
    proxy = max(counts.values()) if counts else 0
    rows = []
    for table_id, index, bank in zip(table_ids, indices, banks):
        rows.append({
            "table_id": int(table_id),
            "index": int(index),
            "bank": int(bank),
            "concurrency": int(n_channels_used),
            "conflict_count": int(conflict_count),
            "max_completion_proxy": int(proxy),
            "bank_occupancy": int(counts[bank]),
        })
    return rows, counts, n_channels_used, conflict_count, proxy


def summarize_forbidden_ok(text):
    lowered = text.lower()
    for token in FORBIDDEN_METRIC_TOKENS:
        if token.lower() in lowered:
            return False
    return True


def pattern_kind(pattern):
    if pattern == "coaccess":
        return "SAME_ROW_INDEX"
    if pattern == "hotspot":
        return "ZIPF_ROW_INDEX_ONLY"
    if pattern == "forced_conflict":
        return "FORCE_TWO_TABLES_TO_BANK0"
    if pattern == "e0":
        return "A17_FIXED_ROWS"
    return "INDEPENDENT_ROW_INDEX"


def run_scenario(n_tables, mapping, pattern, n_rounds=1, seed=1, n_banks=N_BANKS,
                 nrows=NROWS_CANONICAL, zipf_alpha=1.2, cap_skew=False):
    require(pattern in PATTERNS, "pattern must be e0|uniform|hotspot|coaccess|forced_conflict")
    require(n_rounds >= 1, "n_rounds")
    capacities = default_capacities(n_tables, cap_skew)
    force_pair = None
    if pattern == "forced_conflict":
        require(n_tables >= 2, "forced_conflict needs two tables")
        force_pair = (0, 1, 0)
    banks = table_banks(n_tables, mapping, n_banks, capacities, force_pair)
    occ, idle = occupancy_vector(banks, n_banks)
    oversubscribe = n_tables > n_banks
    reused_banks = sorted(set(b for b in banks if banks.count(b) > 1))
    rng = random.Random(int(seed))
    records = []
    proxies = []
    conflicts = []
    pair_same = 0
    pair_total = 0
    pairs = same_row_index_pairs(n_tables)
    table_ids = list(range(n_tables))
    n_requests = n_tables
    for round_id in range(n_rounds):
        indices = draw_indices(pattern, n_tables, rng, nrows, zipf_alpha)
        rows, _counts, _used, conflict_count, proxy = round_geometry(
            table_ids, indices, banks)
        require(len(rows) == n_tables, "must not skip tables")
        proxies.append(proxy)
        conflicts.append(conflict_count)
        for row in rows:
            item = dict(row)
            item["round_id"] = int(round_id)
            records.append(item)
        if pattern == "coaccess":
            for left, right in pairs:
                pair_total += 1
                if banks[left] == banks[right]:
                    pair_same += 1
    summary = {
        "KIND": "L1_GEOMETRY",
        "ROLE": "REQUEST_DISTRIBUTION_CHECK",
        "T": int(n_tables),
        "B": int(n_banks),
        "MAPPING": mapping,
        "MAPPING_FAMILY": "STRIPE_MOD_B" if mapping in STRIPE_MAPPINGS else "CAP",
        "IDENT_RR_EQUIVALENT": True,
        "PATTERN": pattern,
        "PATTERN_KIND": pattern_kind(pattern),
        "GATHER": GATHER_MODE,
        "ROUNDS": int(n_rounds),
        "SEED": int(seed),
        "NROWS": int(nrows),
        "ZIPF_ALPHA": float(zipf_alpha) if pattern in ("hotspot", "forced_conflict") else None,
        "HOTSPOT_SCOPE": "ROW_INDEX_ONLY",
        "CAP_SKEW": bool(cap_skew),
        "TABLE_BANKS": list(banks),
        "BANK_OCCUPANCY": list(occ),
        "IDLE_CHANNELS": list(idle),
        "N_REQUESTS_PER_ROUND": int(n_requests),
        "CONCURRENCY_DEF": "USED_CHANNELS",
        "CONFLICT_DEF": "N_REQUESTS_MINUS_USED_CHANNELS",
        "OVERSUBSCRIBE": bool(oversubscribe),
        "REUSED_BANKS": reused_banks,
        "CONFLICT_SUM": int(sum(conflicts)),
        "PROXY_MAX": int(max(proxies)),
        "PROXY_LIST": list(proxies),
        "SAME_ROW_INDEX_PAIRS": list(pairs) if pattern == "coaccess" else [],
        "SAME_ROW_INDEX_SAME_BANK": int(pair_same),
        "SAME_ROW_INDEX_PAIR_ROUNDS": int(pair_total),
        "SAME_ROW_INDEX_CHANGES_TABLE_SET": False,
        "PHYSICAL_HBM": "NOT_MODELED",
        "PERFORMANCE": "NOT_CLAIMED",
        "NOTE": (
            "concurrency=used channels; conflict_count=requests-used channels; "
            "proxy=max occupancy; not FPGA cycles or physical collisions"
        ),
    }
    blob = json.dumps(summary, sort_keys=True)
    require(summarize_forbidden_ok(blob), "forbidden performance tokens in summary")
    return records, summary


def format_summary(summary):
    idle = summary["IDLE_CHANNELS"]
    lines = [
        "KIND={0}".format(summary["KIND"]),
        "ROLE=REQUEST_DISTRIBUTION_CHECK",
        "T={0}".format(summary["T"]),
        "B={0}".format(summary["B"]),
        "MAPPING={0}".format(summary["MAPPING"]),
        "MAPPING_FAMILY={0}".format(summary["MAPPING_FAMILY"]),
        "IDENT_RR_EQUIVALENT=YES",
        "PATTERN={0}".format(summary["PATTERN"]),
        "PATTERN_KIND={0}".format(summary["PATTERN_KIND"]),
        "GATHER={0}".format(summary["GATHER"]),
        "ROUNDS={0}".format(summary["ROUNDS"]),
        "SEED={0}".format(summary["SEED"]),
        "TABLE_BANKS={0}".format(",".join(str(b) for b in summary["TABLE_BANKS"])),
        "BANK_OCCUPANCY={0}".format(",".join(str(v) for v in summary["BANK_OCCUPANCY"])),
        "IDLE_CHANNELS={0}".format(",".join(str(v) for v in idle) if idle else "none"),
        "OVERSUBSCRIBE={0}".format("YES" if summary["OVERSUBSCRIBE"] else "NO"),
        "REUSED_BANKS={0}".format(",".join(str(b) for b in summary["REUSED_BANKS"]) or "none"),
        "CONCURRENCY_DEF=USED_CHANNELS",
        "CONFLICT_DEF=N_REQUESTS_MINUS_USED_CHANNELS",
        "CONFLICT_SUM={0}".format(summary["CONFLICT_SUM"]),
        "PROXY_MAX={0}".format(summary["PROXY_MAX"]),
        "PHYSICAL_HBM=NOT_MODELED",
        "PERFORMANCE=NOT_CLAIMED",
        "METRIC_CLASS=GEOMETRY_ONLY",
        "NOTE={0}".format(summary["NOTE"]),
    ]
    if summary["PATTERN"] == "coaccess":
        lines.append("SAME_ROW_INDEX_PAIRS={0}".format(summary["SAME_ROW_INDEX_PAIRS"]))
        lines.append("SAME_ROW_INDEX_SAME_BANK={0}/{1}".format(
            summary["SAME_ROW_INDEX_SAME_BANK"],
            summary["SAME_ROW_INDEX_PAIR_ROUNDS"]))
        lines.append("SAME_ROW_INDEX_CHANGES_TABLE_SET=NO")
    if summary["PATTERN"] == "hotspot":
        lines.append("HOTSPOT_SCOPE=ROW_INDEX_ONLY")
    if summary["PATTERN"] == "forced_conflict":
        lines.append("LOAD_SHAPE=UNBALANCED_NOT_IDLE")
    return "\n".join(lines) + "\n"


def format_records(records):
    header = (
        "round_id,table_id,index,bank,concurrency,conflict_count,"
        "max_completion_proxy,bank_occupancy"
    )
    lines = [header]
    for row in records:
        lines.append(
            "{round_id},{table_id},{index},{bank},{concurrency},"
            "{conflict_count},{max_completion_proxy},{bank_occupancy}".format(**row)
        )
    return "\n".join(lines) + "\n"
