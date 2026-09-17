# Stage 2N-A17.5B — Physical Validation Preparation V1

Date: 2026-09-08. Status: **LOCAL PHYSICAL-TEST READINESS ONLY**.

A17.5B prepares Host/BO/evidence structure for a later authorized F37X
four-bank run. It does not connect to a server, build an xclbin, program a
device, or change RTL, testbenches, Host, or the A17.2 ABI.

```text
A17_5B_LOCAL_PREPARATION=PASS
A17_5B_TARGET_XO_BUILD=NOT_RUN
A17_5B_TARGET_LINK=NOT_RUN
A17_5B_XCLBIN=NOT_RUN
A17_5B_PHYSICAL_HBM=NOT_RUN
A17_5B_PERFORMANCE=NOT_CLAIMED
RTL_MODIFIED=NO
TB_MODIFIED=NO
HOST_MODIFIED=NO
ABI_MODIFIED=NO
VPP_INVOKED=NO
XRT_RUN=NO
XBUTIL=NO
DEVICE_OPEN=NO
```

Paper language remains: A17 establishes a multi-bank-capable FPGA architecture
and verification framework. Physical test readiness is not multi-bank HBM
acceleration.

## 1. Current A17 state

| Layer | Status |
|---|---|
| A16.2 | Accepted physical single-bank baseline: `m_axi_gmem -> HBM[0]`, accounting `112/1174/1289/3` |
| A17.1–A17.3 | Local four-master RTL/XSim PASS; golden 36; A13 counters 322/100/744/1174 |
| A17.4 | Mapping proposal `gmemi -> HBM[i]`; current masters unmapped |
| A17.5A | Packaging audit; connectivity file is `PROPOSAL ONLY / NOT FOR v++` |
| A17.5B | This stage: Host/BO/evidence templates |
| A17.5C | Physical execution; **authorization required**; not started |

Host audit detail: `docs/STAGE2N_A17_5B_HOST_VALIDATION_PREP_V1.md`.
Connectivity proposal remains
`analysis/stage2n_a17_5/connectivity_a17_multibank_proposal.cfg`.

## 2. Future A17.5C test flow (not executed here)

User-controlled, after a reviewed A17 xclbin exists:

1. Offline: dump CONNECTIVITY, MEM_TOPOLOGY, IP_LAYOUT; require four used
   `HBM[0..3]` tags and CU `dlrm_a17_1`.
2. Protected device guards (index/BDF/render/UUID) as in A16.2; no FPGA reset.
3. Allocate BO0–BO3 by resolved mem index; record handle, group/mem index,
   tag, `paddr`.
4. Fail closed on duplicate bank, tag/index mismatch, or unaligned `paddr`.
5. `xclRegWrite` BASE0–BASE3 from the four paddrs; read back.
6. START at `0x300`; wait DONE; read A13 and A16 counters.
7. Compare function against the same five trained-model cases as A16.2.
8. Report lookup/e2e beside the A16.2 sequential baseline. Do not claim
   speedup from a single run or from XSim.
9. Release BOs; record post-release HBM usage.

Codex/Cursor must not perform steps 1–9.

## 3. Evidence requirements

Unpopulated templates:

- `docs/evidence/stage2n_a17_5/runtime_mapping_report.txt`
- `docs/evidence/stage2n_a17_5/board_run_summary.txt`
- `docs/evidence/stage2n_a17_5/latency_measurement.txt`

Each file is marked `UNPOPULATED TEMPLATE`. A later A17.5C import must replace
`NOT_RECORDED` fields with user-returned logs. Copied A16.2 numbers in those
templates would be a forge and are forbidden.

Required future fields include four-bank mapping, four BASE readbacks, five
case results, lookup/compute/e2e/residual, cleanup, and SHA of the xclbin
actually programmed. A16.2 remains the sequential comparison point, not an
A17 result.

## 4. Risks

- Four public AXI ports and an `analysis/` `sp` file are not four physical
  banks.
- `HBM[1..3]` tags exist in the A16.2 MEM_TOPOLOGY dump but have never been
  linked or allocated by this project.
- Hardcoding mem index `0` four times would silently stay on one bank.
- `paddr==0` is legal; do not treat it as allocation failure.
- XRT may round BO size (A16.2 requested 1024, properties reported 4096).
- Loading the A16 xclbin with an A17 Host would keep single-bank behavior.
- 100 MHz WNS is already 0.000 ns on A16.2; four SI may fail timing.
- Interconnect sharing can hide parallelism even with four `used` bits.
- A17.5B readiness must not be written as “physical four-bank PASS”.

## Evidence boundary

A17.5B proves only that the A16.2 Host control/BASE/latency path is understood,
that a four-BO metadata check plan exists on paper, and that empty evidence
templates exist. It cannot prove XO/xclbin validity, device mapping, physical
HBM[0..3] access, or any performance result.
