# Stage 2N-A17.4 — HBM Mapping Preparation V1

Date: 2026-09-08. Status: **LOCAL PREPARATION ONLY**.

This stage audits the unpackaged A17.2 four-master kernel against the accepted
A16.2 single-bank xclbin path and records a four-bank mapping proposal. It
does not package an XO, run `v++`, program a device, or change RTL, testbenches,
or the A17.2 AXI-Lite ABI.

Accepted public-kernel XSim remains `beff282`. Documentation parent HEAD at the
start of this stage is `c0a4fa1`.

```text
A17_4_LOCAL_PREPARATION=PASS
A17_4_TARGET_XO_BUILD=NOT_RUN
A17_4_TARGET_LINK=NOT_RUN
A17_4_XCLBIN=NOT_RUN
A17_4_PHYSICAL_HBM=NOT_RUN
A17_4_PERFORMANCE=NOT_CLAIMED
RTL_MODIFIED=NO
A16_2_BASELINE_MODIFIED=NO
A17_2_ABI_MODIFIED=NO
NETWORK_ACCESS=NONE
SERVER_ACCESS=NONE
FPGA_DEVICE_ACCESS=NONE
```

## 1. Current A17.2 interface

Public top: `dlrm_f37x_rtl_kernel_stage2n_a17_v1`.

- one `s_axi_control` slave;
- four independent 64-bit-address / 128-bit-data AXI4 read masters
  `m_axi_gmem0` .. `m_axi_gmem3`;
- write channels present for packaging compatibility and tied inactive;
- each master: one single-beat read, at most one outstanding request.

Frozen AXI-Lite window used by mapping and Host:

| Address | Meaning |
|---|---|
| `0x300` | A15 START/CLEAR and status |
| `0x304` / `0x308` | BASE0 low/high (`m_axi_gmem0`) |
| `0x30C` | lookup cycles |
| `0x310` | FPGA end-to-end cycles |
| `0x314` | reserved, reads 0 |
| `0x318` / `0x31C` | BASE1 low/high (`m_axi_gmem1`) |
| `0x320` / `0x324` | BASE2 low/high (`m_axi_gmem2`) |
| `0x328` / `0x32C` | BASE3 low/high (`m_axi_gmem3`) |

Pipeline version word: `0x00024E17`. A13 offsets through `0x224` are unchanged.

Current xclbin binding of those masters: **none**. See
`docs/A17.4_MAPPING_BASELINE.md`.

Accepted A16.2 comparison point remains one kernel
`dlrm_f37x_rtl_kernel_stage2n_a16_v1`, CU `dlrm_a16_1`,
`m_axi_gmem -> HBM[0]`, physical sequential accounting
`112/1174/1289/3` cycles.

## 2. HBM mapping proposal

Do not implement this as a live `config/` file in A17.4. The reviewed proposal
is stored at `analysis/stage2n_a17_4/hbm_mapping_proposal_v1.cfg`:

```ini
[connectivity]
nk=dlrm_f37x_rtl_kernel_stage2n_a17_v1:1:dlrm_a17_1
sp=dlrm_a17_1.m_axi_gmem0:HBM[0]
sp=dlrm_a17_1.m_axi_gmem1:HBM[1]
sp=dlrm_a17_1.m_axi_gmem2:HBM[2]
sp=dlrm_a17_1.m_axi_gmem3:HBM[3]
```

| Master | Proposed bank | Runtime BASE |
|---|---|---|
| `m_axi_gmem0` | `HBM[0]` | BASE0 at `0x304`/`0x308` |
| `m_axi_gmem1` | `HBM[1]` | BASE1 at `0x318`/`0x31C` |
| `m_axi_gmem2` | `HBM[2]` | BASE2 at `0x320`/`0x324` |
| `m_axi_gmem3` | `HBM[3]` | BASE3 at `0x328`/`0x32C` |

Rationale:

- A16.2 already proved `HBM[0]` on this platform;
- the imported A16.2 `MEM_TOPOLOGY` lists `HBM[0]`..`HBM[31]`, so tags `[1]`
  through `[3]` exist as unused memories in that artifact;
