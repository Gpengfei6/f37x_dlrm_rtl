# Stage 2N-A14.7 Target XRT Build Attempt 1 Diagnosis

Date: 2026-08-26
Branch: `work/stage2n-a13-cycle-counter`
Source commit tested: `5802d570e2122969dc73a04c58d2d41551c50a92`

## 1. Purpose

This record diagnoses the first user-controlled target XRT build-only execution
for Stage 2N-A14.7. The run was intentionally limited to canonical payload
construction, XRT environment/API validation, and Host compile/link.

No Host binary was executed. No FPGA device was opened or programmed. No
physical HBM transaction was issued.

## 2. Target environment observed

- Server OS: Linux
- Repository clone:
  `/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a14_7_buildonly`
- XRT runtime expected/validated by the build gate: `2.9.210507`
- Compiler: `g++ (GCC) 4.8.5 20150623 (Red Hat 4.8.5-36)`
- C++ mode: `gnu++11`
- Source commit: `5802d570e2122969dc73a04c58d2d41551c50a92`

## 3. Bundle / source identity

The uploaded Git bundle was independently verified before the build:

```text
BUNDLE_SHA256=75151b4d5d06735689298f4245d8ff7cd529241f6d9031cf92b22d7af2b516bc
BUNDLE_HEAD=5802d570e2122969dc73a04c58d2d41551c50a92
BUNDLE_VERIFY=PASS
```

The clean build-only clone checked out the same commit and contained all seven
A14.7 source-preparation files.

## 4. Attempt sequence

### Attempt 1

The tracked build runner generated and validated the canonical payload, then
stopped while sourcing `/opt/xilinx/xrt/setup.sh`:

```text
A14_7_CANONICAL_PAYLOAD=PASS
PAYLOAD_BYTES=1024
PAYLOAD_SHA256=023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03
PAYLOAD_FNV1A64=40a53c3698b88325
/opt/xilinx/xrt/setup.sh: line 37: LD_LIBRARY_PATH: unbound variable
```

The login environment had `LD_LIBRARY_PATH`, `PYTHONPATH`, and `XILINX_XRT`
unset before XRT setup.

### Attempt 2

`LD_LIBRARY_PATH` was defined as empty only for the diagnostic subprocess. The
same vendor setup then stopped at its next direct expansion:

```text
/opt/xilinx/xrt/setup.sh: line 39: PYTHONPATH: unbound variable
```

This isolated the failure to Bash `nounset` inheritance rather than the A14.7
Host/API source.

### Diagnostic retry 2

Both `LD_LIBRARY_PATH` and `PYTHONPATH` were defined as empty only for the
diagnostic subprocess. The tracked A14.7 runner then completed its real target
compile/link gate:

```text
A14_7_HOST_XRT_BUILD=PASS
A14_7_XRT2020_2_API_PROBE=PASS
A14_7_CANONICAL_PAYLOAD=PASS
BINARY_SHA256=af743c77ec380fc31e2cf79a07e328f7831eb16d0e4f8459846dd99f3e6b532a
PAYLOAD_SHA256=023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03
HOST_EXECUTION=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
```

The generated Host binary was:

```text
ELF 64-bit LSB executable, x86-64, dynamically linked
```

and the build directory retained `host_build.log`, `host_build_status.txt`,
the Host ELF, canonical payload/manifest, XRT symbol log, and XRT version log.

## 5. Compiler warning disposition

GCC 4.8.5 emitted `-Wmissing-field-initializers` warnings for:

```cpp
xclBOProperties properties_ = {};
```

The constructor already executes:

```cpp
std::memset(&properties_, 0, sizeof(properties_));
```

before `xclGetBOProperties` or any property read. The aggregate initializer is
therefore redundant and can be removed without changing runtime semantics.

## 6. Root cause

The A14.7 project build script correctly enabled strict shell mode with
`set -Eeuo pipefail`, but the XRT 2020.2 vendor setup script is not nounset-safe:

```text
export LD_LIBRARY_PATH=$XILINX_XRT/lib:$LD_LIBRARY_PATH
export PYTHONPATH=$XILINX_XRT/python:$PYTHONPATH
```

The project must not require callers to pre-populate arbitrary vendor setup
variables merely to satisfy `set -u`.

## 7. Adopted source fix

The versioned build runner will temporarily suspend only `nounset` while
sourcing the trusted vendor environment, then immediately restore strict mode:

```bash
set +u
source "${XRT_SETUP}" >/dev/null
set -u
```

The Host source will also drop the redundant aggregate initializer that triggers
the GCC 4.8 warning; explicit constructor `memset` remains the initialization
contract.

## 8. Acceptance boundary

This diagnostic run establishes strong evidence that the A14.7 Host source and
required legacy XRT APIs compile/link on the real F37X software stack.

It is **not yet the final target-build acceptance**, because the successful run
used an external environment workaround rather than the versioned corrected
runner. A clean rerun of the fixed tracked script is required.

Current boundary:

```text
A14_7_CANONICAL_PAYLOAD=PASS
A14_7_TARGET_XRT_BUILD_DIAGNOSTIC=PASS
A14_7_VERSIONED_RUNNER_FORMAL_RERUN=REQUIRED
A14_7_HOST_EXECUTION=NOT_RUN
A14_7_FPGA_PROGRAMMING=NOT_RUN
A14_7_PHYSICAL_HBM=NOT_RUN
A14_7_FPGA_DEVICE_ACCESS=NONE
A14_7_READY_FOR_BOARD=NO
```
