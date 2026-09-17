# A17.6 — four-master target build handoff

Date: 2026-09-09. Scope: executable build implementation; no Host or board run.

The user's instruction to resume engineering supersedes the local A17 writing
pause for this bounded step. Patent and paper drafting are deferred. Accepted
RTL, A16.2 build files, Host, models, and historical evidence remain unchanged.
The user alone performs target builds. Codex does not connect to the server.

## What this package does

- Packages `dlrm_f37x_rtl_kernel_stage2n_a17_v1`. After target link 003 LUTLP-1,
  only the A17 integration handshake was revised: START valid no longer ANDs
  A13 ready, and A13 idle is registered before gating lookup load/START. A13,
  A14, A16, and the A17 public kernel file are unchanged. Do not reuse the
  pre-fix XO `a17_6_xo_001`.
- Includes all 20 RTL source files, including the frozen A16 interval counter.
- Exposes `TABLE_BASE0..3` at `0x304/0x318/0x320/0x328`, each 64 bits, associated
  respectively with `m_axi_gmem0..3` (64-bit address / 128-bit data).
- Links one `dlrm_a17_1` CU to `HBM[0..3]`, requesting 100 MHz.
- Validates pointer metadata inside the XO against generated external metadata.
- Resolves memory indices from CONNECTIVITY and MEM_TOPOLOGY tags, rather than
  assuming the tags HBM[0..3] occupy indices 0..3. Shell IPs are not counted as CUs.
- Requires the source manifest to match before and after building and binds
  link input to the recorded XO and metadata hashes.
- Reuses the unchanged A16 post-route report helper, whose `A16_2_*` environment
  keys/report marker identify that helper, not the identity of the A17 run.
- Checks setup, hold, pulse-width, actual 10 ns kernel clock, unconstrained
  endpoints, DRC/methodology errors and latches. Retains warning counts/reports.

This package has no XRT Host, programming, device query, reset, network, or
automatic rollback operation. Link mapping PASS is not physical mapping PASS.
An A17 xclbin must not be run with the single-BO A16 Host.

## Transfer and source check

Use the ZIP produced by `bundle`; it contains the complete build source closure
and its manifest. Extract into a new empty directory, not over the accepted
server checkout. No Git commit, checkout change, or clean worktree is required.
Preserve file bytes/line endings. Do not run `dos2unix` over the bundle: its
Python and Tcl entry points already work without changing source files.

From the extracted directory, in the existing user-controlled environment:

```bash
python3 scripts/run_stage2n_a17_6_build_v1.py check
```

Expected: `A17_6_SOURCE_INTEGRITY=PASS`. This is a source check only. The runner
uses the Python 3 standard library (Python >=3.5); it installs nothing.

## First target action: XO only

Use the existing Vitis/Vivado 2020.2 shell setup. Then:

```bash
python3 scripts/run_stage2n_a17_6_build_v1.py xo --output runs/a17_6_xo_002 --confirm-build
```

The output directory must not already exist. On failure, keep it and return
`runs/a17_6_xo_002/status.json`, `vivado_version.log`, and `package.log`.
On success also return `xo/kernel.xml` and
`xo/dlrm_f37x_stage2n_a17_ip_v1/component.xml`. Keep the XO itself on the target.
Review these results before the longer link step. An unsupported Vitis XML
variant must be reviewed explicitly; do not bypass a failing metadata check.

## Later target action: link only

After the exact-target XO result is reviewed:

```bash
python3 scripts/run_stage2n_a17_6_build_v1.py link --xo-run runs/a17_6_xo_002 --output runs/a17_6_link_004 --platform /opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm --jobs 8 --confirm-build
```

This consumes the validated XO; it never rebuilds it or programs a device.
Return `status.json`, `link.log`, `xclbin.info`, `connectivity.json`,
`mem_topology.json`, `ip_layout.json`, `post_route.log`, and `post_route/`.
Retain `_x/` and the xclbin on the target for diagnosis. Multiple candidate
routed checkpoints cause a stop for inspection, rather than arbitrary choice.

If a run fails, preserve its directory. A retry uses a new suffix (002, etc.).
Do not modify the source manifest to suppress a mismatch; compare/rebuild the
reviewed bundle instead. No stage is PASS unless its runner returns success
and its retained `status.json` says PASS.

## Local verification and remaining boundary

Local regression tests cover pointer offsets/widths/bus associations, duplicate
argument IDs, stale single-master metadata, archive/external XML mismatch,
shuffled bank indices, shell-IP indexing, wrong/unused banks, timing failures,
and refusal to start a build without the explicit switch. Their constructed
metadata fixtures are tests of validation logic, never target evidence.

Target Vivado/Vitis 2020.2 XO: user-returned `a17_6_xo_001` was reviewed PASS
and is now stale after the LUTLP handshake fix. Rebuild as `a17_6_xo_002`.
Target link: `a17_6_link_001` interrupted; `a17_6_link_002` v++ exit-0 without
xclbin; `a17_6_link_003` routed then failed `write_bitstream` LUTLP-1. Do not
reuse those XO/link directories. Live artifacts are `a17_6_xo_002` /
`a17_6_link_004`. Four-BO Host source is now in tree; see
`docs/STAGE2N_A17_6_FOUR_BO_HOST_V1.md`. Target Host compile remains
user-controlled. Device access, physical four-bank validation, and board
latency: NOT_RUN. Performance: NOT_CLAIMED.

The next authorized step is target Host compile, then a separately confirmed
first board `execute`. A16.2 remains the accepted 112/1174/1289/3 single-bank
baseline. Model scaling and mapping/scheduling algorithms remain outside this
stage.