- identity mapping port *i* → `HBM[i]` is the smallest unique four-bank
  assignment that can later show independent `m_used` bits;
- one CU and 100 MHz remain the A16/A17 clock/identity contract.

Future XO packaging (A17.5, not this stage) must expose four 64-bit pointer
arguments, each `ASSOCIATED_BUSIF` to exactly one public master:

| Proposed kernel argument | Offset | Port |
|---|---|---|
| `TABLE_BASE0` | `0x304` | `m_axi_gmem0` |
| `TABLE_BASE1` | `0x318` | `m_axi_gmem1` |
| `TABLE_BASE2` | `0x320` | `m_axi_gmem2` |
| `TABLE_BASE3` | `0x328` | `m_axi_gmem3` |

`0x30C` and `0x310` stay custom AXI-Lite counters, not Vitis pointer arguments.
Do not revive A14 `LOOKUP_INDEX` / `RESULT0..3`.

First-board table placement (proposal only): copy the same 1024-byte canonical
A14 table into each BO. Port *i* reads canonical row `37+i` from `BASE_i`.
That is a four-bank concurrency fixture, not four business tables and not an
A18 placement experiment.

## 3. Host audit

Keep two layers separate. A17.4 must not present the future layer as current
implementation.

| Layer | Host | BO / bank | Status in A17.4 |
|---|---|---|---|
| Current implementation | A16.2 `host/stage2n_a16_2_physical_latency_v1.cpp` | one BO, `HBM[0]`, BASE0 only | **unchanged baseline** |
| Future validation | A17.5 Host (not created) | `bo_table0`..`bo_table3`, BASE0–BASE3, `HBM[0..3]` | **proposal only** |

Current Host remains the A16.2 single-BO implementation. Four BO allocation is
an A17.5 future validation requirement.

The first A17.4 checker FAIL (`A16.2 Host BO allocation count changed`) was a
false positive on that current layer. The accepted A16.2 source still has one
`bo_ = xclAllocBO(...)` call; the same token also appears in the allocation
error string. The checker now counts assignment calls only and requires the
A16.2 Host to stay single-BO. It does not require the current Host BO count
to equal 4, and it does not require the current kernel to be linked to
`HBM[0..3]`.

There is no A17 Host. The accepted physical Host is
`host/stage2n_a16_2_physical_latency_v1.cpp`. The future names `bo_table0`..
`bo_table3` live only in `analysis/stage2n_a17_4/host_bo_proposal_v1.txt`.

| Topic | A16.2 actual behavior | A17 future requirement |
|---|---|---|
| CU identity | `dlrm_f37x_rtl_kernel_stage2n_a16_v1:dlrm_a16_1` via `xclIPName2Index` | `dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1`; reject an A16 xclbin |
| Kernel arguments at runtime | **none**. User-managed `xclRegWrite` / `xclRegRead` | keep user-managed AXI-Lite; do not switch to OpenCL `setArg` |
| BO allocation | one `xclAllocBO(..., flags=0, mem_index=0)` | four BOs: `bo_table0`..`bo_table3` |
| Group / mem index | hardcoded `0` because `HBM[0]` is topology index 0 in the A16.2 xclbin | resolve each index from `MEM_TOPOLOGY` `m_tag` `HBM[0]`..`HBM[3]`; then require `xclBOProperties.flags` match |
| Payload | 1024-byte canonical table | 1024 bytes per BO, 16-byte aligned; paddr `0` remains a legal allocation |
| Base programming | write `0x304`/`0x308` from that BO paddr | write BASE0–BASE3 from the four BO paddrs and read them back |
| START | `0x300` `A15_CMD_START` | unchanged command encoding |
| Version | `0x00024E13` | `0x00024E17` |

XRT 2020.2 HAL `xclAllocBO` bank selection is the topology **mem index**
(low 24 bits of `xclBOProperties.flags`), which reviewers may also call a
group id. It is not the integer inside the `HBM[N]` tag unless the dump proves
that equality.

## 4. XRT / metadata verification method

A later target xclbin, produced only by the user, must be checked offline
before any board run. The method follows the accepted A15.5/A16.2 dumps:

