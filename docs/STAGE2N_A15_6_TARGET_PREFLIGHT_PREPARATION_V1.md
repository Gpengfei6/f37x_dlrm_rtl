# Stage 2N-A15.6 Target Preflight Preparation V1

Date: 2026-08-31

## 1. Result and boundary

This change prepares a device-free target preflight for the already accepted
A15.6 local assets. It does not execute the preflight on the target and does not
run the protected board flow.

```text
A15_6_LOCAL_PREPARATION=PASS
A15_6_TARGET_PREFLIGHT_PREPARED=YES
A15_6_TARGET_PREFLIGHT=NOT_RUN
READY_TO_TRANSFER_TO_TARGET=YES
FPGA_PROGRAMMING=NOT_RUN
HOST_EXECUTION=NOT_RUN
PHYSICAL_HBM=NOT_VALIDATED
BOARD_FUNCTIONAL=NOT_RUN
PERFORMANCE=NOT_CLAIMED
FPGA_DEVICE_ACCESS=NONE
SERVER_ACCESS=NONE_BY_CODEX
NETWORK_ACCESS=NONE_BY_CODEX
FROZEN_RTL_MODIFIED=NO
XCLBIN_REBUILT=NO
```

The user-controlled target preflight must pass before a separately authorized
protected board execution may be considered.

### Old-Git compatibility correction

The first user-controlled target attempt exposed an older F37X server Git that
does not accept `git -C <repo> ...` and does not support
`git symbolic-ref --short HEAD`. The preflight already changes into the exact
repository before running Git gates, so all runtime Git commands now execute
repository-locally. Branch detection uses the server-validated
`git rev-parse --abbrev-ref HEAD`, while HEAD detection remains
`git rev-parse HEAD`. The protected board runner uses the same compatible
branch query so it cannot fail at the next gate for the same reason.

This correction does not change RTL, Host functionality, board-run behavior,
the frozen XO/xclbin, ABI, golden assets, or any device-access boundary.

### Deterministic golden source-path correction

The target preflight initially passed the absolute server path of the source
model package to the golden builder. That path was consequently serialized into
the regenerated manifest and made its bytes environment-dependent. The script
now keeps the absolute path for required-input validation but passes the stable
repository-relative path
`models/stage2m/stage2m_trained_hybrid_dlrm.f37xhd` to the builder after changing
into the repository root. All seven existing byte-for-byte `cmp` gates remain
unchanged. This restores deterministic regeneration across Windows, Linux, and
the F37X server without changing the builder algorithm or any frozen asset.

## 2. Frozen identities

