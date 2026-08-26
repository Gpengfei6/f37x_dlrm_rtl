# Stage 2N-A14.7 Final Acceptance — Protected Host/XRT + Physical HBM Single-Table Lookup

## 1. Stage objective

Stage 2N-A14.7 closes the first protected physical-HBM execution path for the Stage 2N DLRM project.

The objective was to validate, on the authorized F37X target only:

1. target-compatible XRT 2020.2 Host build;
2. canonical 1024-byte embedding-table payload generation;
3. physical HBM[0] BO allocation and Host-to-device synchronization;
4. extraction of the BO device physical address;
5. programming TABLE_BASE_LO/TABLE_BASE_HI through the A14 AXI-Lite ABI;
6. one physical embedding-table lookup;
7. result comparison against the software golden row;
8. BO release and HBM[0] post-run cleanup;
9. execution under a protected device/BDF/render/UUID/CU guard.

This stage does not claim performance improvement and does not yet implement multi-table or multi-HBM-bank DLRM inference.

---

## 2. Platform and environment

Target platform:

- Platform: `inspur_f37x_xdma_201920_3`
- FPGA: `xcvu37p-fsvh2892-2L-e`
- Target xbutil index: `2`
- Target BDF: `0000:9b:00.1`
- Target render node: `/dev/dri/renderD129`
- XRT: `2.9.210507`
- Host compiler: GCC `4.8.5`
- C++ standard: `gnu++11`

Accepted A14.6 xclbin:

- Kernel: `dlrm_f37x_rtl_kernel_stage2n_a14_v2`
- CU instance: `dlrm_a14_1`
- XCLBIN UUID: `6f29087c-9598-4e68-877a-cc4840d078b8`
- XCLBIN SHA256: `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573`
- Requested memory connection: `m_axi_gmem -> HBM[0]`

No FPGA reset or automatic rollback was performed during A14.7.

---

## 3. A14 control ABI

The A14 Host uses the following control registers:

| Register | Offset | Purpose |
|---|---:|---|
| CONTROL | `0x00` | START / DONE / IDLE / READY / response-error state |
| LOOKUP_INDEX | `0x10` | embedding-table row index |
| TABLE_BASE_LO | `0x18` | physical table base address low 32 bits |
| TABLE_BASE_HI | `0x1C` | physical table base address high 32 bits |
| RESULT0 | `0x20` | result lanes 0–1 |
| RESULT1 | `0x24` | result lanes 2–3 |
| RESULT2 | `0x28` | result lanes 4–5 |
| RESULT3 | `0x2C` | result lanes 6–7 |

`CONTROL.done` has read-to-clear semantics.

---

## 4. Canonical physical-HBM payload

Canonical table configuration:

- Rows: `64`
- Embedding dimension: `8`
- Element type: `INT16`
- Row size: `16 bytes`
- Total payload: `1024 bytes`

Payload identity:

- SHA256: `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`
- FNV1a64: `40a53c3698b88325`

The accepted smoke lookup index is:

`LOOKUP_INDEX=37`

Expected embedding vector:

`[40, 41, 42, 43, 44, 45, 46, 47]`

---

## 5. Target XRT Host build acceptance

Formal Host build-only acceptance completed on the F37X environment before physical execution.

Accepted markers:

- `A14_7_HOST_XRT_BUILD=PASS`
- `A14_7_XRT2020_2_API_PROBE=PASS`
- `A14_7_CANONICAL_PAYLOAD=PASS`
- `HOST_EXECUTION=NOT_RUN`
- `FPGA_DEVICE_ACCESS=NONE`

Accepted Host source SHA256:

`027de80b7217e13450fdae2a1b926b2ce4966ad6326b1ddd4aaec97b864ae7ed`

Accepted Host ELF SHA256:

`f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`

Rebuilt accepted ELF size on the target environment:

`44064 bytes`

---

## 6. First protected physical attempt and artifact-integrity failure

The first protected physical attempt occurred at timestamp:

`20260826_161952`

The protected runner:

1. locked target index/BDF/render node;
2. verified no open render handle;
3. verified HBM[0] usage `0 Byte / 0 BO`;
4. completed the read-only activity guard;
5. received explicit `yes` authorization;
6. successfully programmed the accepted A14.6 xclbin;
7. verified the A14.6 UUID/CU;
8. attempted to invoke the formal Host artifact.

The runner then reported:

