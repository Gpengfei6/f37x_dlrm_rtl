# Stage 2N-A17.2 — Four-master public-kernel XSim V1

Date: 2026-09-08. Status: **LOCAL XSIM PASS** (A17.3 public-port regression).

## Objective

A17.2 places the accepted A17.1 four-port lookup and unchanged A13 compute
pipeline behind a separately versioned public RTL-kernel boundary. The local
proof must exercise only the public AXI4-Lite and four AXI4 memory interfaces.
It does not modify or replace any accepted A13 through A17.1 source.

The public top is:

`dlrm_f37x_rtl_kernel_stage2n_a17_v1`

It exposes one `s_axi_control` interface and four independent read-only AXI4
masters named `m_axi_gmem0` through `m_axi_gmem3`. Each master retains the
accepted A14 v2 contract: 64-bit byte address, 128-bit data, one single-beat
read, and at most one outstanding request per port. The public write channels
are present for packaging compatibility and are tied inactive.

A17.3 is the XSim regression of this public top. It does not start A18, does
not package an XO/xclbin, and does not access F37X.

## Preserved and extended ABI

The complete accepted A13 register map through `0x224` is unchanged. A17.2
also preserves the following A15/A16 meanings:

| Address | Access | Meaning |
|---|---:|---|
| `0x300` | R/W command | A15 START/CLEAR and status |
| `0x304` | R/W while idle | HBM port 0 table-base low word |
| `0x308` | R/W while idle | HBM port 0 table-base high word |
| `0x30C` | R | first successful AR through group injection completion |
| `0x310` | R | accepted START through first final-result visibility |
| `0x314` | R; writes rejected | reserved and reads as zero |
| `0x318` | R/W while idle | HBM port 1 table-base low word |
| `0x31C` | R/W while idle | HBM port 1 table-base high word |
| `0x320` | R/W while idle | HBM port 2 table-base low word |
| `0x324` | R/W while idle | HBM port 2 table-base high word |
| `0x328` | R/W while idle | HBM port 3 table-base low word |
| `0x32C` | R/W while idle | HBM port 3 table-base high word |

All base writes apply AXI-Lite `WSTRB`. An accepted START atomically snapshots
all four staging bases for that job, so later staging writes cannot alter an
active address. Base writes while the A15 sequencer is outside IDLE are
rejected with the existing wrapper error mechanism. The A17 pipeline version
word is `0x00024E17`.

## Data and control path

On an accepted START, the wrapper supplies the four captured bases to the
accepted A17.1 integration. The integration requests rows 37, 38, 39 and 40 on
ports 0, 1, 2 and 3 respectively. AR handshakes proceed independently; no
logic requires all four `ARREADY` signals on the same cycle. Responses may
return in any order or simultaneously. The controller retains every successful
128-bit row, waits for the group to finish, and commits slots 0 through 3 over
the unchanged single A13 embedding configuration port.

Any address or response fault prevents all A13 embedding commits for that
group. The controller consumes the other issued single-beat responses before
publishing the retained error. CLEAR acknowledges the failure and returns the
wrapper to IDLE only after the controller recovery handshake. A successful
group grants one fresh compute START; the retained A13 loaded mask cannot
authorize a stale rerun.

## Counter contract

The A16 inclusive event definitions are retained. Let `S` be the accepted A15
START write, `A` the first successful AR handshake on any of the four ports,
`D` the completion of the four-slot injection group, `C` the accepted A13
compute START, and `F` the first final-result visibility:

`lookup = D - A + 1`

`compute = F - C + 1`

`end_to_end = F - S + 1`

The lookup counter starts once per job from the OR of the four public AR
handshakes. Both added counters saturate, retain their completed value until a
new accepted START or reset, and stop on their specified terminal event.

## Verification Result

Local Vivado/XSim 2022.1, SW Build 3526262, on 2026-09-08. Parent HEAD at the
run was `e4ce2ab59b594910003c20fc00174b3a465e9bca`. Tool return codes are
`XVLOG_RC=0`, `XELAB_RC=0`, `XSIM_RC=0`. `WARNING_COUNT=0`. The self-checking
public-port bench finished at `524330 ns` with
`STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1_PASS`.

