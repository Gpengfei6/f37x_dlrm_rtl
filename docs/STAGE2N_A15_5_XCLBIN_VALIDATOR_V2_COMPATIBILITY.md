# Stage 2N-A15.5 XCLBIN Validator V2 Compatibility Fix

Date: 2026-08-28

## 1. Scope

This change fixes one offline metadata-validator incompatibility exposed by a
user-controlled Vitis 2020.2 A15.5 target link. It does not change RTL,
packaging inputs, kernel metadata, connectivity, the generated XO/xclbin, or
the target implementation. It does not run `v++`, rebuild an artifact, access
an FPGA, or validate physical HBM behavior.

Frozen source-build identity:

- branch: `work/stage2n-a15-hbm-pipeline-integration`;
- source-build HEAD: `30cbf64e44fa99aa025f1a7456d739c8b5d4be6b`;
- accepted A15.4 top: `dlrm_f37x_rtl_kernel_stage2n_a15_v1`;
- accepted top SHA256:
  `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`;
- compute unit: `dlrm_a15_1`;
- connectivity: `dlrm_a15_1.m_axi_gmem:HBM[0]`;
- requested clock: 100 MHz.

## 2. User-returned target facts

The following facts were supplied by the user from the controlled target
environment. The raw target files are not present in this local worktree, so
they remain user-reported and pending the versioned v2 revalidation flow:

- target XO build/validation reported PASS;
- XO SHA256:
  `a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019`;
- Vitis link reported completion of synthesis, implementation, placement,
  routing, bitstream generation, and xclbin generation in `1:13:47`;