1. `CONNECTIVITY`: exactly four `m_connection` records; unique
   `mem_data_index` values; `arg_index` 0..3 correspond to
   `TABLE_BASE0`..`TABLE_BASE3`.
2. `MEM_TOPOLOGY`: tags `HBM[0]`..`HBM[3]` each `m_used=1`; no extra used
   HBM bank for this CU; do not filter on `m_type` (`HBM[0]` is labeled
   `MEM_DDR4` in the A16.2 dump).
3. `IP_LAYOUT`: exactly one `IP_KERNEL` named
   `dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1`.
4. kernel XML / XO: four masters `m_axi_gmem0`..`3`, 128-bit data, 64-bit
   address, four pointer arguments, no stale A14 names.
5. Host: four live BOs; each `mem_index` equals the topology index of the
   intended tag; four BASE readbacks match the four paddrs.
6. Negative gates: one-bank leftover, duplicate `HBM[0]` four times, missing
   master, A16 kernel/CU identity, and hardcoded mem-index `0` for all four
   BOs must fail.

A16.2 evidence may be used only as a platform-tag reference. It must not be
relabeled as A17 four-bank proof.

## 5. Risks

- Four public AXI ports in RTL are a packaging prerequisite, not four physical
  banks.
- F37X has proven `HBM[0]` only. `HBM[1]`..`HBM[3]` tags exist in MEM_TOPOLOGY
  but have not been linked or allocated by this project.
- Vitis 2020.2 may serialize or share HBM interconnect even with four `sp`
  lines; metadata `used` bits are not bandwidth.
- Four XO pointer arguments are required for `v++`. Runtime still programs
  bases through AXI-Lite; mixing those models is a packaging bug class already
  seen in A14/A15.
- Topology index is not guaranteed to equal `N` in `HBM[N]` on a future xclbin.
- Loading the frozen A16 xclbin with an A17 Host would silently stay on one
  bank.
- Four copied canonical tables do not prove multi-table placement (A18).
- Added AXI SI at 100 MHz may consume the existing 0.000 ns WNS gate.
- paddr 0 is valid; treat API/property failure, not a zero address, as the
  allocation error.
- This document is not authorization to connect to the server, rebuild the
  A16 xclbin, or claim speedup.

## 6. A17.5 acceptance criteria

A17.5 is **physical HBM validation preparation**, still local/source-only
unless a later user-controlled target run is separately authorized. A17.5
PASS may be claimed only when all of the following are true:

1. A16.2 baseline files and A17.2 RTL/TB/ABI are unchanged.
2. A versioned A17 XO package Tcl names
   `dlrm_f37x_rtl_kernel_stage2n_a17_v1`, four masters, and four
   `TABLE_BASE*` arguments. Codex/Cursor does not execute that Tcl on the
   target.
3. A live `config/` connectivity file matches the proposal in section 2,
   requests 100 MHz, and is not an edit of `stage2n_a16_2_target_v1.cfg`.
4. A versioned A17 Host source allocates `bo_table0`..`bo_table3`, resolves
   mem indexes from tags, writes BASE0–BASE3, and rejects A16 identities.
5. Offline validators reject one-bank, duplicate-bank, wrong-kernel, and
   stale-A14 signatures.
6. Status language remains `A17_5_TARGET_XO_BUILD=NOT_RUN`,
   `A17_5_TARGET_LINK=NOT_RUN`, `A17_5_XCLBIN=NOT_RUN`, and
   `A17_5_PHYSICAL_HBM=NOT_RUN` until the user returns reviewed target
   evidence.

A17.5 must not start A18, must not modify frozen A13–A16 assets, and must not
claim bandwidth, latency improvement, throughput, power, or speedup.

## Evidence boundary

A17.4 proves only that the current A17 public interface is four unmapped AXI
masters, that the A16.2 path is still one `m_axi_gmem -> HBM[0]`, and that a
four-bank `sp` proposal plus Host/BO plan have been written down. It cannot
prove XO validity, link timing, physical HBM[0..3] access, or any performance
result.
