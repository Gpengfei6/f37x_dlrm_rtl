# Stage 2N-A15.6 Protected All-HBM Board Validation Preparation V1

Date: 2026-08-28

## 1. Objective and decision

Stage 2N-A15.6 prepares, but does not execute, a protected real-F37X functional
validation of the accepted A15.5 artifact:

```text
fixed A15.5 xclbin
  -> one physical HBM[0] BO
  -> rows 37, 38, 39, 40 read sequentially
  -> A13 embedding slots 0, 1, 2, 3
  -> Bottom MLP -> Feature Interaction -> Top MLP
  -> exact software-golden result
```

This local preparation result is:

```text
A15_6_LOCAL_PREPARATION=PASS
FROZEN_RTL_MODIFIED=NO
XCLBIN_REBUILT=NO
FPGA_PROGRAMMING=NOT_RUN
HOST_EXECUTION=NOT_RUN
PHYSICAL_HBM=NOT_RUN
BOARD_FUNCTIONAL=NOT_RUN
PERFORMANCE=NOT_CLAIMED
FPGA_DEVICE_ACCESS=NONE
SERVER_ACCESS=NONE
NETWORK_ACCESS=NONE
READY_FOR_PROTECTED_BOARD_EXECUTION=YES
```

`READY_FOR_PROTECTED_BOARD_EXECUTION=YES` means the reviewed Host, assets,
protection runner and offline validator are locally prepared. It is not a board
PASS and does not authorize unattended execution.

## 2. Frozen A15.5 baseline

| Item | Frozen value |
|---|---|
| Preparation parent HEAD | `14cb37721b918e644c8cae689791628247a00eec` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a15_v1` |
| Compute unit | `dlrm_a15_1` |
| Platform | `inspur_f37x_xdma_201920_3` |
| Part | `xcvu37p-fsvh2892-2L-e` |
| Clock | 100 MHz |
| XO SHA256 | `a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019` |
| xclbin SHA256 | `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356` |
| xclbin UUID | `1b555645-a9e2-4f5e-95af-6ce4adacbc3c` |
| Connectivity | `dlrm_a15_1.m_axi_gmem -> HBM[0]` |
| Accepted wrapper SHA256 | `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1` |

The local source check recomputed the wrapper SHA256 and passed. No A13, A14,
A15.1, A15.2, A15.3, A15.4 or A15.5 frozen datapath file was changed. No XO or
xclbin was built or modified.

## 3. Audited implementation sources

The preparation was derived from source rather than old summaries:

- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv` defines the public A15
  status/control window and preserves the complete A13 configuration window;