- xclbin: `dlrm_f37x_rtl_kernel_stage2n_a15_v1.xclbin`;
- xclbin SHA256:
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`;
- target timing was reported as WNS/TNS/WHS/THS `0.000/0.000/0.000/0.000 ns`;
- failed endpoints and unrouted nets were reported as zero.

These statements are not promoted to repository-accepted target evidence by
this local compatibility commit. The fixed-SHA artifacts must be checked by the
read-only v2 revalidation runner and the returned raw status/log/hash/report
files must be reviewed separately.

## 3. Root cause

The v1 xclbin validator treated every `IP_LAYOUT.m_ip_data` entry as a compute
unit and required the whole list to contain exactly one entry. The reported
Vitis 2020.2 xclbin instead contains 36 legal entries:

- one `IP_KERNEL` entry at index 0;
- three `IP_MEM_DDR4` shell entries;
- 32 `IP_MEM_HBM` shell entries.

The unique kernel entry is reported as:

- `m_type=IP_KERNEL`;
- `m_name=dlrm_f37x_rtl_kernel_stage2n_a15_v1:dlrm_a15_1`;
- `m_base_address=0x1800000`.

The one reported connection maps global argument index 0 to IP-layout index 0
and memory-topology index 0. Memory index 0 is tagged `HBM[0]` and marked used.
The v1 `len(m_ip_data) == 1` assertion therefore produced a false negative. It
did not identify an RTL, implementation, connectivity, or multiple-CU defect.

## 4. Validator v2 rule

`scripts/validate_stage2n_a15_5_xclbin_v2.py` keeps all v1 identity, ABI,
metadata, target, clock, and stale-signature gates, but interprets the Vitis
2020.2 layout correctly:

1. require the section `m_count` to equal the actual list length;
2. filter `IP_LAYOUT.m_ip_data` by `m_type == IP_KERNEL`;
3. require exactly one filtered kernel entry;
4. require the exact `kernel:CU` name;
5. require exactly one connectivity record and `arg_index == 0`;
6. require its IP index to reference that unique kernel entry;
7. require its memory index to be in range and dereference that exact memory;
8. require the referenced memory to be used `HBM[0]`;
9. allow unrelated shell DDR/HBM IP-layout entries;
10. retain rejection of stale A14 `LOOKUP_INDEX` and `RESULT0` through
    `RESULT3` arguments.

The validator deliberately does not require a particular memory `m_type` for
the connected memory because the authoritative binding is the in-range
connectivity index plus the referenced `m_tag=HBM[0]` and used flag. It does not
weaken the one-kernel, one-connection, one-memory-master, or one-bank contract.

## 5. Local validator tests

The v2 self-test constructs the reported Vitis 2020.2 layout shape: one kernel,
three DDR4 shell entries, and 32 HBM shell entries. The positive fixture passes.
The following mutations are rejected:

1. no `IP_KERNEL` entry;
2. a second `IP_KERNEL` entry;
3. wrong kernel name;
4. wrong compute-unit name;
5. wrong HBM bank;
6. unused HBM[0];
7. a second connectivity record;
8. wrong argument index;
9. wrong IP-layout index;
10. wrong memory-topology index;
11. stale `LOOKUP_INDEX` argument;
12. stale `RESULT0` argument.

Local result:

```text
PYTHON_SYNTAX=PASS
A15_5_XCLBIN_VALIDATOR_V2_SELF_TEST=PASS
POSITIVE_VITIS_2020_2_LAYOUT=PASS
NEGATIVE_CASES=12/12 PASS
BASH_SYNTAX=NOT_RUN
```

`bash -n` remains `NOT_RUN` because Bash is unavailable in this Windows local
environment. Static source inspection confirms that the revalidation runner
contains no active `v++`, `xbutil`, `xbmgmt`, SSH, SCP, or rsync command. This
does not substitute for a target-side Bash syntax check.

Retained local evidence:

| Evidence | SHA256 |
|---|---|
| `results/stage2n_a15_5/validator_v2_local/python_syntax.log` | `ada726f60fa37b661755c64c08b56485932e5ab7f076c0be246cdf991e76faaa` |
| `results/stage2n_a15_5/validator_v2_local/validator_v2_self_test.log` | `dc1d544e69bf607f78f1e2d911821ca962b87dd6768ca0b607f9bae2b7735486` |
| `results/stage2n_a15_5/validator_v2_local/validator_v2_local_status.txt` | `f0e9b1f3618898bf71c3e60eb198838ea32c72ddce71bba76182adaa00ebb357` |

## 6. Fixed-artifact revalidation flow

`scripts/revalidate_stage2n_a15_5_xclbin_v2.sh` is a non-overwriting,
user-executed target-side checker. It requires the exact XO and xclbin SHA256
values above and rejects changed frozen build inputs. It does not call `v++`
and sets:

```text
A15_5_TARGET_REBUILD_REQUIRED=NO
```

For the already-built artifact it performs only:

1. fixed-SHA and retained-log/status checks;
2. read-only `xclbinutil` metadata extraction;
3. v2 metadata validation;
4. read-only post-route report extraction from the retained routed DCP;
5. non-overwriting status and SHA256-manifest generation under
   `results/stage2n_a15_5/target_xclbin_revalidation_v2/`.

The intended controlled-environment invocation is:

```bash
export A15_5_REVALIDATE_CONFIRM=yes
bash scripts/revalidate_stage2n_a15_5_xclbin_v2.sh
```

Codex does not execute this command on the server. A target rebuild or relink is
not required for this validator-only correction.

## 7. Status boundary

Current repository status after local v2 development:

```text
A15_5_VALIDATOR_V2_LOCAL=PASS
A15_5_TARGET_XO_BUILD=USER_REPORTED_PASS_PENDING_V2_REVALIDATION
A15_5_TARGET_XO_VALIDATION=USER_REPORTED_PASS_PENDING_V2_REVALIDATION
A15_5_TARGET_LINK=USER_REPORTED_PASS_PENDING_V2_REVALIDATION
A15_5_XCLBIN=USER_REPORTED_PASS_PENDING_V2_REVALIDATION
A15_5_XCLBIN_VALIDATION=PENDING_V2_REVALIDATION
A15_5_TARGET_TIMING=USER_REPORTED_PASS_PENDING_RAW_EVIDENCE_REVIEW
A15_5_TARGET_REBUILD_REQUIRED=NO
A15_5_FPGA_PROGRAMMING=NOT_RUN
A15_5_HOST_EXECUTION=NOT_RUN
A15_5_PHYSICAL_HBM=NOT_VALIDATED
A15_5_BOARD=NOT_RUN
A15_5_PERFORMANCE=NOT_CLAIMED
NETWORK_ACCESS=NONE
SERVER_ACCESS=NONE
FPGA_DEVICE_ACCESS=NONE
```

No conclusion is made about physical HBM lookup correctness, FPGA execution,
Host runtime, bandwidth, latency, throughput, power, energy, speedup, or any
performance improvement.
