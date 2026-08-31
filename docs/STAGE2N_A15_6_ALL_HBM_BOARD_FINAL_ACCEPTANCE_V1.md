# Stage 2N-A15.6 All-HBM Board Final Acceptance V1

Date: 2026-08-31

## 1. Final conclusion

Stage 2N-A15.6 is accepted as the first complete physical-board functional
baseline in this repository where all four embedding slots are supplied by
physical `HBM[0]` and consumed by the accepted Bottom–Interaction–Top pipeline.

```text
A15_6_FINAL_ACCEPTANCE=PASS
A15_6_FIXED_XCLBIN_IDENTITY=PASS
A15_6_DEVICE_IDENTITY=PASS
A15_6_FPGA_PROGRAMMING=PASS
A15_6_HBM0_BO_ALLOCATION=PASS
A15_6_PAYLOAD_TRANSFER=PASS
A15_6_TABLE_BASE_PROGRAMMING=PASS
A15_6_COMPLETE_DLRM_RESULT=PASS
A15_6_BO_CLEANUP=PASS
A15_6_PHYSICAL_HBM=PASS
A15_6_BOARD_FUNCTIONAL=PASS
A15_6_IMPORTED_EVIDENCE_VALIDATION=PASS
A15_6_PERFORMANCE=NOT_CLAIMED
FPGA_RESET=NOT_RUN
OTHER_DEVICE_ACCESS=NONE
FROZEN_RTL_MODIFIED=NO
FROZEN_ASSETS_MODIFIED=NO
XCLBIN_REBUILT=NO
READY_FOR_A16_PREPARATION=YES
```

The conclusion is based on the imported server-generated JSON and runner/Host
logs plus compact summaries derived from the pre/post device queries and xclbin
information. The byte-exact originals remain in the retained archive. The local
offline validator was rerun against the imported JSON and tracked manifest.

## 2. Stage development relationship

- A15.1 connected one A14 v2 lookup response to A13 embedding slot 0 locally.
- A15.2 proved one complete local inference through that slot-0 path.
- A15.3 sequenced one lookup engine across rows 37–40 and injected slots 0–3.
- A15.4 exposed that accepted path through one public AXI4-Lite kernel and one
  64-bit-address/128-bit-data `m_axi_gmem` read master.
- A15.5 packaged and linked the exact F37X target, froze the XO/xclbin and
  accepted 100 MHz routed timing.
- A15.6 added the protected XRT Host, deterministic five-case golden contract,
  device guards, evidence assembly/validation and the real F37X execution.

No A13/A14/A15.1–A15.5 frozen RTL or arithmetic contract was changed by this
acceptance.

## 3. Accepted architecture

The accepted physical path is:

```text
physical HBM[0]
  -> one AXI read master
  -> four sequential logical lookups (rows 37, 38, 39, 40)
  -> embedding slots 0, 1, 2, 3
  -> Bottom MLP
  -> Feature Interaction
  -> Top MLP
  -> final DLRM result
```

This is one HBM bank, one AXI read master and four sequential lookups. It is not
a multi-bank or parallel-lookup architecture.

## 4. Target and tool identity

| Item | Accepted value |
|---|---|
| Device index | `2` |
| BDF | `0000:9b:00.1` |
| Render node | `/dev/dri/renderD129` |
| Device | `xcvu37p-fsvh2892-2L-e` |
| Platform | `inspur_f37x_xdma_201920_3` |
| XRT | `2.9.210507` |
| HBM bank | `HBM[0]` |

The pre/post query evidence identifies the same platform and XRT version. Only
the explicitly selected BDF/device was used.

## 5. Frozen implementation identity