`Host smoke PASS marker missing`

No FPGA reset or automatic rollback was attempted.

Post-failure device state remained healthy:

- accepted A14.6 UUID loaded;
- CU `IDLE`;
- Firewall Level 0 `GOOD`;
- HBM[0] `0 Byte / 0 BO`;
- no persistent BO observed.

Root-cause analysis showed that the formal runtime Host artifact had been truncated to zero bytes while retaining executable mode:

- size: `0 bytes`
- mode: `775`
- empty-file SHA256:
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

The stale build-status file still contained the previously accepted non-empty ELF SHA256:

`f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`

Because the protected runner originally checked only executable permission and build-status PASS markers, the zero-byte executable passed the original Host-artifact gate and exited as an empty shell program with return code zero.

Therefore the first attempt did not constitute a valid physical-HBM lookup failure. The actual C++ Host did not execute its HBM BO path.

---

## 7. Runtime Host artifact guard hardening

The protected runner was hardened in commit:

`70179f66c6fab8a28c2305c024bec3fa43f9c508`

Subject:

`fix(stage2n): bind A14.7 runner to accepted Host binary`

The runtime gate now requires:

1. Host binary exists and is executable;
2. Host binary is non-empty;
3. build-status `BINARY_SHA256` equals the frozen accepted SHA256;
4. actual runtime Host ELF SHA256 equals the same frozen accepted SHA256.

Final protected runner SHA256:

`03838a0e0a3d85f8a0df622efa35c3a81cf69f58a56bc07792ec16965e48e47e`

Final Host ELF SHA256:

`f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`

---

## 8. Successful physical-HBM board validation

The successful functional board run occurred at:

`20260826_163749`

Functional tested Git HEAD:

`74301a458ef8f6ad7d59dafc80ff30bbae9961d3`

The accepted A14.6 image was already loaded, therefore:

`A14_7_FPGA_PROGRAMMING=SKIPPED_ALREADY_LOADED`

No FPGA reset occurred.

The Host allocated and synchronized the canonical table into HBM[0], obtained the device physical address, programmed TABLE_BASE and LOOKUP_INDEX, issued START, observed read-to-clear DONE, and read RESULT0–RESULT3.

Observed Host information:

- `HBM_MEMORY_INDEX=0`
- `BO_FLAGS_HEX=0x00000000`
- `BO_SIZE_BYTES=4096`
- `BO_PADDR_HEX=0x0000000000000000`
- `TABLE_BASE_LO_HEX=0x00000000`
- `TABLE_BASE_HI_HEX=0x00000000`

The BO size reflects XRT allocation granularity; the canonical payload itself remains exactly 1024 bytes.

HBM[0] has base address zero on this platform, so a device physical address of zero is valid for this allocation. Correct returned data provides end-to-end confirmation that this address was valid.

---

## 9. CONTROL protocol result

Observed control words:

- pre-start: `0x0000000c`
- authoritative DONE word: `0x00000006`
- post-DONE read: `0x0000000c`
- poll count: `1`

This validates the intended A14 read-to-clear DONE behavior and clean return to IDLE/READY.

No response error was observed.

---

## 10. Physical embedding result

Observed result registers:

- `RESULT0_HEX=0x00290028`
- `RESULT1_HEX=0x002b002a`
- `RESULT2_HEX=0x002d002c`
- `RESULT3_HEX=0x002f002e`

Decoded actual lanes:

`[40, 41, 42, 43, 44, 45, 46, 47]`

Software expected lanes:

`[40, 41, 42, 43, 44, 45, 46, 47]`

All eight lanes match exactly.

Accepted markers:

- `A14_7_HOST_EXECUTION=PASS`
- `A14_7_PHYSICAL_HBM=PASS`
- `A14_7_SINGLE_TABLE_LOOKUP=PASS`
- `A14_7_RESULT_MATCH=PASS`
- `A14_7_BO_RELEASED=PASS`
- `A14_7_HBM0_POST_RELEASE_ZERO=PASS`
- `A14_7_DMA_ACTIVITY_OBSERVED=PASS`

---

## 11. Final source-baseline guard validation

The final source baseline is:

`70179f66c6fab8a28c2305c024bec3fa43f9c508`

The hardened protected runner was executed on this source baseline with the rebuilt accepted Host ELF.

It successfully passed:

- Host non-empty gate;
- recorded Host SHA gate;
- actual Host SHA gate;
- target mapping gate;
- render-handle gate;
- HBM[0] zero-usage gate;
- 30-second read-only activity guard;
- accepted A14.6 UUID/CU recognition.

At the final authorization prompt the run was intentionally cancelled with `no`.

Therefore:

- final runtime Host artifact guard: `PASS`
- additional Host execution: `NOT_RUN`
- additional physical HBM lookup: `NOT_RUN`
- additional FPGA programming: `NOT_RUN`
- FPGA reset: `NOT_RUN`

This separates functional evidence from final guard-baseline evidence without performing an unnecessary second physical lookup.

---

## 12. Evidence identities

### Successful physical-HBM evidence

File:

`docs/evidence/stage2n_a14_7/final_acceptance_v1/a14_7_evidence_64_20260826_163749.txt`

Lines:

`64`

SHA256:

`644155ffc1c4e40456a52a2a8ca3a84765b1ce685b9d377138bdd25b6871d2d2`

### Successful physical-HBM raw log

File:

`docs/evidence/stage2n_a14_7/final_acceptance_v1/a14_7_board_pass_20260826_163749.log`

Lines:

`112`

SHA256:

`cecce17484def1645938b14df8f9b1744e13bf67ea9e4af3ab3ab25dbef54ca5`

### Final hardened guard log

File:

`docs/evidence/stage2n_a14_7/final_acceptance_v1/a14_7_final_guard_70179f6_20260826_164336.log`

Lines:

`53`

SHA256:

`9c7db499b84444d278c3be195439fa0984b144cb4586930112f2a2ba7755e368`

---

## 13. Final acceptance state

`STAGE2N_A14_7_FINAL_ACCEPTANCE=PASS`

Final state:

- `A14_7_LOCAL_SOURCE_PREPARATION=PASS`
- `A14_7_TARGET_XRT_BUILD=PASS`
- `A14_7_XRT2020_2_API_PROBE=PASS`
- `A14_7_CANONICAL_PAYLOAD=PASS`
- `A14_7_PROTECTED_DEVICE_GATE=PASS`
- `A14_7_HOST_ARTIFACT_GUARD=PASS`
- `A14_7_FPGA_PROGRAMMING=PASS`
- `A14_7_HOST_EXECUTION=PASS`
- `A14_7_PHYSICAL_HBM=PASS`
- `A14_7_SINGLE_TABLE_LOOKUP=PASS`
- `A14_7_RESULT_MATCH=PASS`
- `A14_7_BO_RELEASED=PASS`
- `A14_7_HBM0_POST_RELEASE_ZERO=PASS`
- `A14_7_DMA_ACTIVITY_OBSERVED=PASS`
- `A14_7_BOARD_SMOKE=PASS`
- `A14_7_FPGA_RESET=NOT_RUN`
- `A14_7_AUTOMATIC_ROLLBACK=NOT_RUN`
- `A14_7_PERFORMANCE=NOT_CLAIMED`

---

## 14. What A14.7 proves

A14.7 provides the first accepted proof in Stage 2N that the following physical path works on F37X:

`Host -> XRT BO -> HBM[0] -> physical BO address -> TABLE_BASE -> RTL AXI master -> embedding row -> AXI-Lite results -> software golden comparison`

This closes the minimum physical-HBM single-table lookup capability.

---

## 15. What A14.7 does not prove

A14.7 does not yet prove:

- multiple embedding tables;
- multiple HBM banks operating concurrently;
- bank-aware table placement;
- hotspot caching in BRAM/URAM;
- INT8/mixed-precision embedding;
- HBM lookup integrated into the complete A13 DLRM pipeline;
- end-to-end DLRM throughput;
- board power or energy efficiency;
- GPU comparison.

No performance claim is made from this smoke test.

---

## 16. Frozen baseline and next stage

Frozen final A14.7 source baseline:

`70179f66c6fab8a28c2305c024bec3fa43f9c508`

A14.7 is closed and should not be repeatedly re-executed merely for confirmation.

The next independent stage should integrate the accepted physical-HBM embedding lookup path with the existing A13 DLRM compute pipeline.

Initial integration target:

`Physical HBM embedding lookup -> Interaction -> Top MLP -> final result`

The first acceptance criterion for the next stage should remain functional correctness and software-golden equivalence before expanding to multi-table or multi-HBM-bank parallelism.
