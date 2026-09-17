# Stage 2N-A18.3 extra-run (no program, no reset)

Date: 2026-09-17. Status: **RUNNER READY; BOARD EXTRA-RUN=NOT_RUN**.
`PERFORMANCE=NOT_CLAIMED`. Codex does not execute this runner.

User-authorized extra-run of the locked A18.3 five-tuple Host on the
already-loaded A18 xclbin. The runner never calls `xbutil program` or
`xbutil reset`. If CURRENT_UUID is not
`32a9c911-af15-47fc-90c8-0bfe3894a3ef`, it fails closed.

This extra-run cannot prove T>4, mapping, or cache. It repeats the
already-boarded five tuples.

## Files

- `scripts/run_stage2n_a18_3_extra_run_v1.sh`
- `scripts/check/check_stage2n_a18_3_extra_run_v1.py`
- `handoff/copy_a18_3_extra_run_v1.ps1` (user-only copy)

```text
python scripts/check/check_stage2n_a18_3_extra_run_v1.py
bash scripts/run_stage2n_a18_3_extra_run_v1.sh prepare
```

Linux extra-run (user):

```text
export A18_3_EXTRA_RUN_AUTHORIZED=yes
export A18_3_CONFIRM=yes
export A18_3_TARGET_INDEX=2
export A18_3_TARGET_BDF=0000:9b:00.1
export A18_3_TARGET_RENDER=/dev/dri/renderD129
export A18_3_XCLBIN=<reviewed a18_2_link_001 xclbin>
export A18_3_EXPECTED_HOST_ELF_SHA256=011a0b8f1630b9cadbba49150f3f28ebfd042cc5c77af840bcc00d27a403187f
export A18_3_EXPECTED_HOST_SOURCE_SHA256=f516896068f6664060cd392b954795f7fb877bdec66935f3163b8e38694dbaa9
bash scripts/run_stage2n_a18_3_extra_run_v1.sh extra-run
```

Do not treat Host-returned lookup 33 as a speedup.