- `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv` fixes the
  sequential row-to-slot mapping 37->0, 38->1, 39->2 and 40->3 through one A14
  v2 lookup engine and one AXI read master;
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv` proves public-port sequencing,
  mask `0xF`, complete local inference and accepted counters;
- `host/stage2n_a14_7_hbm_single_table_board_smoke_v1.cpp` supplies the accepted
  XRT 2020.2 low-level BO allocation/map/sync/paddr/MMIO/cleanup pattern;
- `scripts/program_and_run_stage2n_a14_7_hbm_smoke_v1.sh` supplies the accepted
  BDF, UUID/CU, activity, HBM-use and explicit-authorization guards;
- `host/stage2n_a13_cycle_counter_board_v1.cpp` supplies the accepted descriptor,
  weight, bias, dense-input, result-retirement and cycle-counter programming
  sequence;
- `python/build_stage2n_a11_pipeline_batch_asset_v2.py` supplies the accepted
  fixed-point Bottom, Interaction and Top software reference.

The new Host therefore does not assume that TABLE_BASE alone configures a full
inference. It programs five descriptors, 1,360 INT8 weights, 73 INT24 biases,
the eight-value dense input, Bottom/Top segment controls and interaction shift
before issuing A15 START. It never writes embedding slots through the Host
embedding registers.

## 4. Exact A15/A13 ABI

### A15 window

| Offset | Meaning | Audited behavior |
|---:|---|---|
| `0x300` | A15 CONTROL/STATUS | write `1` START; write `2` CLEAR; reads have no side effect |
| `0x304` | TABLE_BASE low | writable only while A15 is IDLE; readable |
| `0x308` | TABLE_BASE high | writable only while A15 is IDLE; readable |

The `0x300` read status is:

| Bits | Meaning |
|---:|---|
| 0 | A15 active |
| 1 | four-row sequence busy |
| 2 | all four embeddings loaded |
| 3 | A13 core busy |
| 4 | A15 DONE state |
| 5 | A15 error/recovery condition |
| 6 | START-ready; this is the usable idle-and-ready indication |
| 7 | final result valid |
| 11:8 | A13 embedding loaded mask |
| 13:12 | failing lookup slot |
| 15 | wrapper error latched |
| 23:16 | failing lookup index low byte |
| 24 | load-all request ready |
| 25 | A13 start ready |
| 26 | four-row sequence done pulse |
| 27 | embedding injection done pulse |
| 30:28 | A15 FSM state |
| 31 | aggregate error |

START is accepted only in IDLE when all model/input command paths, A13 and the
load-all controller are ready. A rejected START sets the existing wrapper error
instead of replacing an active operation. START snapshots TABLE_BASE and the
Bottom/Top/interaction configuration, performs four lookups, waits for loaded
mask `0xF`, and then starts A13 automatically.

CLEAR is accepted only from DONE or ERROR. DONE clears directly to IDLE. ERROR
enters recovery and returns to IDLE after the retained lookup error is
acknowledged. A `0x300` read does not clear DONE. The Host polling rule is:

1. poll A13 result-valid at `0x180` bit 2 while also rejecting A15 error;
2. read result/index/meta and counters;
3. issue result POP through `0x180` command `0x40`;
4. poll A15 DONE at `0x300` bit 4;
5. issue A15 CLEAR (`2`);
6. poll `0x300` bit 6 before the next case.

### Preserved A13 programming/result window

The Host preserves the accepted offsets and command semantics. In particular:

- descriptor staging/commit: `0x190..0x19C`, command `0x0001` at `0x180`;
- dense activation staging/commit: `0x1A0..0x1CC`, command `0x0002`;
- weight address/data/commit: `0x1E4/0x1E8`, command `0x0008`;
- bias address/data/commit: `0x1EC/0x1F0`, command `0x0010`;
- Bottom/Top/interaction config: `0x1F4/0x1F8/0x1FC`;
- final result/index/meta: `0x200/0x204/0x208`;
- embedding loaded mask: `0x20C`;
- error/config-ready: `0x210/0x214`;
- Bottom/Interaction/Top/Total counters:
  `0x218/0x21C/0x220/0x224`.

The A13 direct embedding commit remains intentionally unused because all four
slots are owned by A15 physical-HBM lookups.

## 5. XRT and physical HBM allocation method

The versioned Host reuses the A14.7-proven low-level XRT 2020.2 calls:

```text
xclOpen
xclIPName2Index
xclOpenContext
xclAllocBO(HBM memory index 0, 1024 bytes)
xclGetBOProperties
xclMapBO
memcpy + xclSyncBO(TO_DEVICE)
xclRegWrite/xclRegRead
xclUnmapBO + xclFreeBO
xclCloseContext + xclClose
```

The BO contract is one 1,024-byte allocation in memory-topology index 0,
corresponding to linked `HBM[0]`. The Host checks the returned allocation size,
memory index, 16-byte alignment and 64-bit address range. It deliberately does
not reject physical address `0x0`; A14.7 proved that address can be legal.

For every case, all 1,024 bytes are copied and synchronized Host-to-device. The
real 64-bit `xclBOProperties.paddr` value is split into TABLE_BASE low/high,
written at `0x304/0x308`, and read back before START.

RAII cleanup releases a mapped BO on all C++ exception paths. A successful run
also calls checked unmap/free explicitly. The runner then requires no process
to retain the target render node and requires HBM[0] to report zero bytes and
zero active BOs. It never resets the FPGA, invokes global HBM cleanup, kills a
process or touches another device.

## 6. Fixed xclbin and device protection gates

The protected runner accepts an explicit existing xclbin path. Before any
device-changing action it requires:

- exact xclbin SHA256 and UUID from the frozen A15.5 acceptance;
- exact kernel and CU in `xclbinutil --info`;
- local source/asset validation and evidence-validator self-test;
- XRT 2020.2 Host build PASS;
- explicit runtime device index, rather than silently assuming historical
  index 2;
- index-to-BDF-to-platform mapping for BDF `0000:9b:00.1`;
- render-node-to-BDF mapping;
- firewall GOOD, CU IDLE, no render-node owner and HBM[0] zero usage;
- an explicit allowlisted source UUID/CU if another image is currently loaded.

The runner displays device/BDF, xclbin SHA/UUID, kernel/CU, HBM bank, FPGA
programming possibility, BO allocation and full-DLRM execution intent. It also
states that reset, global cleanup and other-device access are forbidden. Only
the exact response `yes` continues. `no` or any other response exits safely.

If the accepted UUID is already active, programming is skipped. Otherwise the
runner programs only the guarded BDF after authorization. There is no reset,
rollback or automatic selection of the first FPGA.

## 7. Deterministic golden and sensitivity cases

The local generator reads the SHA-frozen Stage 2M package through the accepted
A11 v2 reader and reuses its exact INT16/INT8/INT24/INT48, round-away-from-zero,
saturation, ReLU, interaction ordering and layer ordering. Source sample 0 is
used:

```text
dense = [-575, 591, 123, -461, 2813, -2032, 28, -519]
categorical IDs = [55, 45, 49, 63]
baseline expected Bottom = [849, 85, 853, 165, 0, 542, 1225, 1930]
baseline expected final result = -393
```

The physical table retains the A14 64-row, eight-lane, little-endian INT16,
16-byte-row, 1,024-byte layout. Rows 37 through 40 are replaced with the four
resolved sample-0 embeddings. Every sensitivity case changes only lane 0 in
one selected row by +2048; all other rows 37 through 40 remain bit-identical.

| Case | Changed HBM-derived slot | Expected final | Table SHA256 |
|---|---:|---:|---|
| baseline | none | -393 | `c319aeef84dc1cf4c73d16ab7c498bb31f37460f339cf849616952bb676d00cb` |
| slot0 sensitivity | row37/slot0 | -392 | `5b7e39bd29ba27fdf6732cc441cdb7bea09d6abef07a78098a9d87af4b032717` |
| slot1 sensitivity | row38/slot1 | -93 | `b37a4ff8e18ca29020a2e0b261f7b57f879b250025e309a8f4a0336df1b95f14` |
| slot2 sensitivity | row39/slot2 | -689 | `d0d0385e61590d0256e6b50e781a32718b9921066a4190ee8a38feba8638de12` |
| slot3 sensitivity | row40/slot3 | -519 | `3914dcd2721ecf1263c37a9e909fc40475b5a08a90269d4c3b7542686f1ed216` |

All four sensitivity outputs differ from the baseline and are pairwise
distinct. This corrects the weakness of the A15.4 sparse copy/sum smoke model:
that model's final value 36 used only the first eight Interaction outputs and
therefore could not prove that each embedding independently affected the final
result. A15.6 changes no RTL or model shape; it programs the already supported
accepted trained-model weights and biases.

The generated compact model asset is 1,824 bytes with SHA256
`3493f7946d2b609d2c7b39dc585eae698447d62a4f0504d33e5e1aa7c5301335`.
It contains the five accepted descriptors, 1,360 weights, 73 biases and one
dense input. Its source SHA is embedded in the header and the source validator
checks the generated asset and all five table payloads.

## 8. Evidence schema

A future board run must retain JSON evidence containing:

- UTC timestamp and hostname;
- Git branch and HEAD;
- runtime-selected device index, exact BDF and other-device boundary;
- xclbin path, SHA256, UUID, kernel and CU;
- HBM bank/index, BO size and 64-bit physical address;
- payload transfer and TABLE_BASE readback status;
- each case's payload SHA, rows 37–40, expected/actual result, loaded mask,
  counters and completion state;
- programming and reset state;
- BO release, device close and global-cleanup state;
- board-functional and performance classification.

The schema deliberately permits BO physical address zero. The validator rejects
wrong xclbin SHA, UUID, BDF, HBM bank, payload SHA, missing actual result,
mismatched golden, malformed evidence, wrong counters, incomplete cleanup or a
performance claim.

## 9. Local verification

The Windows-only local preparation executed:

- Python syntax parsing for generator, source validator, evidence assembler and
  evidence validator: PASS;
- deterministic regeneration and byte-for-byte comparison of the compact model
  and five table payloads: PASS;
- accepted wrapper SHA check: PASS;
- model/table/source/runner protection-order validation: PASS;
- evidence assembler positive fixture: PASS;
- evidence validator positive fixture: PASS;
- legal zero physical-address fixture: PASS;
- eight requested negative fixtures: 8/8 PASS;
- `git diff --check`: PASS at local-test time.

Bash syntax is `NOT_RUN_WINDOWS_LOCAL_POLICY`; the Windows session did not
invoke WSL or a target shell. C++/XRT compilation is
`NOT_RUN_TARGET_ENV_REQUIRED` because local XRT 2020.2 headers/libraries are not
available. These states are not rewritten as PASS.

Local evidence is retained under
`docs/evidence/stage2n_a15_6/local_preparation_v1/`. It proves no FPGA behavior.
The retained small-file SHA256 manifest records:

| Evidence file | SHA256 |
|---|---|
| `a15_6_local_preparation_v1_status.txt` | `c284733e907ba0a5a26977e4249570ca90e79fa9101084ccf44b0f4dc8b68acc` |
| `golden_generation.log` | `cfe4941ae3a492599cb8b876d2cf85fb0bae071bfd508f8ccff035c9842d7795` |
| `source_validation.log` | `44438f6cbdf212146feaa2042a2b7b4cd5895bd502e8c9e40951f06e777fc164` |
| `validator_self_test.log` | `c98596e1db954467c88df2eb88e587ac206385b230e821c51d3e9197d87c6ac1` |
| `assembler_positive.log` | `086a937eae54ab72caa907b64a2ece4154031ab7fa0d04e1be1ab390e2e775c0` |

The companion `LOCAL_EVIDENCE_SHA256.txt` is the canonical local manifest.

## 10. Future board acceptance criteria

The protected board stage may report PASS only if all of these are present in
one validated evidence chain:

```text
FIXED_XCLBIN_IDENTITY=PASS
DEVICE_IDENTITY=PASS
FPGA_PROGRAMMING=PASS or SKIPPED_ALREADY_LOADED
HBM0_BO_ALLOCATION=PASS
PAYLOAD_TRANSFER=PASS
TABLE_BASE_PROGRAMMING=PASS
BASELINE_CASE=PASS
SLOT0_SENSITIVITY=PASS
SLOT1_SENSITIVITY=PASS
SLOT2_SENSITIVITY=PASS
SLOT3_SENSITIVITY=PASS
COMPLETE_DLRM_RESULT=PASS
BO_CLEANUP=PASS
PHYSICAL_HBM=PASS
BOARD_FUNCTIONAL=PASS
PERFORMANCE=NOT_CLAIMED
FPGA_RESET=NOT_RUN
OTHER_DEVICE_ACCESS=NONE
```

Any missing, malformed or mismatched field is FAIL/BLOCKED, not an inferred
PASS.

## 11. Performance boundary and limitations

The Host reads Bottom 322, Interaction 100, Top 744 and Total 1174 as functional
consistency evidence. These counters begin after the four sequential HBM reads.
They do not include lookup0+lookup1+lookup2+lookup3 and therefore do not measure
all-HBM end-to-end latency. Host wall time is also not accepted as a performance
metric in this stage.

```text
PERFORMANCE=NOT_CLAIMED
TRUE_ALL_HBM_E2E_PERFORMANCE=NOT_YET_MEASURED
```

A later performance stage must define one hardware-visible interval spanning
all four lookups plus Bottom, Interaction and Top before making latency,
bandwidth, throughput, energy, power or speedup claims.

Other explicit limitations:

- one F37X device and one guarded BDF only;
- one CU, one AXI master, one HBM bank and one outstanding read;
- no multi-bank/table, burst, cache, prefetch, INT8 embedding or model-size
  change;
- no device/server/network access occurred during this preparation;
- real Host compilation, FPGA programming, physical HBM and board function are
  still `NOT_RUN` until a separately authorized execution returns evidence.

## 12. Next action

The user first transfers the reviewed source through the Git-bundle workflow
and runs only the device-free target preflight. After its complete status is
returned and reviewed, a separate request may authorize the protected runner in
the controlled F37X environment. Codex does not perform either target action.
No physical HBM or board state may be marked PASS from source preparation or
target-preflight preparation alone.

## 13. Target-preflight separation

The next step is now explicitly split into two gates:

1. `A15_6_TARGET_PREFLIGHT`: a device-free user-run check in the established
   A15.5 build-only repository; and
2. `A15_6_PROTECTED_BOARD_EXECUTION`: a later separately authorized operation
   that may program/open the guarded FPGA and run the Host.

The versioned preflight entry is
`scripts/run_stage2n_a15_6_target_preflight_v1.sh`. It checks Git ancestry and
tracked cleanliness, the frozen RTL, XRT 2020.2 Host compilation, the existing
fixed-SHA xclbin and offline HBM[0] metadata, deterministic golden assets, and
the protection gate. It does not query a device, open XRT, allocate a BO, run
the Host, program/reset the FPGA, invoke `v++`, or rebuild XO/xclbin.

Local source validation of that preflight is PASS, but the actual target
preflight remains `NOT_RUN`. See
`docs/STAGE2N_A15_6_TARGET_PREFLIGHT_PREPARATION_V1.md` for the transfer,
evidence, and command boundary.
