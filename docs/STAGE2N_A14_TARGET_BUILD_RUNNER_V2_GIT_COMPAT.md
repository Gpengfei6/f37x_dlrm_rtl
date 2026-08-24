# Stage 2N-A14 Target Build Runner V2 Git Compatibility Fix

## 1. Purpose

This delivery records and fixes the first target-server runner failure for the
Stage 2N-A14 standalone HBM embedding-lookup prototype. The failure occurred
before Vivado, XO packaging, `v++ --link`, xclbin generation, implementation,
or timing analysis.

The fix is intentionally limited to Git worktree-status collection. It does
not modify A14 RTL, testbenches, kernel metadata, connectivity, target part,
clock, Vitis link settings, or any accepted A13 asset.

Repository context:

```text
Branch:        work/stage2n-a13-cycle-counter
Attempt-1 HEAD: 4d24272a9788a3b7006cc37667aefda33c83878e
Server Git:    older version accepting --porcelain without a value
Target part:   xcvu37p-fsvh2892-2L-e
Platform:      inspur_f37x_xdma_201920_3
```

## 2. Attempt-1 environment and transfer

The server could not fetch the GitHub repository through either its retained
`github-f37x-dlrm` SSH alias or direct HTTPS. The user therefore created a
complete Git bundle on Windows and transferred it through the established
`id_fpga` key workflow.

Recorded bundle evidence:

```text
Bundle: f37x_dlrm_a14_4d24272.bundle
SHA256: E769E84212E328B4094DAB2055B214C21ED92EA4FC401A67D44BC7D40CAD363A
Ref:    refs/heads/work/stage2n-a13-cycle-counter
HEAD:   4d24272a9788a3b7006cc37667aefda33c83878e
History: complete
```

The clean target-build repository was created at:

```text
/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a14_bundle_4d24272
```

The branch and HEAD matched the intended delivery and `git status --short`
was empty before attempt 1.

## 3. Observed failure

The V1 runner attempted:

```text
git status --porcelain=v1
```

The server Git returned:

```text
error: option `porcelain' takes no value
```

The retained status file reported:

```text
A14_TARGET_XO_BUILD=BLOCKED_NOT_RUN
A14_VPP_LINK=BLOCKED_NOT_RUN
A14_XCLBIN_BUILD=BLOCKED_NOT_RUN
A14_HBM0_LINK_MAPPING=BLOCKED_NOT_RUN
A14_TARGET_VU37P_TIMING=BLOCKED_NOT_RUN
FAIL_REASON=unexpected command failure at line 194
GIT_HEAD=4d24272a9788a3b7006cc37667aefda33c83878e
A14_PHYSICAL_HBM_ACCESS=NOT_VALIDATED
A14_FPGA_DEVICE_ACCESS=NONE
A14_READY_FOR_BOARD=NO
```

This is a runner compatibility failure, not an XO, Vitis-link, RTL, HBM,
timing, or board failure.

## 4. Root cause

The local development Git accepts the explicit porcelain format value
`--porcelain=v1`. The older server Git exposes `--porcelain` as a flag and
rejects an attached value. Both forms request the stable machine-readable
status format needed by the runner, but only the valueless form is compatible
with this server.

## 5. Corrective change

The worktree-state command in
`scripts/build_stage2n_a14_target_v1.sh` is changed to:

```text
git status --porcelain
```

The runner also accepts two evidence-only environment fields:

```text
A14_TARGET_BUILD_FLOW
A14_TARGET_RUNNER_VERSION
```

Their V1 defaults preserve the original behavior. The new compatibility entry
point is:

```text
scripts/build_stage2n_a14_target_v2.sh
```

It sets:

```text
A14_TARGET_BUILD_FLOW=STAGE2N_A14_TARGET_V2_GIT_COMPAT
A14_TARGET_RUNNER_VERSION=V2_GIT_PORCELAIN_COMPAT
```

and delegates to the corrected V1 implementation. All build, metadata,
connectivity, timing, and no-board gates therefore remain identical.

## 6. Attempt-1 asset preservation

Attempt-1 output must not be deleted or overwritten. Before a V2 retry, the
user must move the two generated roots to these retained names:

```text
build/stage2n_a14
  -> build/stage2n_a14_attempt1_git_porcelain_block

results/stage2n_a14/target_build_v1
  -> results/stage2n_a14/target_build_v1_attempt1_git_porcelain_block
```

The V2 retry then recreates the normal V1 artifact paths in a clean state. The
retained attempt-1 status remains directly inspectable and is not relabeled.

## 7. Verification boundary

Local checks required for this fix are:

- Bash syntax for V1 and V2;
- embedded Python syntax in V1;
- absence of `--porcelain=v1` from both runners;
- presence of exactly one compatible `git status --porcelain` call;
- unchanged RTL, testbench, target configuration, and post-route Tcl;
- clean diff and prohibited-operation scan.

Local validation can prove only that the compatibility change is structurally
correct. Only the user-controlled server retry can determine XO, xclbin,
HBM[0] link-metadata, and target-timing status.

Completed local results:

```text
V1_BASH_SYNTAX=PASS
V2_BASH_SYNTAX=PASS
EMBEDDED_PYTHON_SYNTAX=PASS
OLD_GIT_PORCELAIN_COMPAT=PASS
V2_EVIDENCE_TAGS=PASS
TRAILING_WHITESPACE=PASS
EXECUTABLE_FORBIDDEN_OPERATION_SCAN=PASS
DIFF_CHECK=PASS
```

## 8. Retry command

After preserving attempt-1 outputs and applying the fix commit to the clean
server repository, the user-controlled retry command is:

```bash
bash scripts/build_stage2n_a14_target_v2.sh
```

The retry remains build-only. It must stop before Host execution, device open,
FPGA programming, reset, or physical HBM validation.

## 9. Evidence status at this checkpoint

```text
A14_ATTEMPT1_RUNNER_COMPATIBILITY = FAIL_CONFIRMED
A14_ATTEMPT1_XO_BUILD             = BLOCKED_NOT_RUN
A14_ATTEMPT1_VPP_LINK             = BLOCKED_NOT_RUN
A14_ATTEMPT1_XCLBIN               = BLOCKED_NOT_RUN
A14_ATTEMPT1_HBM0_LINK_MAPPING    = BLOCKED_NOT_RUN
A14_ATTEMPT1_TARGET_TIMING        = BLOCKED_NOT_RUN
A14_V2_LOCAL_STATIC_CHECK         = PASS
A14_V2_TARGET_RETRY               = NOT_RUN
A14_PHYSICAL_HBM_ACCESS           = NOT_VALIDATED
A14_READY_FOR_BOARD               = NO
```

No attempt-1 status may be promoted to a tool-build failure or PASS. No V2
static check may be promoted to server, xclbin, HBM, timing, or board evidence.