| Item | Accepted value |
|---|---|
| Board-execution source HEAD | `85ac9d1c333d5e016341c57de722e222da991d97` |
| Accepted A15.4 RTL SHA256 | `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1` |
| XO SHA256 | `a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019` |
| xclbin SHA256 | `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356` |
| xclbin UUID | `1b555645-a9e2-4f5e-95af-6ce4adacbc3c` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a15_v1` |
| Compute unit | `dlrm_a15_1` |
| Connectivity | `dlrm_a15_1.m_axi_gmem:HBM[0]` |
| Kernel clock | 100 MHz |

The accepted A15.5 xclbin was consumed without XO rebuild, relink or xclbin
replacement.

## 6. Target preflight and protected execution gates

Before the protected run, the user-controlled target preflight completed the
xclbin `CONNECTIVITY`, `MEM_TOPOLOGY` and `IP_LAYOUT` extraction, XRT 2020.2
Host build and API probe. Three environment-compatibility defects were corrected
without RTL or artifact changes: old-Git command selection, deterministic
repo-relative golden source path and entry-time freezing of `SELF_SCRIPT` before
XRT setup.

The returned board package does not include a separate preflight status file;
those preflight results are user-returned target evidence. The board runner
independently repeated the source/asset checks and exact xclbin, UUID,
kernel/CU, device and HBM guards before any device-changing action.

The original resident design was:

```text
UUID=e4346e48-1644-484b-8548-e2cc9eb22a8b
CU=single_cmac_endpoint:single_cmac_endpoint_1
STATUS=IDLE
```

Replacement occurred only after the design/device passed the explicit allowlist
and the user entered literal `yes`. The runner records `xbutil program`
success. It did not reset the FPGA and did not access another device.

## 7. Physical BO and TABLE_BASE

| Item | Result |
|---|---|
| BO bank | `HBM[0]` / memory index 0 |
| BO size | 4096 bytes |
| BO physical address | `0x0000000000000000` |
| Payload transfer | PASS |
| TABLE_BASE programming/readback | PASS for all five cases |
| BO release | PASS |
| Device close | PASS |
| Global HBM cleanup | NOT RUN |

The physical BO address `0x0` is valid for this `HBM[0]` allocation. It is a
real value returned by XRT and successfully used as TABLE_BASE; it is not a null
pointer or allocation-failure indication. Each case read back TABLE_BASE low/high
as `0x00000000/0x00000000` and completed successfully.

The post-Host query records `HBM[0]` at `0 Byte / 0 BO`, consistent with the
JSON cleanup fields.

## 8. Five physical-board cases

| Case | Purpose | Expected | Actual | Loaded mask | Result |
|---|---|---:|---:|---|---|
| 0 | baseline | -393 | -393 | `0xF` | PASS |
| 1 | slot0 sensitivity | -392 | -392 | `0xF` | PASS |
| 2 | slot1 sensitivity | -93 | -93 | `0xF` | PASS |
| 3 | slot2 sensitivity | -689 | -689 | `0xF` | PASS |
| 4 | slot3 sensitivity | -519 | -519 | `0xF` | PASS |

The four sensitivity payloads independently change rows 37, 38, 39 and 40.
All four HBM-derived embedding slots therefore have an observable effect on the
complete physical-board result; the test does not merely prove the baseline
case.

## 9. Cycle counters and timing boundary

Every case returned the same accepted compute counters:

| Counter | Cycles |
|---|---:|
| Bottom | 322 |
| Interaction | 100 |
| Top | 744 |
| Total | 1174 |

`1174` covers only the existing accepted compute-counter interval. It excludes:

- four sequential HBM lookup/prefetch intervals;
- Host orchestration;
- BO payload transfer; and
- complete all-HBM end-to-end inference time.

It must not be reported as all-HBM end-to-end latency.

## 10. Evidence provenance and hashes

The original archive remains outside Git at:

`_local_recovery/stage2n_a15_6_final_evidence/stage2n_a15_6_board_validation_v1_evidence.tar.gz`

Its locally recalculated SHA256 is:

`e903865a26153c5121ab84fe9f5735faa73df4bd73522cf079d1c9d0ae4a0c18`

The source server result was:

`results/stage2n_a15_6/board_validation_v1/20260831_102550`

The imported board JSON is:

`docs/evidence/stage2n_a15_6/final_acceptance_v1/a15_6_board_evidence_v1.json`

Its locally recalculated SHA256 is:

`a6d228b78ff1889ccb7a532e22997a6f6f669a024f802e0798271c625b7fe7da`

`docs/evidence/stage2n_a15_6/final_acceptance_v1/SHA256SUMS.txt` records
the archive and every imported compact-evidence hash. The tar, xclbin, XO,
build trees, caches, DCP and WDB are not committed.

## 11. Offline validation

The existing validator was run locally as:

```text
scripts/validate_stage2n_a15_6_evidence_v1.py
  --manifest models/stage2n_a15_6/stage2n_a15_6_cases_v1.json
  --evidence docs/evidence/stage2n_a15_6/final_acceptance_v1/a15_6_board_evidence_v1.json
```

Result:

```text
A15_6_IMPORTED_EVIDENCE_VALIDATION=PASS
A15_6_EVIDENCE_VALIDATION=PASS
```

The validator checks the exact xclbin identity, BDF, `HBM[0]`, payload hashes,
five expected/actual results, loaded masks, TABLE_BASE readback, cycle counters,
cleanup, board-functional state and performance boundary. Its self-test also
accepts the legal zero physical address and rejects wrong xclbin/UUID/BDF/bank,
wrong payload/golden, missing results and malformed evidence.

## 12. Accepted claims

A15.6 proves on the real F37X target:

- programming the frozen A15.5 xclbin;
- allocating, writing and releasing one BO in physical `HBM[0]`;
- programming TABLE_BASE with the returned physical address, including valid
  address zero;
- four sequential embedding lookups through one AXI read master;
- injection of physical-HBM results into embedding slots 0–3;
- execution of Bottom MLP, Feature Interaction and Top MLP; and
- exact final results for a baseline and four independent slot-sensitivity
  cases, with no FPGA reset or other-device access.

This establishes a real-board functional closed loop, not a performance result.

## 13. Explicit non-claims and limitations

The following remain unproven and must not be inferred from A15.6:

- multi-HBM-bank mapping or parallel bank access;
- parallel embedding lookup;
- burst or multiple-outstanding optimization;
- cache, prefetch or request-coalescing behavior;
- HBM lookup latency, all-HBM end-to-end latency, throughput or bandwidth;
- speedup, performance gain, power or energy improvement; and
- any model-size or INT8 result beyond the frozen A15.6 case set.

Accordingly, `A15_6_PERFORMANCE=NOT_CLAIMED` remains frozen.

## 14. Frozen baseline

Future work must preserve the accepted A15.4 RTL SHA, A15.5 XO/xclbin identity,
A15.6 five-case golden assets, public ABI and this compact evidence. The
A15.6 physical functional baseline is exactly one HBM bank, one AXI read master
and four sequential logical lookups.

## 15. Recommended Stage 2N-A16 direction

A16 is not implemented by this acceptance. Recommended order:

1. define one end-to-end timing boundary;
2. add explicit HBM lookup-interval counters;
3. distinguish lookup, compute and complete-inference latency;
4. measure and freeze the A15.6 sequential baseline;
5. map embeddings across multiple HBM banks;
6. introduce and verify parallel lookup; and
7. compare against the frozen A15.6 baseline.

No multi-bank speedup may be claimed before comparable target measurements and
functional equivalence are retained.
