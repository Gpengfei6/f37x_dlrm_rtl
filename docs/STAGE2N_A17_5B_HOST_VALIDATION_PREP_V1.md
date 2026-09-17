# Stage 2N-A17.5B — Host Validation Preparation V1

Date: 2026-09-08. Status: **LOCAL HOST AUDIT / PLAN ONLY**. Not a Host
implementation and not a board result.

This document audits the accepted A16.2 Host path and records what a future
A17 Host must add. It does not modify `host/stage2n_a16_2_physical_latency_v1.cpp`
and does not add `host/*a17*`.

## 1. A16.2 Host path (current implementation)

Source: `host/stage2n_a16_2_physical_latency_v1.cpp`. Runtime is user-managed
XRT 2020.2 HAL: `xclOpen` / `xclIPName2Index` / `xclOpenContext`, then
`xclRegWrite` / `xclRegRead`. There is no OpenCL `setArg`.

| Step | A16.2 behavior |
|---|---|
| CU | `dlrm_f37x_rtl_kernel_stage2n_a16_v1:dlrm_a16_1` |
| BO | one `xclAllocBO(size=1024, flags=0, mem_index=0)` |
| Metadata | `xclGetBOProperties`; `flags & 0x00FFFFFF` must be mem index 0; `paddr` 16-byte aligned; `paddr==0` is legal |
| CONTROL | `0x300` `A15_CMD_START=1`, `A15_CMD_CLEAR=2` |
| BASE write | `paddr` split to `0x304` / `0x308`, then readback |
| Latency | `0x30C` lookup, `0x310` FPGA e2e, plus A13 `0x218/0x21C/0x220/0x224` |
| Version | `0x184` must be `0x00024E13` |

XRT may report `properties.size=4096` for a 1024-byte request. Future A17
evidence must print both requested size and `properties.size` per BO.

## 2. Future A17 Host mapping (not implemented)

Keep `xclRegWrite`. Do not switch to `setArg`.

```text
BO0  -->  BASE0  0x304/0x308  -->  m_axi_gmem0  -->  HBM[0]
BO1  -->  BASE1  0x318/0x31C  -->  m_axi_gmem1  -->  HBM[1]
BO2  -->  BASE2  0x320/0x324  -->  m_axi_gmem2  -->  HBM[2]
BO3  -->  BASE3  0x328/0x32C  -->  m_axi_gmem3  -->  HBM[3]
```

START remains `0x300` `A15_CMD_START` after all four bases read back.
Version check becomes `0x00024E17`. CU becomes
`dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1`. Reject an A16 xclbin.

Mem index must be resolved from xclbin `MEM_TOPOLOGY` `m_tag`, not hardcoded
`0,1,2,3`. In the A16.2 dump those tags happened to be indexes 0–3; that is
not a contract.

## 3. BO metadata check plan (not implemented)

For each of BO0–BO3, after `xclAllocBO` / `xclGetBOProperties`:

```text
BO handle  -->  mem index / group id  -->  HBM[tag]  -->  paddr  -->  BASE write/readback
```

Pass only if:

- four handles are distinct and non-null;
- four mem indexes are distinct;
- tags are exactly `HBM[0]`..`HBM[3]` in that BO order;
- CONNECTIVITY `arg_index` i matches `TABLE_BASEi` / `m_axi_gmemi` / that tag;
- each BASE readback equals that BO `paddr`;
- all four paddrs are 16-byte aligned.

Fail modes to encode later (A17.5C Host, not now):

| Failure | Detection |
|---|---|
| All four BOs land on one bank | duplicate mem index or duplicate `HBM[0]` tag |
| Metadata disagree | Host mem index ≠ CONNECTIVITY `mem_data_index` for that arg |
| Address written wrong | BASE readback ≠ `paddr`, or BASE i gets BO j |
| Hardcoded index 0 for every BO | four allocations with `mem_index==0` |
| A16 xclbin | IP name still `dlrm_a16_1` or one used HBM bank |

`group id` in newer XRT C++ is the same integer the HAL exposes as
`xclBOProperties.flags` bits `[23:0]`. A17.5B does not call XRT.

## 4. Boundary

A17.5B does not compile Host, open a device, or print live BO handles.
Templates under `docs/evidence/stage2n_a17_5/` are unpopulated.
