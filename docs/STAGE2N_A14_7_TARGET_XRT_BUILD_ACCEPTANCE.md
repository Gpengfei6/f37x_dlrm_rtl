# Stage 2N-A14.7 Target XRT Build-Only Acceptance

Date: 2026-08-26
Branch: `work/stage2n-a13-cycle-counter`
Accepted tested server HEAD: `82a6e4627bcaa0e9c7bab6daf8ca6bcc095d7cc6`

## Goal
Close the A14.7 target build-only gate on the real F37X software stack without
executing the Host or accessing the FPGA.

## Formal environment
- XRT: `2.9.210507`
- Compiler: `g++ (GCC) 4.8.5 20150623 (Red Hat 4.8.5-36)`
- C++ standard: `gnu++11`
- Caller `LD_LIBRARY_PATH`: unset
- Caller `PYTHONPATH`: unset
- Caller `XILINX_XRT`: unset
- Tracked worktree/index before run: clean

## Formal result
```text
A14_7_CANONICAL_PAYLOAD=PASS
A14_7_HOST_XRT_BUILD=PASS
A14_7_XRT2020_2_API_PROBE=PASS
HOST_EXECUTION=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
```

The formal Host is a 64-bit x86-64 dynamically linked ELF reported as 44 KiB.
`host_build.log` is zero bytes; the prior GCC 4.8 aggregate-init warnings are
absent after commit `82a6e46`.

## Artifact identities
- Host source SHA256: `027de80b7217e13450fdae2a1b926b2ce4966ad6326b1ddd4aaec97b864ae7ed`
- Asset builder SHA256: `ab34fd6ef33563e30b52a5d811143c84fc6cc028e08e22376edfbb463d18570c`
- Source JSON SHA256: `af29d60e3dce8ebcbe87e1363665869851ee87942471aacadeacd47642e73122`
- Payload bytes: `1024`
- Payload SHA256: `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`
- Payload FNV1a64: `40a53c3698b88325`
- Host ELF SHA256: `f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`

## Acceptance boundary
```text
A14_7_LOCAL_SOURCE_PREPARATION=PASS
A14_7_TARGET_XRT_BUILD=PASS
A14_7_XRT2020_2_API_PROBE=PASS
A14_7_CANONICAL_PAYLOAD=PASS
A14_7_READY_FOR_BOARD=YES
A14_7_HOST_EXECUTION=NOT_RUN
A14_7_FPGA_PROGRAMMING=NOT_RUN
A14_7_PHYSICAL_HBM=NOT_RUN
A14_7_FPGA_DEVICE_ACCESS=NONE
A14_7_BOARD_SMOKE=NOT_RUN
A14_7_PERFORMANCE=NOT_RUN
A14_7_A13_INTEGRATION=NOT_RUN
```

`A14_7_READY_FOR_BOARD=YES` means only that the separately protected board gate
may be entered; it is not a board PASS.