| Item | Frozen value |
|---|---|
| A15.6 preparation HEAD | `ee3dcaa7f3d90458f3b770318001f3b16d04eccf` |
| Accepted A15.4 RTL SHA256 | `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1` |
| xclbin SHA256 | `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356` |
| xclbin UUID | `1b555645-a9e2-4f5e-95af-6ce4adacbc3c` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a15_v1` |
| Compute unit | `dlrm_a15_1` |
| Connectivity | `dlrm_a15_1.m_axi_gmem:HBM[0]` |
| Target part | `xcvu37p-fsvh2892-2L-e` |
| Platform | `inspur_f37x_xdma_201920_3` |
| Requested clock | 100 MHz |

The established target repository remains:

```text
/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a15_5_buildonly
```

Its untracked `build/`, `results/`, `logs/`, `.ipcache/`, and accepted xclbin
must remain in place. No new repository is needed.

## 3. Exact A15.6 asset inventory from `ee3dcaa`

### Runtime and build sources

- `host/stage2n_a15_6_all_hbm_board_validation_v1.cpp`
- `scripts/build_stage2n_a15_6_host_v1.sh`
- `scripts/program_and_run_stage2n_a15_6_all_hbm_board_validation_v1.sh`

### Golden generation and assets

- `python/build_stage2n_a15_6_board_assets_v1.py`
- `models/stage2n_a15_6/stage2n_a15_6_model_v1.bin`
- `models/stage2n_a15_6/stage2n_a15_6_cases_v1.json`
- `models/stage2n_a15_6/stage2n_a15_6_case0_baseline_table_v1.bin`
- `models/stage2n_a15_6/stage2n_a15_6_case1_slot0_sensitivity_table_v1.bin`
- `models/stage2n_a15_6/stage2n_a15_6_case2_slot1_sensitivity_table_v1.bin`
- `models/stage2n_a15_6/stage2n_a15_6_case3_slot2_sensitivity_table_v1.bin`
- `models/stage2n_a15_6/stage2n_a15_6_case4_slot3_sensitivity_table_v1.bin`

### Validation and evidence sources

- `scripts/validate_stage2n_a15_6_sources_v1.py`
- `scripts/validate_stage2n_a15_6_evidence_v1.py`
- `scripts/assemble_stage2n_a15_6_evidence_v1.py`
- `docs/evidence/stage2n_a15_6/A15_6_BOARD_EVIDENCE_TEMPLATE_V1.json`
- `docs/STAGE2N_A15_6_PROTECTED_ALL_HBM_BOARD_VALIDATION_PREPARATION_V1.md`

The new target-preflight files are:

- `scripts/run_stage2n_a15_6_target_preflight_v1.sh`
- `scripts/validate_stage2n_a15_6_target_preflight_v1.py`
- `docs/evidence/stage2n_a15_6/A15_6_TARGET_PREFLIGHT_STATUS_TEMPLATE_V1.txt`

## 4. Target-preflight behavior

The preflight performs only these operations:

1. verifies the exact target-repository path, branch, ancestry, clean tracked
   worktree/index, frozen RTL SHA256, and records rather than removes untracked
   files;
2. checks the Vitis 2020.2 settings path, XRT setup, compiler, legacy XRT
   headers/libraries/symbols, Python and required read-only utilities;
3. validates the existing xclbin SHA256, UUID, kernel/CU, TABLE_BASE metadata,
   unique `IP_KERNEL`, and sole used `HBM[0]` connection using the accepted
   A15.5 v2 validator;
4. compiles the A15.6 Host, or validates an existing non-empty build against
   its retained source and binary SHA256 values;
5. regenerates all A15.6 assets into a new result directory and compares every
   byte with the tracked model, case manifest, and five HBM table payloads;
6. statically validates the protected runner and the A15/A13 ABI; and
7. writes a non-overwriting timestamped status/evidence directory.

It does not run `xbutil scan/query/program/reset`, `xbmgmt`, `v++`, Vivado, the
Host executable, the protected board runner, or any command that opens an XRT
device or allocates a BO.

## 5. Host XRT 2020.2 compatibility conclusion

The A15.6 Host retains the A14.7-accepted legacy HAL pattern:

```text
xclOpen / xclClose
xclOpenContext / xclCloseContext
xclIPName2Index
xclRegRead / xclRegWrite
xclAllocBO / xclFreeBO
xclMapBO / xclUnmapBO
xclSyncBO
xclGetBOProperties
```

The build script uses the same `xrt.h`, `experimental/xrt-next.h`,
`libxrt_core.so`, XRT `2.9.210507`, `gnu++11`, `-pthread`, and `-ldl` convention
as the accepted A14.7 build. No newer XRT API is introduced. Local static source
validation passes; actual target compilation remains part of the not-yet-run
target preflight.

The Host does not call `xclLoadXclBin`: the separately protected runner owns any
future programming decision, while the Host opens an exclusive context for the
already active frozen UUID. This separation matches the accepted A14.7 pattern.

## 6. Frozen ABI

The preflight source validator checks these exact A15/A13 values:

- A15 control/status: `0x300`;
- TABLE_BASE low/high: `0x304` / `0x308`;
- A15 START/CLEAR: `0x0001` / `0x0002`;
- DONE/error/START-ready: status bits 4/5/6;
- Bottom/Interaction/Top/Total counters:
  `0x218` / `0x21C` / `0x220` / `0x224`;
- the retained descriptor, activation, weight, bias, result, error, readiness,
  and pipeline-configuration windows used by the complete A13 inference.

A14 single-lookup CONTROL semantics are not substituted for the A15 state
machine.

## 7. Golden contract

| Case | Purpose | Expected final result |
|---|---|---:|
| 0 | baseline | -393 |
| 1 | slot0 sensitivity | -392 |
| 2 | slot1 sensitivity | -93 |
| 3 | slot2 sensitivity | -689 |
| 4 | slot3 sensitivity | -519 |

The preflight validates the model/table sizes, SHA256 values, rows 37–40,
manifest consistency, and byte-for-byte deterministic regeneration. These are
software/build-readiness checks, not physical-HBM evidence.

## 8. Expected target-preflight evidence

Each user-run preflight writes a new directory:

```text
results/stage2n_a15_6/target_preflight_v1/<timestamp>/
```

Expected files include:

- `a15_6_target_preflight_v1_status.txt`;
- `git_status_porcelain.txt`;
- `tool_versions.log`;
- `source_validation.log`;
- `preflight_source_validation.log`;
- `golden_regeneration.log` and `golden_regeneration_status.txt`;
- regenerated comparison assets under `generated_assets/`;
- xclbin info, CONNECTIVITY, MEM_TOPOLOGY and IP_LAYOUT extracts;
- `xclbin_metadata_validation_v2.log`;
- copied `host_build_status.txt`; and
- `preflight_sources.sha256`.

The committed status template remains `NOT_RUN`; it is not evidence of a target
PASS.

## 9. Transfer workflow

Bundle filename:

```text
stage2n_a15_6_target_preflight_v1.bundle
```

The bundle must be created only after the preflight-preparation commit. A Git
bundle contains tracked history only, so it excludes historical untracked
assets, `build/`, xclbin, DCP, tar archives and `_local_recovery/`.

The target import must fetch the branch to a temporary ref, prove that the
current target HEAD is an ancestor, and use `git merge --ff-only`. It must not
clean, reset, stash, replace, or delete any target output.

Manual Windows bundle creation (not executed by Codex):

```powershell
Set-Location D:\FpgaWork\f37x_dlrm_rtl
$Bundle = Join-Path (Get-Location) 'stage2n_a15_6_target_preflight_v1.bundle'
git bundle create $Bundle work/stage2n-a15-hbm-pipeline-integration
git bundle verify $Bundle
Get-FileHash -Algorithm SHA256 -LiteralPath $Bundle
```

Manual upload through the established `id_fpga` flow (not executed by Codex):

```powershell
$Bundle = 'D:\FpgaWork\f37x_dlrm_rtl\stage2n_a15_6_target_preflight_v1.bundle'
scp.exe -i "$env:USERPROFILE\.ssh\id_fpga" -o IdentitiesOnly=yes -- `
  $Bundle `
  'chaosuan@172.17.8.254:/home/chaosuan/gpf/gpf_f37x_dlrm/transfer/stage2n_a15_6_target_preflight_v1.bundle'