| Gate | Result |
|---|---|
| compile PASS | **PASS** |
| simulation PASS | **PASS** |
| four AXI PASS | **PASS** (`m_axi_gmem0..3` `ARVALID` together) |
| reorder PASS | **PASS** (R order 2, 0, 3, 1) |
| stall PASS | **PASS** (port 1 `ARREADY`/`RREADY` held low; ports 0/2/3 completed) |
| error PASS | **PASS** (`RRESP=SLVERR`, four-response drain, CLEAR recovery) |
| restart PASS | **PASS** (START/DONE, START/DONE, no DUT reset) |

Functional observations from the same run:

- pipeline version `0x00024E17`; reserved `0x314` reads zero and rejects writes;
- four 64-bit bases programmed with split AW/W and partial `WSTRB`;
- all four AR handshakes completed before the first R beat on the success path;
- Host embedding writes remain rejected; busy START and busy base writes are
  rejected without changing the captured request addresses;
- two identical public-port inferences match golden result `36`;
- accepted A13 counters remain `322/100/744/1174`;
- fake-memory lookup/e2e/overhead = `24/1256/58` cycles. These are not physical
  HBM latency and are not compared with the accepted A16.2 `112/1174/1289/3`
  board baseline.

The first xvlog attempt failed because the public testbench still used A16
single-master connections and part-selects on function returns. The adapter
also still instantiated the sequential A15.3 integration. Those A17-only
defects were corrected before the passing rerun. Frozen A13/A14/A15/A16/A17.1
files were not modified.

## Evidence

Compact tracked evidence:

- `docs/evidence/stage2n_a17_2/xsim.log`
- `docs/evidence/stage2n_a17_2/compile.log`
- `docs/evidence/stage2n_a17_2/run_summary.txt`
- `docs/evidence/stage2n_a17_2/manifest.txt`

The unique local result directory retained by the runner is
`results/stage2n_a17_2/20260908_161448_982/`.

## Evidence boundary

This stage proves a public four-master RTL/XSim architecture baseline. It
cannot prove XO packaging, Vitis link, target timing, physical HBM bank
placement, physical latency, bandwidth, throughput, speedup, power or energy.
Four public AXI ports in RTL are a prerequisite for a later four-bank target,
not evidence that an xclbin contains four distinct HBM connections.

The accepted physical comparison point remains the A16.2 single-master,
HBM[0], sequential baseline: lookup/compute/end-to-end/residual
`112/1174/1289/3` cycles at the requested 100 MHz. No A17 performance claim is
made from fake-memory simulation.

## A17.2 Final Acceptance State

Accepted source and evidence commit:

`beff282629a02300965a1fb0fbf2cb1e835903e7` (`beff282`)

| Public-kernel gate | Result |
|---|---|
| four AXI master | **PASS** (`m_axi_gmem0..3`, independent AR/R) |
| unordered response | **PASS** (R order 2, 0, 3, 1; no deadlock) |
| stall isolation | **PASS** (port 1 held; ports 0/2/3 completed) |
| error drain | **PASS** (`RRESP=SLVERR`, group drain, CLEAR recovery) |
| restart | **PASS** (START/DONE then START/DONE, no DUT reset) |

The AXI-Lite map `0x300` through `0x32C` is frozen. `0x300` remains the A15
START/CLEAR window; `0x304`/`0x308` remain BASE0; `0x30C`/`0x310` remain the
A16 inclusive counters; `0x314` remains reserved; `0x318` through `0x32C`
remain BASE1–BASE3 low/high. There is no BASE4 register.

Post-validation naming audit of the A17.2 files only (kernel, public TB, and
A17.2 runners) found no `a15_table_base` signal, no A15.2 sequential path, and
no A16.1 PASS marker. Remaining `ADDR_A15_*`, `A15_CMD_*`, and `a15_state*`
identifiers name the preserved `0x300` sequencer window. They are not a
functional A15.2/A16.1 lookup path and were left unchanged so the accepted
XSim result at `beff282` is not disturbed.

This record does not start A17.4 target HBM mapping, A18, XO/xclbin generation,
or board execution.
