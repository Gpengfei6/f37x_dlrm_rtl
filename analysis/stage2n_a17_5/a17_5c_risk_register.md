# A17.5C risk register

Date: 2026-09-08. Status: **PLAN ONLY**. Not a board result.

These risks apply to a future authorized A17.5C run. None of them has been
observed on hardware in this stage.

## 1. Connectivity did not take effect

`analysis/` `sp` lines are not live Vitis link-config input. If the xclbin CONNECTIVITY
section still has one `m_axi_gmem -> HBM[0]` connection, the kernel is still
the A16 sequential shape even if RTL has four ports.

## 2. Four interfaces land on the same bank

Host may allocate four BOs with `mem_index=0`. Metadata would then show four
handles and one tag `HBM[0]`. Treat duplicate tags/indexes as FAIL, not as
four-bank PASS.

## 3. BO group / mem-index anomaly

XRT 2020.2 HAL group id is `xclBOProperties.flags[23:0]`. It may not equal the
integer `N` in `HBM[N]` on a future xclbin. Resolve from `MEM_TOPOLOGY` `m_tag`.
`properties.size` may round up (A16.2: request 1024, report 4096).

## 4. UUID mismatch

Programming the frozen A16.2 xclbin (`f18571de-4a43-46bd-8ab9-a89dd4b11f8e`)
with an A17 Host keeps single-bank behavior. Require IP name
`dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1` and the A17 UUID.

## 5. Latency does not drop

A16.2 lookup is `112/1289 ≈ 8.7%` of FPGA e2e. Four-bank mapping can be correct
while e2e stays close to 1289 cycles. That is a measurement outcome, not proof
that connectivity failed. Do not require e2e reduction to declare mapping PASS.

## 6. Compute remains the bottleneck

A16.2 compute is `1174/1289 ≈ 91%`. A13 counters 322/100/744/1174 are frozen.
A17.5C must still report them. Reducing lookup does not move the dense engine.
A18/A19 compute work is a separate authorization.

## Disposition

A17.5C execution remains `AUTHORIZED EXECUTION ONLY`. This register does not
authorize server, `v++`, XRT, or board access.
