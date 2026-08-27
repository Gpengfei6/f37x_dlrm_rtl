# Stage 2N-A15.4 F37X Kernel All-HBM Pipeline XSim V1

## 1. Status and objective

- Date: 2026-08-27
- Branch: `work/stage2n-a15-hbm-pipeline-integration`
- Starting HEAD and authorization commit:
  `7d0c3519c29b2dd07e0615dc98ba7060d728bc4f`
- Authorization subject:
  `docs(stage2n): authorize A15.4 local F37X kernel integration`
- Result: **LOCAL VIVADO 2022.1 XSIM PASS**

A15.4 adds a new versioned public F37X-style kernel boundary around the
accepted A15.3 controller. Software configures the accepted A13 model state and
a 64-bit HBM table base through AXI4-Lite, then writes one A15 START command.
One accepted A14 v2 lookup engine issues four sequential reads for canonical
rows 37 through 40, injects the four results into accepted A13 embedding slots
0 through 3, waits for the loaded mask to reach `4'hF`, and starts the unchanged
Bottom–Interaction–Top pipeline. The final result and A13 counters remain
visible at their accepted addresses.

This is a local fake-AXI-memory proof. It is not target build, xclbin, physical
HBM, FPGA, board, or performance evidence.

## 2. Source audit

### 2.1 Accepted A13 public boundary and register map

The accepted A13 top exposes only its AXI4-Lite slave at
`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv:12-40`. It preserves the
legacy A2 control windows and delegates the pipeline window to the accepted A13
adapter instantiated at line 286.

The complete accepted pipeline register map is defined in
`rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv:67-154`:

| Address | Accepted A13 meaning |
|---:|---|
| `0x180` | pipeline control/status |
| `0x184` | version |
| `0x188` | result count |
| `0x18C` | phase counts |
| `0x190` | descriptor index |
| `0x194`–`0x19C` | descriptor words 0–2 |
| `0x1A0` | activation buffer select |
| `0x1A4` | activation chunk index |
| `0x1A8` | activation lane mask |
| `0x1B0`–`0x1CC` | activation data words 0–7 |
| `0x1D0` | embedding index |
| `0x1D4`–`0x1E0` | embedding data words 0–3 |
| `0x1E4` / `0x1E8` | weight address/data |
| `0x1EC` / `0x1F0` | bias address/data |
| `0x1F4` | Bottom descriptor-segment configuration |
| `0x1F8` | Top descriptor-segment configuration |
| `0x1FC` | pipeline/interaction configuration |
| `0x200` / `0x204` / `0x208` | result data/index/meta |
| `0x20C` | embedding loaded mask |
| `0x210` | error code |
| `0x214` | configuration-ready status |
| `0x218` | Bottom cycles |
| `0x21C` | Interaction cycles |
| `0x220` | Top cycles |
| `0x224` | Total cycles |

The four counter readbacks are implemented at lines 893–900 of that adapter.
A15.4 mirrors this map without moving or redefining any accepted address.

### 2.2 Accepted A14 v2 interface and address behavior

The accepted A14 v2 wrapper exposes a 64-bit-address, 128-bit-data
`m_axi_gmem` interface at
`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv:64-105`. Its private
AXI4-Lite map uses `0x000`, `0x010`, `0x018`, `0x01C`, and `0x020`–`0x02C`
at lines 108–123. Those addresses conflict with the accepted legacy/A13 public
map, so A15.4 does not copy the A14 control map.

The actual accepted lookup engine is
`rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`. It owns the calculation

```text
read_address = TABLE_BASE + (lookup_index << 4)
```

at lines 72–74, exposes one ready/valid request and response at lines 20–29,
and drives a one-beat AXI read (`ARLEN=0`, 16-byte `ARSIZE`) at lines 76–92.

### 2.3 Accepted A15.3 ownership

`rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv` is reused
unchanged. Its public integration ports begin at line 10; the runtime
`table_base_addr` and load-all request are lines 120–122. It owns:

- the fixed row sequence 37, 38, 39, 40;
- request launch and response acceptance at lines 229–235 and 282–294;
- successful response retention and slot injection;
- error slot/index retention and stop-on-error behavior;
- the `4'hF` gate around the accepted pipeline START at lines 240–249;
- the one accepted A14 v2 lookup instance at lines 327–364;
- the accepted A13 cycle-counter controller instance starting at line 366.

The four default row parameters are lines 34–37 and their slot-to-row selection
function is lines 192–203. Response/error capture and slot advancement are lines
273–315.

Therefore A15.4 needs only a public register/control wrapper. It does not
duplicate the A14 control ABI, add lookup engines, or alter accepted A15.3.
The fixed rows are sufficient for this deterministic integration proof, so no
programmable-row registers were added.

## 3. Architecture and reuse boundary

```text
AXI4-Lite slave
       |
       v
A15.4 public kernel + command FSM
       |
       +-- accepted A2/A13 model and result register behavior
       |
       +-- accepted A15.3 four-row controller
              |
              +-- one accepted A14 v2 lookup engine
              |          |
              |          +-- one m_axi_gmem read master
              |
              +-- accepted A13 cycle-counter pipeline
                         |
                         +-- result + 0x218/0x21C/0x220/0x224
```

