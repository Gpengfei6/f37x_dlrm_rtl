# Stage 2N-A14 Target XO and XCLBIN Build Runner V1

## 1. Purpose

This stage prepares a reproducible, build-only server runner for the first A14
target-platform link. It consumes the already reviewed A14 lookup RTL, wrapper,
packaging Tcl, and single-bank connectivity configuration.

The runner is:

```text
scripts/build_stage2n_a14_target_v1.sh
```

The routed-checkpoint report script is:

```text
scripts/report_stage2n_a14_vitis_post_route_v1.tcl
```

Neither script accesses an FPGA device. They do not run a Host program, open an
XRT render node, program or reset a board, or issue a physical HBM transaction.

Repository context for this delivery unit:

```text
Branch:        work/stage2n-a13-cycle-counter
Baseline HEAD: 41cd7776b77e4af410684824038886851d5a315e
Baseline:      docs: establish AI-readable project context and collaboration policy
Delivery:      the Git commit containing this stage document and its four companion files
```

The branch name is retained for continuity with the accepted A13 baseline; the
implementation scope of this delivery is A14 target-build preparation only.

## 2. Frozen inputs

The runner uses only these reviewed A14 inputs:

- `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`;
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv`;
- `scripts/package_stage2n_a14_rtl_kernel_v1.tcl`;
- `scripts/report_stage2n_a14_vitis_post_route_v1.tcl`;
- `config/stage2n_a14_target_v1.cfg`.

The original `config/stage2n_a14_v1.cfg` remains unchanged. The target-only
configuration adds one explicit `nk=` declaration with the shortened compute
unit name `dlrm_a14_1`. This keeps
`dlrm_f37x_rtl_kernel_stage2n_a14_v1:dlrm_a14_1` within the Vitis 2020.2
64-character kernel/CU limit.

The expected platform and target are:

```text
Platform: inspur_f37x_xdma_201920_3
Part:     xcvu37p-fsvh2892-2L-e
Clock:    100 MHz
```

The only requested memory mapping is:

```text
dlrm_a14_1.m_axi_gmem -> HBM[0]
```

## 3. Runner gates

Before invoking Vivado or `v++`, the runner:

1. refuses to overwrite an existing A14 build or target-result root;
2. checks the Vitis settings file and exact F37X `.xpfm` path;
3. requires exactly one `sp=` mapping and requires it to be the reviewed
   `m_axi_gmem:HBM[0]` entry;
4. requires exactly one `nk=` declaration and checks the 64-character
   kernel/CU limit;
5. records branch, HEAD, worktree status, tool versions, and source hashes;
6. confirms that all required tools are available after sourcing Vitis 2020.2.

## 4. Target XO validation

The runner calls the existing A14 package Tcl without a proxy-part argument.
The packaging log must therefore contain:

```text
TARGET_PART_USED=1
```

It then checks:

- XO archive integrity;
- kernel name from generated `kernel.xml`;
- `user_managed` control protocol;
- 32-bit slave `s_axi_control`;
- 128-bit master `m_axi_gmem`;
- five kernel arguments at offsets `0x10`, `0x20`, `0x24`, `0x28`, and `0x2C`;
- six component registers including `CONTROL` at `0x00`.

Proxy-part packaging is not accepted by this target runner.

## 5. Vitis link and xclbin validation

The runner invokes `v++ --target hw --link` with:

- the resolved F37X platform path;
- `config/stage2n_a14_target_v1.cfg`;
- one A14 XO;
- a requested 100 MHz kernel clock;
- saved implementation temporary files.

After link, it requires:

- zero anchored `ERROR:` lines;
- zero anchored `CRITICAL WARNING:` lines;
- a non-empty xclbin;
- the expected kernel, compute unit, and platform in `xclbinutil --info`;
- non-empty `CONNECTIVITY`, `MEM_TOPOLOGY`, and `IP_LAYOUT` JSON sections;
- one used `HBM[0]` memory entry;
- exactly one expected A14 compute unit in the IP layout;
- exactly one CONNECTIVITY record whose IP-layout index is that compute unit
  and whose memory-topology index is `HBM[0]`.

These checks validate the linked xclbin metadata and requested HBM[0] mapping.
They do not validate a physical read from HBM.

## 6. Routed timing and resource evidence

The report Tcl opens the routed Vitis checkpoint read-only and writes:

- timing summary and 100 worst setup paths;
- clock report;
- hierarchical utilization;
- DRC and methodology reports;
- verbose `check_timing` output;
- optional high-fanout and RAM reports;
- a machine-readable metrics file.

Target timing passes only when:

```text
TARGET_PART = xcvu37p-fsvh2892-2L-e
WNS >= 0
TNS = 0
FAILING_ENDPOINTS = 0
```

The metrics also retain LUT, FF, BRAM, URAM, DSP, latch, DRC, methodology,
clock, worst-startpoint, and worst-endpoint information.

## 7. Output locations

Generated build artifacts are placed under:

```text
build/stage2n_a14/
```

Evidence is placed under:

```text
results/stage2n_a14/target_build_v1/
```

The primary status file is:

```text
results/stage2n_a14/target_build_v1/a14_target_build_status.txt
```

Source and generated-artifact SHA256 manifests are retained beside the status
file. The result directory also contains tool versions, logs, xclbin metadata,
connectivity JSON, HBM topology JSON, IP layout JSON, routed reports, and the
recorded Git worktree state.

## 8. Intended user-controlled execution

The script is intended to be run by the user through the project's established
server-transfer and key workflow, from the server repository root:

```bash
bash scripts/build_stage2n_a14_target_v1.sh
```

Optional environment overrides are limited to:

```bash
VITIS_SETTINGS=/path/to/Vitis/2020.2/settings64.sh
PLATFORM=/path/to/inspur_f37x_xdma_201920_3.xpfm
JOBS=8
```

The target clock is frozen at 100 MHz in this runner. A
`KERNEL_FREQUENCY_MHZ` override other than `100` is rejected so that the
post-route timing evidence cannot be mislabeled.

The runner must not be used to access a board. A later physical-HBM stage needs
separate Host code, a reviewed BO allocation/data-loading contract, device
authorization, and an independent board-run gate.

## 9. Current evidence status

At creation time, only local static validation of these new scripts is allowed.
Until the user supplies the target-environment logs, the correct status is:

```text
A14_TARGET_RUNNER_BASH_SYNTAX  = PASS
A14_POST_ROUTE_TCL_STRUCTURE   = PASS
A14_TARGET_RUNNER_SHELLCHECK   = NOT_RUN_MISSING_TOOL
A14_TARGET_XO_BUILD            = NOT_RUN
A14_VPP_LINK                   = NOT_RUN
A14_XCLBIN_BUILD               = NOT_RUN
A14_HBM0_LINK_MAPPING          = NOT_RUN
A14_TARGET_VU37P_TIMING        = NOT_RUN
A14_PHYSICAL_HBM_ACCESS        = NOT_VALIDATED
A14_READY_FOR_BOARD            = NO
```

No script presence or local syntax check may be relabeled as target build,
link, timing, physical HBM, or board PASS.
