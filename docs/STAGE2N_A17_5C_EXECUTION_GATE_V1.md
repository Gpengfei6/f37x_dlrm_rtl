# Stage 2N-A17.5C — Execution Gate V1

Date: 2026-09-08. Status: **CHECKLIST ONLY**. This stage is not physical
execution.

A17.5C as authorized later is the only step that may produce physical
multi-bank evidence. This document is the pre-run gate. Codex/Cursor must not
connect to a server, open a device, invoke Vitis link, build an xclbin, or run XRT.

```text
A17_5C_EXECUTION_GATE=PREPARED
A17_5C_AUTHORIZATION=REQUIRED
A17_5C_TARGET_XO_BUILD=NOT_RUN
A17_5C_TARGET_LINK=NOT_RUN
A17_5C_XCLBIN=NOT_RUN
A17_5C_DEVICE=NOT_RUN
A17_5C_BO_MAPPING=NOT_RUN
A17_5C_KERNEL_RUN=NOT_RUN
A17_5C_LATENCY=NOT_RUN
A17_5C_PHYSICAL_MULTI_BANK_VALIDATION=NOT_RUN
A17_5C_PERFORMANCE=NOT_CLAIMED
RTL_MODIFIED=NO
TB_MODIFIED=NO
HOST_MODIFIED=NO
CONFIG_MODIFIED=NO
```

Paper language remains: A17 establishes a multi-bank-capable FPGA architecture
and verification framework. Do not write that multi-bank HBM acceleration was
achieved until every success criterion below is PASS on user-returned evidence.

## Build prerequisites

All items are currently **NOT_RUN**. A future user-controlled target build must
record:

| Check | Required identity | Current |
|---|---|---|
| Kernel XO | `package_xo` of `dlrm_f37x_rtl_kernel_stage2n_a17_v1`; four masters `m_axi_gmem0..3`; four pointer args `TABLE_BASE0..3` at `0x304/0x318/0x320/0x328`; 64-bit address, 128-bit data | **NOT_RUN** |
| xclbin | Non-empty hardware xclbin; SHA256/UUID retained; not the A16.2 artifact `5f0d6fef...` / `f18571de-...` | **NOT_RUN** |
| Platform | `inspur_f37x_xdma_201920_3` at `/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm`; part `xcvu37p-fsvh2892-2L-e`; 100 MHz | **NOT_RUN** |
| Connectivity | Live `config/` (not the `analysis/` proposal) with CU `dlrm_a17_1` and four `sp` lines below | **NOT_RUN** |

Proposed connectivity (still `PROPOSAL ONLY` under `analysis/`):

```text
sp=dlrm_a17_1.m_axi_gmem0:HBM[0]
sp=dlrm_a17_1.m_axi_gmem1:HBM[1]
sp=dlrm_a17_1.m_axi_gmem2:HBM[2]
sp=dlrm_a17_1.m_axi_gmem3:HBM[3]
```

## Runtime prerequisites

| Check | Required | Current |
|---|---|---|
| Device visible | Guarded index/BDF/render as in A16.2; one F37X card | **NOT_RUN** |
| XRT version | Recorded; A16.2 accepted `2.9.210507` | **NOT_RUN** |
| UUID match | Programmed xclbin UUID equals the retained A17 artifact | **NOT_RUN** |
| BO allocation | Four BOs; each mem/group index from `MEM_TOPOLOGY` tag `HBM[i]` | **NOT_RUN** |

## Mapping verification

Must confirm after CONNECTIVITY + `xclGetBOProperties`, not from the proposal
file:

| Master | Bank |
|---|---|
| `m_axi_gmem0` | `HBM[0]` |
| `m_axi_gmem1` | `HBM[1]` |
| `m_axi_gmem2` | `HBM[2]` |
| `m_axi_gmem3` | `HBM[3]` |

Four mem indexes must be distinct. BASE0–BASE3 readbacks must match the four
BO paddrs. `paddr==0` is legal.

## Success criteria

Announce **physical multi-bank validation** only when **all** of the following
are PASS on retained logs. Any one NOT_RUN or FAIL blocks the claim.

| Gate | Meaning |
|---|---|
| xclbin PASS | Exact-target A17 XO/link, four used `HBM[0..3]`, 100 MHz timing gate recorded |
| device PASS | Protected device identity, UUID match, no unauthorized reset |
| BO mapping PASS | Four unique banks as in the table above; metadata consistent |
| kernel run PASS | START/DONE; five functional cases; A13 counters unchanged |
| latency measured | `0x30C/0x310` plus A13 totals reported beside A16.2 `112/1174/1289/3` |

Latency measured is not “latency improved”. Compute remaining the bottleneck
does not fail mapping if the four-bank map itself PASS.

## Authorization

`Ready: AUTHORIZED EXECUTION ONLY`. A later explicit user yes, on the
controlled target, is required before A17.5C execution. This checklist is not
that authorization.
