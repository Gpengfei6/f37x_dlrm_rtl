# Stage-1 server handoff

All actions in this document are for the user to execute manually.  They have
not been run by Codex.  Do not install missing tools during this validation.

## Upload

Upload only `handoff/stage1_validation/stage1_validation_payload.zip` to a
personal working directory.  The documented target is:

```text
/home/chaosuan/gpf_f37x_dlrm
```

Codex does not access or create that directory.

## Manual commands

```bash
mkdir -p /home/chaosuan/gpf_f37x_dlrm
cd /home/chaosuan/gpf_f37x_dlrm
unzip -o stage1_validation_payload.zip
cd f37x_dlrm_rtl

python3 scripts/run_python_tests.py
vivado -mode batch -nojournal -nolog -source scripts/run_xsim_stage1.tcl
python3 scripts/collect_validation_bundle.py --collect-logs
```

If direct XSim executables are already configured, the generated Tcl script
checks and invokes `xvlog`, `xelab`, and `xsim`; it never installs them.

## Expected output

- Python prints `run_python_tests: PASS` for 24 vectors.
- XSim prints one `tb_*: PASS` marker for each of eight testbenches.
- `results/validation_summary.json` distinguishes PASS/FAIL/SKIPPED.
- The collector creates `results/stage1_validation_logs.zip` and a SHA-256
  manifest.  GATE-1 remains unapproved until these real files are reviewed.

## Return to Codex

Return the following files without credentials:

- `results/stage1_validation_logs.zip`;
- `results/validation_summary.json`;
- `logs/xvlog_stage1.log`;
- every `logs/xelab_*.log` and `logs/xsim_*.log`;
- `results/source_manifest_sha256.json`;
- on failure, the complete earliest failing log and console transcript.
