# Stage 2N-A13 Final Acceptance Report

## 1. Scope

Stage 2N-A13 adds four 32-bit saturating hardware cycle counters to the existing DLRM FPGA inference pipeline:

- Bottom MLP cycles
- Feature Interaction cycles
- Top MLP cycles
- Total pipeline cycles

A13 does **not** add FPGA-side HBM embedding lookup, `m_axi`, DMA batch input, or a new model topology. Embedding lookup is still resolved on the CPU side and resolved embedding vectors are written to the FPGA through the control path.

## 2. Target Platform

- Board/platform: Inspur F37X
- FPGA: `xcvu37p-fsvh2892-2L-e`
- Vitis platform: `inspur_f37x_xdma_201920_3`
- XRT: `2.9.210507`
- Target board index: `2`
- Target BDF: `0000:9b:00.1`
- Render node: `/dev/dri/renderD129`
- Kernel clock: `100 MHz`
- Kernel/CU:
  - Kernel: `dlrm_f37x_rtl_kernel_stage2n_a13_v1`
  - CU: `dlrm_a13_1`

## 3. Build and Implementation Results

### 3.1 XSim

- `A13_XSIM=PASS`
- Expected stage-cycle counts:
  - Bottom: `322`
  - Interaction: `100`
  - Top: `744`
  - Total: `1174`
- Restart behavior: PASS
- 12-cycle result backpressure behavior: PASS

### 3.2 Host build

- `A13_HOST_XRT_BUILD=PASS`
- Host executable:
  `build/stage2n_a13/host_v1/stage2n_a13_cycle_counter_board_v1`

### 3.3 XO package

- `A13_XO_BUILD=PASS`
- XO SHA256:
  `d7c4bf9c7298573f63ac2390e39f306e5f8bb25f394601fa7c4ba67dfac33add`

### 3.4 F37X xclbin

- `A13_XCLBIN_BUILD=PASS`
- xclbin:
  `build/stage2n_a13/vitis_link_manual_v1/dlrm_f37x_rtl_kernel_stage2n_a13_v1.xclbin`
- xclbin SHA256:
  `f3d33821804e266e6d3e664e03c7db13c8b3092cdd9bc1c5b75b5080569e3cdf`
- xclbin UUID:
  `807f85c5-dc98-4e79-aaf0-ec2f3edc7d5a`

### 3.5 Routed timing

Final post-route physical optimization timing:

- Global WNS: `0.000 ns`
- Global TNS: `0.000 ns`
- Global failing endpoints: `0`
- Vivado status: `All user specified timing constraints are met.`

100 MHz kernel clock:

- Clock: `clk_out1_pfm_top_clkwiz_kernel_0`
- Period: `10.000 ns`
- Frequency: `100.000 MHz`
- WNS: `+1.456 ns`
- TNS: `0.000 ns`
- Failing endpoints: `0`

Therefore:

`A13_TARGET_VU37P_TIMING=PASS`

## 4. Real-Board Validation

A13 was programmed only to the authorized target:

- Index `2`
- BDF `0000:9b:00.1`
- `/dev/dri/renderD129`

Post-program verification:

- `PROGRAM_EXIT=0`
- UUID matched A13 xclbin
- CU:
  `dlrm_f37x_rtl_kernel_stage2n_a13_v1:dlrm_a13_1`
- CU status: `IDLE`
- Firewall: `Level 0 : 0x0(GOOD)`

## 5. Test Asset

Deterministic trained-model regression asset:

- Samples: `256`
- Model:
  `stage2m_trained_hybrid_dlrm_8x16x8_interact18_32x16x1`
- Descriptor count: `5`
- Weight count: `1360`
- Bias count: `73`
- Embedding tables: `4`
- Embedding dimension: `8`
- Dense dimension: `8`
- Interaction dimension: `18`
- Final descriptor tag: `4`

Software reference:

- Bottom exact: `256/256`
- Interaction exact: `256/256`
- Top exact: `256/256`
- Classification correct: `228/256`
- Accuracy: `0.890625`

## 6. Real-Board Functional Results

Host exit:

`HOST_EXIT=0`

FPGA exactness:

- `FPGA_LOGIT_EXACT=256`
- `FPGA_PREDICTION_EXACT=256`
- `FPGA_RESULT_INDEX_EXACT=256`
- `FPGA_RESULT_TAG_EXACT=256`
- `FPGA_BOTTOM_COUNT_EXACT=256`
- `FPGA_INTERACTION_COUNT_EXACT=256`
- `FPGA_CYCLE_COUNTER_VALID=256`

Classification:

- Correct: `228/256`
- Accuracy: `0.890625`

Final host status:

`STAGE2N_A13_CYCLE_COUNTER_BOARD_V1_PASS`

## 7. Hardware Cycle Measurements

At `100 MHz`:

| Stage | Cycles | Hardware time |
|---|---:|---:|
| Bottom MLP | 322 | 3.22 us |
| Interaction | 100 | 1.00 us |
| Top MLP | 744 | 7.44 us |
| Total pipeline | 1174 | 11.74 us |

The measured board counters exactly reproduce the XSim cycle counts.

## 8. Host-Visible Batch Timing

- 256-sample host batch elapsed time: `58440 us`
- Average host-visible time:
  `58440 / 256 = 228.28125 us/sample`

This value is not the same metric as the 11.74 us FPGA-internal pipeline latency.

Current control path still includes CPU-side embedding lookup and fine-grained AXI-Lite register transactions. Therefore the current host-visible latency must not be described as pure FPGA compute latency.

## 9. Post-Run Safety State

After the host run:

- Firewall: `0x0(GOOD)`
- CU: `IDLE`
- No FPGA reset performed by the A13 host
- No FPGA programming performed by the A13 host

## 10. Claim Boundary

The current evidence supports:

- A configurable FPGA DLRM internal inference pipeline
- Correct Bottom MLP → Interaction → Top MLP execution
- Bit-exact FPGA/software regression for 256 deterministic trained-model samples
- Real F37X / XCVU37P implementation at 100 MHz
- Hardware-observable per-stage and total cycle counts

The current evidence does **not** support claiming:

- Real Criteo dataset validation
- FPGA-side HBM embedding lookup
- `m_axi`-based embedding memory access
- DMA-based batch input
- Multi-bank HBM embedding mapping
- End-to-end latency equal to 11.74 us

## 11. Final Acceptance

```text
STAGE2N_A13_FINAL_STATUS=PASS

A13_XSIM=PASS
A13_HOST_XRT_BUILD=PASS
A13_XO_BUILD=PASS
A13_XCLBIN_BUILD=PASS
A13_TARGET_VU37P_TIMING=PASS
A13_BOARD_PROGRAM=PASS
A13_BOARD_FUNCTIONAL=PASS
A13_CYCLE_COUNTER_BOARD=PASS

TARGET_KERNEL_CLOCK=100MHz
SAMPLES=256
FPGA_LOGIT_EXACT=256/256
FPGA_PREDICTION_EXACT=256/256
FPGA_CLASSIFICATION_ACCURACY=0.890625

BOTTOM_CYCLES=322
INTERACTION_CYCLES=100
TOP_CYCLES=744
TOTAL_CYCLES=1174
TOTAL_HW_LATENCY_US=11.74

HOST_BATCH_ELAPSED_US=58440
HOST_AVG_US_PER_SAMPLE=228.28125

FIREWALL_AFTER_RUN=GOOD
CU_AFTER_RUN=IDLE
```

A13 is accepted and should be frozen. Future architecture work should proceed in a new stage rather than modifying the accepted A13 baseline.