New RTL:

- public module `dlrm_f37x_rtl_kernel_stage2n_a15_v1` at
  `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv:12`;
- its versioned AXI-Lite/control adapter at line 404;
- the accepted A15.3 instance at line 1600.

The public master interface is one 64-bit-address, 128-bit-data AXI4 master.
Write channels are tied inactive at lines 332–346. Only the accepted lookup's
single-outstanding, one-beat read channel is active.

Protected files modified: **none**. Accepted A13, A14 v2, A14.7, A15.1, A15.2,
and A15.3 source, tests, runners, documents, and retained evidence are unchanged.

## 4. A15.4 AXI-Lite ABI

A15.4 preserves every accepted A13 address above and adds only this disjoint
window (`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv:573-579`):

| Address | Name | Access | Meaning |
|---:|---|---|---|
| `0x300` | `A15_CONTROL_STATUS` | write/read | write `0x1` START; write `0x2` CLEAR; read status |
| `0x304` | `A15_TABLE_BASE_LO` | write/read | staged table base bits `[31:0]` |
| `0x308` | `A15_TABLE_BASE_HI` | write/read | staged table base bits `[63:32]` |

START/CLEAR values are defined at lines 591–592. TABLE_BASE writes are accepted
only in IDLE at lines 1426–1446. A successful START snapshots the table base and
accepted Bottom/Top/pipeline configuration before loading begins at lines
926–945. Readback is implemented at lines 1583–1588.

`A15_CONTROL_STATUS` reports active, HBM sequence busy, all-loaded, A13 busy,
done, error, START-ready, result-valid, loaded mask, error slot/index, injection
state, accepted-controller readiness, and the A15 FSM state. The exact bit
assignment is in lines 883–907; software must treat unlisted bits as reserved.

The accepted A13 public ABI remains available, including model programming,
result retirement, error handling, and counter reads. Host embedding commits
are deliberately consumed and rejected by the unchanged A15.3 ownership path;
they cannot overwrite the four HBM-owned slots.

## 5. Command FSM and error semantics

The kernel-level FSM is defined at lines 601–610 and implemented at lines
911–994:

```text
IDLE -> LOAD_REQUEST -> LOAD_WAIT -> PIPE_START -> PIPE_WAIT -> DONE
                         |                         |
                         +-----------> ERROR <----+
                                         |
                                      RECOVER
                                         |
                                        IDLE
```

Behavior:

1. IDLE accepts A15 START only after the accepted model/configuration channels,
   A15.3 load-all interface, result path, and error paths are ready.
2. LOAD_REQUEST performs exactly one load-all handshake.
3. A15.3 sequentially requests rows 37–40 and sets each slot loaded only after
   the accepted A13 embedding configuration handshake.
4. PIPE_START is reachable only after `hbm_all_loaded`, therefore before the
   loaded mask reaches `4'hF` the pipeline cannot start.
5. PIPE_WAIT terminates in DONE on accepted A13 completion or ERROR on accepted
   pipeline error.
6. Lookup error terminates loading, preserves prior successful slots, does not
   load the failing slot, issues no later row request, and never starts A13.
7. Repeated START while busy does not replace the active request or captured
   table base; it is exposed as a wrapper error while the active sequence
   continues.
8. CLEAR acknowledges DONE/ERROR and returns through RECOVER where necessary.
9. Reset clears staged A15 state, busy/done/error state, loaded bits, and
   outstanding control state.

There is no silent retry.

## 6. Canonical table, addresses, and packing

The runner and testbench validate rows against tracked
`models/stage2n_a14_embedding_table.json`; expected values are not copied from
an old test summary. The test uses:

```text
TABLE_BASE = 0x0000000123456000
row value  = row * 8 + lane - 256
```

| Slot | Row | AXI address | Observed lanes 0–7 |
|---:|---:|---:|---|
| 0 | 37 | `0x0000000123456250` | `[40,41,42,43,44,45,46,47]` |
| 1 | 38 | `0x0000000123456260` | `[48,49,50,51,52,53,54,55]` |
| 2 | 39 | `0x0000000123456270` | `[56,57,58,59,60,61,62,63]` |
| 3 | 40 | `0x0000000123456280` | `[64,65,66,67,68,69,70,71]` |

Packing is unchanged and bit-exact:

```text
[15:0] lane0, [31:16] lane1, [47:32] lane2, [63:48] lane3,
[79:64] lane4, [95:80] lane5, [111:96] lane6, [127:112] lane7
```

No byte swap, word swap, or lane reorder occurs.

## 7. Public-port self-checking testbench

`tb/tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv` drives only public AXI4-Lite
and `m_axi_gmem` ports. It does not use hierarchical force/poke. Its AXI-Lite
transactions begin at line 324 and its fake AXI-memory service begins at line
458. The memory service checks the expected base-plus-row address, one-beat
control, address stability while ARREADY is delayed, returned row/lane data,
and loaded-mask progression.

Positive coverage:

- TABLE_BASE low/high programming and readback;
- one START and exactly four sequential canonical requests;
- exactly four AR handshakes, four successful R handshakes, and four slot
  injections;
- lane packing and final loaded mask `4'hF`;
- no accepted A13 pipeline start before all four slot commits;
- complete Bottom–Interaction–Top execution;
- independent golden 36 equals actual final result 36;
- unchanged A13 public register behavior and counter addresses;
- final result retention during AXI-Lite Host polling/backpressure.

Negative coverage:

- reset returns to clean IDLE;
- slot0 read error leaves mask zero and makes no later request;
- slot2 read error preserves slots0–1, leaves slot2 unloaded, makes no slot3
  request, and does not start the pipeline;
- repeated START during delayed ARREADY is rejected without replacing the
  active sequence;
- delayed ARREADY holds address/control stable;
- delayed RVALID leaves the sequence waiting correctly;
- Host embedding commits cannot overwrite HBM-owned slots0–3;
- errors require explicit acknowledgement and are not silently retried.

The response-retention/config-ready property is inherited unchanged from the
accepted A15.3 module and its independent delayed-ready test. The A15.4 public
ABI intentionally exposes no test-only signal with which to deassert the
internal accepted A13 embedding-config ready. Therefore this kernel-level TB
records structural reuse (`A15_4_RESPONSE_RETENTION_REUSED=PASS`) rather than
using prohibited hierarchical force/poke or adding a non-production debug port.

## 8. XSim method and actual result

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts\run_stage2n_a15_4_kernel_xsim_v1.ps1
```

The runner compiles 18 explicit sources, guards accepted files against the
authorization baseline, checks the tracked canonical table, requires each PASS
marker exactly once, parses measured counts/results, and scans the retained logs
for warnings, errors, fatals, and assertion failures.

| Item | Actual result |
|---|---:|
| Vivado/XSim | 2022.1, SW Build 3526262 |
| `xvlog` / `xelab` / `xsim` RC | `0 / 0 / 0` |
| Warning / error / fatal / assertion-failure count | `0 / 0 / 0 / 0` |
| Lookup requests | 4 |
| AR handshakes | 4 |
| Successful R handshakes | 4 |
| Slot injections | 4 |
| Final loaded mask | `0xF` |
| Golden / actual result | `36 / 36` |
| Bottom cycles | 322 |
| Interaction cycles | 100 |
| Top cycles | 744 |
| Total cycles | 1174 |
| Simulation completion time | 452,720 ns |

The four cycle values are the accepted A13 compute-stage counters. They start
at accepted A13 pipeline START, after the four fake-memory lookups, and therefore
are not HBM end-to-end latency, all-request latency, physical-HBM latency, or
total kernel latency.

Final marker:

```text
STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1_PASS
```

## 9. Retained evidence

Local generated evidence, intentionally not staged for Git:

- `results/stage2n_a15_4/status.txt`
- `results/stage2n_a15_4/xvlog.log`
- `results/stage2n_a15_4/xelab.log`
- `results/stage2n_a15_4/xsim.log`
- `results/stage2n_a15_4/command_transcript.txt`

Final `status.txt` SHA256:

```text
7156f67dc250e21ce5b4eab44074a472090e7579e5217180234027c90e1be8d8
```

## 10. Exact source changes

Created:

- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv`
- `scripts/run_stage2n_a15_4_kernel_xsim_v1.ps1`
- `scripts/run_stage2n_a15_4_kernel_xsim_v1.tcl`
- `docs/STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1.md`

Updated after PASS:

- `docs/CURRENT_STATE.md`
- `docs/AI_CONTEXT.md`
- `docs/DECISIONS.md`
- `docs/STAGE_HISTORY.md`

Generated `results/stage2n_a15_4/` files are evidence artifacts and are not part
of the source commit.

## 11. Limitations and evidence boundary

A15.4 proves locally:

- one public AXI4-Lite plus `m_axi_gmem` kernel composition;
- one accepted A14 v2 engine, one read master, and four sequential logical
  lookups;
- exact fake-memory addresses, lane data, four-slot injection, loaded-mask
  gating, error/busy/reset/Host-ownership behavior;
- complete accepted A13 inference and independent result match;
- unchanged A13 public and cycle-counter ABIs.

A15.4 does **not** prove:

- target synthesis, implementation, timing, packaging, or link;
- XO or xclbin generation or validity;
- physical HBM access, latency, bandwidth, or throughput;
- FPGA programming, F37X board execution, or Host runtime behavior;
- multiple banks, AXI masters, lookup engines, outstanding requests, bursts,
  caching, prefetching, multiple tables, INT8, or a different model size;
- performance, power, energy, speedup, or GPU comparison.

Network, server, and FPGA-device access were all `NONE`.

## 12. Next-stage recommendation

Treat this local A15.4 result as the source/functional gate for a separately
authorized A15.5 target packaging and link-preparation stage. That future gate
must preserve the accepted A13 ABI and the A15.4 `0x300`–`0x308` control ABI,
and must not promote target or physical-HBM claims without returned evidence
from the user-controlled environment.
