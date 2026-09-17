# Stage 2N-A17.5A — Target Packaging Audit V1

Date: 2026-09-08. Status: **LOCAL AUDIT / PROPOSAL ONLY**.

A17.5A inspects the accepted A16.2 packaging path and the unpackaged A17.2
public kernel interface. It does not modify RTL, testbenches, or Host source,
does not add a live `config/` file, does not invoke `v++`, and does not
access a board.

```text
A17_5A_LOCAL_PREPARATION=PASS
A17_5A_TARGET_XO_BUILD=NOT_RUN
A17_5A_TARGET_LINK=NOT_RUN
A17_5A_XCLBIN=NOT_RUN
A17_5A_PHYSICAL_HBM=NOT_RUN
A17_5A_PERFORMANCE=NOT_CLAIMED
RTL_MODIFIED=NO
TB_MODIFIED=NO
HOST_MODIFIED=NO
VPP_INVOKED=NO
BOARD_ACCESSED=NO
```

Paper language remains: A17 establishes a multi-bank-capable FPGA architecture
and verification framework. It has not achieved multi-bank HBM acceleration.

## 1. A16.2 packaging flow

There is no `platform/` directory. Historical `tcl/package_stage2n_a*.tcl`
files package A2/A8/A10 kernels and are not the A16.2 path. A16.2 packaging
lives under `scripts/` plus one live connectivity file.

| Step | File | Role |
|---|---|---|
| XO package Tcl | `scripts/package_stage2n_a16_2_rtl_kernel_v1.tcl` | Vivado `package_xo` for user-managed RTL kernel |
| XO runner | `scripts/build_stage2n_a16_2_target_xo_v1.sh` | User-executed exact-target XO-only; no `v++` |
| XO validator | `scripts/validate_stage2n_a16_2_xo_v1.py` | Offline kernel XML / argument / width gate |
| Link config | `config/stage2n_a16_2_target_v1.cfg` | Live `v++ --config` input |
| Link runner | `scripts/link_stage2n_a16_2_target_xclbin_v1.sh` | User-executed `v++ --link`; no device open |
| xclbin validator | `scripts/validate_stage2n_a16_2_xclbin_v1.py` | CONNECTIVITY / MEM_TOPOLOGY / IP_LAYOUT |
| Post-route Tcl | `scripts/report_stage2n_a16_2_vitis_post_route_v1.tcl` | 100 MHz timing extract after link |
| Host build | `scripts/build_stage2n_a16_2_host_v1.sh` | Separate from link |
| Board runner | `scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh` | Protected F37X run; out of A17.5A scope |

Local `build/stage2n_a16_2/` is absent in this worktree. Generated XO/xclbin
remain outside Git. Compact accepted dumps are under
`docs/evidence/stage2n_a16_2/final_acceptance_v1/`.

### Identities

| Item | A16.2 accepted value |
|---|---|
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` |
| Compute unit | `dlrm_a16_1` |
| Control | `s_axi_control` |
| Memory master | one `m_axi_gmem` |
| Connectivity | `dlrm_a16_1.m_axi_gmem:HBM[0]` |
| Kernel argument | `TABLE_BASE`, offset `0x304`, size 8, `void*`, `addressQualifier=1` |
| Part | `xcvu37p-fsvh2892-2L-e` |
| Platform | `inspur_f37x_xdma_201920_3` |
| Platform path | `/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm` |
| Clock | 100 MHz |
| Vitis | 2020.2 |
| XO SHA256 | `ea0fe950339ada07eaacd181c495dcb1f07251ed20e7d1cef44479bc36cec94a` |
| xclbin SHA256 | `5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4` |

XO packaging writes IP-XACT `ASSOCIATED_BUSIF=m_axi_gmem` for that single
pointer. Runtime does not use `setArg`; the A16.2 Host programs `0x304/0x308`
with `xclRegWrite`.

Link command shape (user-controlled target only):

```text
v++ --target hw --link --platform <xpfm> --config config/stage2n_a16_2_target_v1.cfg
    --kernel_frequency 100 --output build/stage2n_a16_2/link_v1/hw/<kernel>.xclbin
    <xo>