```

Manual Linux fast-forward-only import (not executed by Codex):

```bash
REPO=/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a15_5_buildonly
BUNDLE=/home/chaosuan/gpf/gpf_f37x_dlrm/transfer/stage2n_a15_6_target_preflight_v1.bundle
BRANCH=work/stage2n-a15-hbm-pipeline-integration
TRANSFER_REF=refs/remotes/a15_6_transfer/stage2n-a15-hbm-pipeline-integration

cd "${REPO}"
git bundle verify "${BUNDLE}"
test "$(git rev-parse --abbrev-ref HEAD)" = "${BRANCH}"
git diff --quiet
git diff --cached --quiet
git fetch "${BUNDLE}" "refs/heads/${BRANCH}:${TRANSFER_REF}"
git merge-base --is-ancestor HEAD "${TRANSFER_REF}"
git merge --ff-only "${TRANSFER_REF}"
git merge-base --is-ancestor ee3dcaa7f3d90458f3b770318001f3b16d04eccf HEAD
git status --short
```

The final status intentionally shows retained untracked build/results/log files;
only tracked worktree/index changes are prohibited.

## 10. Target execution order

After the user transfers and fast-forwards the target repository, the only
command authorized by this preparation is:

```bash
cd /home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a15_5_buildonly
bash -n scripts/run_stage2n_a15_6_target_preflight_v1.sh
bash -n scripts/build_stage2n_a15_6_host_v1.sh
bash -n scripts/program_and_run_stage2n_a15_6_all_hbm_board_validation_v1.sh
python3 scripts/validate_stage2n_a15_6_target_preflight_v1.py --repo .
bash scripts/run_stage2n_a15_6_target_preflight_v1.sh
```

The preflight itself builds the Host when no valid A15.6 Host build exists and
otherwise verifies the retained source/binary hashes. A separate Host-build
command is therefore optional and should not be used to overwrite an existing
build directory.

Only after that run returns a complete status with all five preflight gates
PASS may the user request separate authorization for the protected board run.
No FPGA-programming command is supplied by this document.

## 11. Performance boundary

`1174` cycles remains the accepted compute-only interval and excludes the four
HBM lookups. Target preflight performs no inference and records no performance.

```text
PERFORMANCE=NOT_CLAIMED
```
