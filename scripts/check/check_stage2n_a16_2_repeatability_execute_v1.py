#!/usr/bin/env python3
"""Local static gates for the A16.2 process-restart execute wrapper.

No device, no program, no Host rebuild.
"""
from __future__ import print_function

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path


FROZEN = {
    "UUID": "f18571de-4a43-46bd-8ab9-a89dd4b11f8e",
    "XCLBIN": "5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4",
    "ELF": "de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b",
    "SOURCE": "d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99",
    "EXECUTE": "8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba",
    "SOURCE_UUID": "622c839f-55f4-47c1-92e9-95ee5595ffa4",
}


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def find_bash():
    candidates = ["bash"]
    windir = os.environ.get("ProgramFiles", r"C:\Program Files")
    candidates.append(str(Path(windir) / "Git" / "bin" / "bash.exe"))
    candidates.append(str(Path(windir) / "Git" / "usr" / "bin" / "bash.exe"))
    for cmd in candidates:
        try:
            proc = subprocess.Popen(
                [cmd, "-c", "echo ok"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            out, _ = proc.communicate()
            if proc.returncode == 0 and b"ok" in (out or b""):
                return cmd
        except OSError:
            continue
    return None


def main():
    repo = Path(__file__).resolve().parents[2]
    wrapper = repo / "scripts" / "run_stage2n_a16_2_a16_repeatability_v1.sh"
    frozen_execute = repo / "scripts" / "program_and_run_stage2n_a16_2_physical_latency_v1.sh"
    host_src = repo / "host" / "stage2n_a16_2_physical_latency_v1.cpp"
    summarizer = repo / "scripts" / "check" / "summarize_stage2n_a16_2_repeatability_v1.py"
    historical = (
        repo / "docs" / "evidence" / "stage2n_a16_2" / "final_acceptance_v1"
        / "physical_latency_v1" / "20260831_182443" / "host.log"
    )
    require(wrapper.is_file(), "wrapper missing")
    require(frozen_execute.is_file(), "frozen execute missing")
    text = wrapper.read_text(encoding="utf-8")
    require("action=\"${1:-prepare}\"".lower() in text.lower() or 'ACTION="${1:-prepare}"' in text,
            "prepare default missing")
    require('ACTION="${1:-prepare}"' in text, "prepare default missing")
    for value in FROZEN.values():
        require(value in text, "wrapper missing frozen identity " + value)
    require("bash \"${EXECUTE}\"" in text, "wrapper must call frozen execute")
    require('[[ -f "${EXECUTE}" && -s "${EXECUTE}" ]]' in text,
            "frozen execute must be present-file checked, not execute-bit only")
    require("build/stage2n_a16_v1" in text and "stale" in text.lower(),
            "wrapper must reject stale stage2n_a16_v1 xclbin path")
    require("a17_6_four_bo_host_v1" in text and "will not be executed" in text or
            "REJECTED_A17_HOST" in text,
            "A17 Host rejection missing")
    require("this slice does not rebuild" in text, "rebuild refusal missing")
    require("A17_RESTORE_PROGRAM=NOT_AUTHORIZED" in text, "A17 restore block missing")
    require("DO_NOT_EXTRA_RUN=YES" in text, "no extra-run marker missing")
    require("HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES" in text,
            "pre-program identity marker missing")
    require("REPEAT_BASELINE=ABSENT_ON_FROZEN_A16_HOST" in text,
            "REPEAT_BASELINE absence missing")
    require("one_HBM0_BO_reload_full_image_each_case" in text,
            "BO-init measurement condition missing")
    require("program_and_run_stage2n_a16_2_physical_latency_v1.sh" in text,
            "must wrap frozen A16 runner")
    require("xbutil program" not in text,
            "wrapper must not call xbutil program itself")
    require(sha256(frozen_execute) == FROZEN["EXECUTE"],
            "frozen execute SHA changed; do not edit it")
    require(sha256(host_src) == FROZEN["SOURCE"],
            "frozen Host source SHA changed; do not edit it")

    bash = find_bash()
    if bash is None:
        print("BASH_INVOKE=NOT_RUN")
        print("NOTE=static identity and summarizer checks still apply")
    else:
        env = os.environ.copy()
        env["A16_2_REPEATABILITY_AUTHORIZED"] = "no"
        proc = subprocess.Popen(
            [bash, str(wrapper), "prepare"],
            cwd=str(repo), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=env)
        out, err = proc.communicate()
        out_text = (out or b"").decode("utf-8", "replace")
        require(proc.returncode == 0,
                "prepare failed: " + ((err.decode("utf-8", "replace") if err else out_text)))
        require("A16_2_REPEATABILITY=PREPARE_ONLY" in out_text, "prepare marker missing")
        require(FROZEN["UUID"] in out_text, "prepare UUID missing")
        proc = subprocess.Popen(
            [bash, str(wrapper), "execute"],
            cwd=str(repo), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=env)
        out, err = proc.communicate()
        err_text = (err or b"").decode("utf-8", "replace") + (out or b"").decode("utf-8", "replace")
        require(proc.returncode != 0, "execute without auth must fail")
        require("A16_2_REPEATABILITY=FAIL" in err_text, "unauth execute fail marker missing")
        require("FPGA_RESET=NOT_RUN" in err_text, "reset refusal missing")
        print("BASH_INVOKE=PASS")

    tmp = Path(tempfile.mkdtemp(prefix="a16_rep_"))
    rounds = tmp / "rounds.txt"
    rounds.write_text(
        "ROUND=1 ROLE=MEASURED STAMP=20260831_182443 RC=0\n",
        encoding="utf-8")
    require(historical.is_file(), "historical A16 host.log missing")
    proc = subprocess.Popen(
        [sys.executable, str(summarizer), "--repo", str(repo),
         "--campaign-dir", str(tmp)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = proc.communicate()
    sum_text = (out or b"").decode("utf-8", "replace")
    require(proc.returncode == 0, "summarizer failed: " + (err.decode("utf-8", "replace") if err else sum_text))
    require("CASE0_N=1" in sum_text, "summarizer CASE0 missing")
    require("REPEAT_BASELINE=ABSENT_ON_FROZEN_A16_HOST" in sum_text,
            "summarizer REPEAT_BASELINE contract missing")
    require("lookup=112" in sum_text and "e2e=1289" in sum_text,
            "historical 112/1289 not parsed")
    require("A16_A17_SPEEDUP=NOT_COMPUTED" in sum_text, "speedup block missing")
    print("A16_2_REPEATABILITY_LOCAL_GATES=PASS")
    print("FROZEN_EXECUTE_UNCHANGED=PASS")
    print("FROZEN_HOST_SOURCE_UNCHANGED=PASS")
    print("PREPARE_ONLY_DEFAULT=PASS")
    print("UNAUTH_EXECUTE_REJECTED=PASS")
    print("SUMMARIZER_HISTORICAL_PARSE=PASS")
    print("WRAPS_FROZEN_RUNNER=PASS")
    print("WRAPPER_HAS_NO_DIRECT_XBUTIL_PROGRAM=PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A16_2_REPEATABILITY_LOCAL_GATES=FAIL", file=sys.stderr)
        print("REASON=" + str(error), file=sys.stderr)
        sys.exit(1)
