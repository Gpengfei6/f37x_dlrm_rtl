# Stage-1 validation payload

This directory defines a credential-free package for manual validation in the
user's personal server directory.  Codex has not uploaded, extracted, compiled,
or executed it on a server.

The payload contains the repository source, deterministic data, Python checks,
all eight testbenches, ordered Vivado/XSim scripts, source/testbench manifests,
and log collection tools.  It contains no `.xclbin`, HBM integration, XRT host,
credentials, or installer.

Generate or refresh the payload locally:

```powershell
python scripts/collect_validation_bundle.py --prepare-handoff
```

The user uploads `stage1_validation_payload.zip`, extracts it under the documented
personal directory, then follows `docs/SERVER_HANDOFF.md` or manually runs:

```bash
cd /home/chaosuan/gpf_f37x_dlrm/f37x_dlrm_rtl
python3 scripts/run_python_tests.py
vivado -mode batch -nojournal -nolog -source scripts/run_xsim_stage1.tcl
bash handoff/stage1_validation/collect_logs.sh
```

Return the generated log zip, summary JSON, XSim logs, and SHA-256 manifest.