```

A17.5A did not run that command.

## 2. A17.2 kernel interface to package later

Public top: `dlrm_f37x_rtl_kernel_stage2n_a17_v1`.

- `s_axi_control`
- four 64-bit-address / 128-bit-data masters `m_axi_gmem0` .. `m_axi_gmem3`
- BASE0 at `0x304/0x308`, BASE1 at `0x318/0x31C`, BASE2 at `0x320/0x324`,
  BASE3 at `0x328/0x32C`
- counters `0x30C` / `0x310` stay custom AXI-Lite registers, not pointer args
- pipeline version `0x00024E17`

There is no A17 package Tcl, no A17 XO runner, no A17 live `config/`, and no
A17 xclbin. Internal packed `m_axi_gmem_*` arrays are not Vitis masters.

A later XO (not this stage) must describe four pointer arguments:

| Proposed argument | Offset | Port |
|---|---|---|
| `TABLE_BASE0` | `0x304` | `m_axi_gmem0` |
| `TABLE_BASE1` | `0x318` | `m_axi_gmem1` |
| `TABLE_BASE2` | `0x320` | `m_axi_gmem2` |
| `TABLE_BASE3` | `0x328` | `m_axi_gmem3` |

Copying the A16.2 Tcl unchanged would package one `m_axi_gmem` and one
`TABLE_BASE` and is therefore the wrong template.

## 3. Connectivity proposal

Stored only at
`analysis/stage2n_a17_5/connectivity_a17_multibank_proposal.cfg`.
Header required: `PROPOSAL ONLY`, `NOT FOR v++`, `UNVALIDATED`.

Proposed CU name `dlrm_a17_1` is the A17.4/A17.5A planning identity. It is not
a packaged compute unit today.

```ini
[connectivity]
nk=dlrm_f37x_rtl_kernel_stage2n_a17_v1:1:dlrm_a17_1
sp=dlrm_a17_1.m_axi_gmem0:HBM[0]
sp=dlrm_a17_1.m_axi_gmem1:HBM[1]
sp=dlrm_a17_1.m_axi_gmem2:HBM[2]
sp=dlrm_a17_1.m_axi_gmem3:HBM[3]
```

Do not place this file under `config/`. Do not edit
`config/stage2n_a16_2_target_v1.cfg`.

## 4. Host mapping (documented, not implemented)

Current Host remains A16.2 single-BO. Future mapping, still via `xclRegWrite`:

| Future BO | BASE | Offsets | Port | Bank |
|---|---|---|---|---|
| BO0 | BASE0 | `0x304` / `0x308` | `m_axi_gmem0` | `HBM[0]` |
| BO1 | BASE1 | `0x318` / `0x31C` | `m_axi_gmem1` | `HBM[1]` |
| BO2 | BASE2 | `0x320` / `0x324` | `m_axi_gmem2` | `HBM[2]` |
| BO3 | BASE3 | `0x328` / `0x32C` | `m_axi_gmem3` | `HBM[3]` |

See `analysis/stage2n_a17_5/host_mapping_proposal_v1.txt`. No A17 Host file is
added in A17.5A.

## 5. Gaps before a user-controlled A17 package/link

1. Versioned A17 `package_xo` Tcl with four masters and four pointer args.
2. Live `config/` only after review; never by silently replacing A16.2.
3. XO/xclbin validators that require four used `HBM[0..3]` tags and reject
   one-bank leftovers.
4. A17 Host that resolves mem indexes from tags and writes BASE0–BASE3.
5. A17 runners must not reuse the A16.2 expected branch
   `work/stage2n-a15-hbm-pipeline-integration` without an explicit new
   baseline.
6. Four `sp` lines are not bandwidth, latency, or acceleration evidence.

A17.5B may prepare physical-validation sources. It is not a board PASS and
must not upgrade the paper claim.

## Evidence boundary

A17.5A proves only that the A16.2 packaging path is understood and that an
unvalidated four-bank `sp` proposal plus Host-mapping note exist under
`analysis/`. It cannot prove XO validity, Vitis link, target timing, physical
HBM[0..3] access, or any performance result.

The static checker diffs only tracked A16.2/A17 files against HEAD. Historical
untracked files under `rtl/`, `tb/`, and `host/` are preserved and are not a
FAIL.
