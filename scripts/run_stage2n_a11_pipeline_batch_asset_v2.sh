#!/usr/bin/env bash
#
# Build and validate the Stage 2N-A11 real-model automatic-pipeline asset v2.
#
# This script performs no FPGA access, programming, or reset.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a11-real-model-batch-regression"
EXPECTED_SOURCE_PACKAGE_SHA256="b953289de8910f8402c4eefb79c516ab7d2468dba34fcc44532b9469cdcb2b3b"
EXPECTED_SOURCE_MANIFEST_SHA256="301bd88086bc42a0943af7b9b1867570a3e049b19e980e51ecc4390d69d8855d"

SOURCE_PACKAGE="${REPO_ROOT}/models/stage2m/stage2m_trained_hybrid_dlrm.f37xhd"
SOURCE_MANIFEST="${REPO_ROOT}/models/stage2m/stage2m_trained_hybrid_dlrm_manifest.json"
BUILDER="${REPO_ROOT}/python/build_stage2n_a11_pipeline_batch_asset_v2.py"

BUILD_DIR="${REPO_ROOT}/build/stage2n_a11/assets_v2"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a11/assets_v2"
EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a11_assets_v2"

OUTPUT_ASSET="${BUILD_DIR}/stage2n_a11_real_model_batch_v2.f37xpb"
OUTPUT_MANIFEST="${RESULT_DIR}/stage2n_a11_real_model_batch_v2_manifest.json"
OUTPUT_CSV="${RESULT_DIR}/stage2n_a11_real_model_batch_v2_samples.csv"
STATUS="${RESULT_DIR}/stage2n_a11_real_model_batch_v2_status.txt"

fail()
{
    local reason="$*"
    mkdir -p "${RESULT_DIR}"
    cat > "${STATUS}" <<EOF
STAGE2N_A11_PIPELINE_BATCH_ASSET_V2_FAILED
REASON=${reason}
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF
    echo "ERROR: ${reason}" >&2
    exit 40
}

require_file()
{
    local file="$1"
    [[ -s "${file}" ]] ||
        fail "required file missing or empty: ${file}"
}

require_exact()
{
    local file="$1"
    local line="$2"
    grep -Fxq "${line}" "${file}" ||
        fail "missing exact line in ${file}: ${line}"
}

cd "${REPO_ROOT}"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(git rev-parse HEAD)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "wrong branch: ${CURRENT_BRANCH}"

for file in \
    "${SOURCE_PACKAGE}" \
    "${SOURCE_MANIFEST}" \
    "${BUILDER}"
do
    require_file "${file}"
done

SOURCE_PACKAGE_SHA256="$(sha256sum "${SOURCE_PACKAGE}" | awk '{print $1}')"
SOURCE_MANIFEST_SHA256="$(sha256sum "${SOURCE_MANIFEST}" | awk '{print $1}')"

[[ "${SOURCE_PACKAGE_SHA256}" == "${EXPECTED_SOURCE_PACKAGE_SHA256}" ]] ||
    fail "source package SHA256 mismatch"
[[ "${SOURCE_MANIFEST_SHA256}" == "${EXPECTED_SOURCE_MANIFEST_SHA256}" ]] ||
    fail "source manifest SHA256 mismatch"

python3 - "${SOURCE_MANIFEST}" <<'PY'
from __future__ import print_function
import json
import sys

path = sys.argv[1]
with open(path, "r") as f:
    value = json.load(f)

checks = [
    (value["format"] == "F37XHD1", "format"),
    (value["format_version"] == 1, "format_version"),
    (value["dataset"]["test_samples"] == 256, "test_samples"),
    (
        value["model"]["architecture"]["bottom_mlp"] == [8, 16, 8],
        "bottom_mlp",
    ),
    (
        value["model"]["architecture"]["top_mlp"] == [18, 32, 16, 1],
        "top_mlp",
    ),
    (
        value["model"]["architecture"]["embedding_tables"]
        == [64, 80, 96, 128],
        "embedding_tables",
    ),
    (
        value["model"]["architecture"]["interaction_output_dim"] == 18,
        "interaction_output_dim",
    ),
    (
        value["package"]["bottom_weight_values"]
        + value["package"]["top_weight_values"]
        == 1360,
        "weight_count",
    ),
    (
        value["package"]["bottom_bias_values"]
        + value["package"]["top_bias_values"]
        == 73,
        "bias_count",
    ),
    (
        value["quantization"]["quantized_test_correct"] == 228,
        "quantized_test_correct",
    ),
    (
        value["quantization"]["quantized_test_accuracy"] == 0.890625,
        "quantized_test_accuracy",
    ),
    (
        value["quantization"]["interaction_shift"] == 11,
        "interaction_shift",
    ),
]
for ok, name in checks:
    if not ok:
        raise SystemExit("manifest contract failed: " + name)

print("STAGE2N_A11_SOURCE_MANIFEST_CONTRACT_PASS")
PY

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${EVIDENCE_DIR}"

python3 "${BUILDER}" \
    --source-package "${SOURCE_PACKAGE}" \
    --output-asset "${OUTPUT_ASSET}" \
    --manifest "${OUTPUT_MANIFEST}" \
    --samples-csv "${OUTPUT_CSV}" \
    --status "${STATUS}" ||
    fail "A11 pipeline batch asset builder failed"

for file in \
    "${OUTPUT_ASSET}" \
    "${OUTPUT_MANIFEST}" \
    "${OUTPUT_CSV}" \
    "${STATUS}"
do
    require_file "${file}"
done

require_exact "${STATUS}" "STAGE2N_A11_PIPELINE_BATCH_ASSET_V2_PASS"
require_exact "${STATUS}" "MODEL_SHAPE=8x16x8_interact18_32x16x1"
require_exact "${STATUS}" "SAMPLE_COUNT=256"
require_exact "${STATUS}" "DESCRIPTOR_COUNT=5"
require_exact "${STATUS}" "WEIGHT_COUNT=1360"
require_exact "${STATUS}" "BIAS_COUNT=73"
require_exact "${STATUS}" "EMBEDDING_TABLES=4"
require_exact "${STATUS}" "EMBEDDING_DIM=8"
require_exact "${STATUS}" "DENSE_DIM=8"
require_exact "${STATUS}" "INTERACTION_DIM=18"
require_exact "${STATUS}" "INTERACTION_SHIFT=11"
require_exact "${STATUS}" "FINAL_DESCRIPTOR_TAG=4"
require_exact "${STATUS}" "SOFTWARE_BOTTOM_EXACT=256"
require_exact "${STATUS}" "SOFTWARE_INTERACTION_EXACT=256"
require_exact "${STATUS}" "SOFTWARE_TOP_EXACT=256"
require_exact "${STATUS}" "SOFTWARE_CLASSIFICATION_CORRECT=228"
require_exact "${STATUS}" "SOFTWARE_CLASSIFICATION_ACCURACY=0.890625"
require_exact "${STATUS}" "A10_PIPELINE_VERSION=0x00024E11"
require_exact "${STATUS}" "NO_FPGA_ACCESS=1"
require_exact "${STATUS}" "NO_FPGA_PROGRAMMING_OR_RESET=1"

CSV_ROWS="$(
    awk 'NR > 1 {count++} END {print count+0}' "${OUTPUT_CSV}"
)"
CSV_CORRECT="$(
    awk -F, 'NR > 1 && $4 == 1 {count++} END {print count+0}' "${OUTPUT_CSV}"
)"
[[ "${CSV_ROWS}" == "256" ]] ||
    fail "sample CSV row count mismatch: ${CSV_ROWS}"
[[ "${CSV_CORRECT}" == "228" ]] ||
    fail "sample CSV classification count mismatch: ${CSV_CORRECT}"

python3 - "${OUTPUT_ASSET}" "${STATUS}" <<'PY'
from __future__ import print_function
import hashlib
import re
import string
import sys

asset_path = sys.argv[1]
status_path = sys.argv[2]

with open(asset_path, "rb") as f:
    actual = hashlib.sha256(f.read()).hexdigest()
with open(status_path, "r") as f:
    text = f.read()

match = re.search(r"^OUTPUT_ASSET_SHA256=([0-9a-f]{64})$", text, re.M)
if match is None:
    raise SystemExit("output asset status SHA256 is missing or malformed")
stored = match.group(1)
valid = (
    len(stored) == 64
    and all(c in string.hexdigits for c in stored)
    and stored == actual
)
print("OUTPUT_ASSET_SHA256_LENGTH={}".format(len(stored)))
print("OUTPUT_ASSET_SHA256_VALID_HEX={}".format(
    int(all(c in string.hexdigits for c in stored))
))
print("OUTPUT_ASSET_SHA256_MATCHES_ACTUAL={}".format(int(stored == actual)))
if not valid:
    raise SystemExit("output asset SHA256 verification failed")
PY

cp -f "${STATUS}" "${EVIDENCE_DIR}/"
cp -f "${OUTPUT_MANIFEST}" "${EVIDENCE_DIR}/"
cp -f "${OUTPUT_CSV}" "${EVIDENCE_DIR}/"

(
    cd "${EVIDENCE_DIR}"
    sha256sum \
        stage2n_a11_real_model_batch_v2_status.txt \
        stage2n_a11_real_model_batch_v2_manifest.json \
        stage2n_a11_real_model_batch_v2_samples.csv \
        > stage2n_a11_pipeline_batch_asset_v2_manifest.sha256
)

echo "============================================================"
echo "STAGE2N_A11_PIPELINE_BATCH_ASSET_V2_PASS"
echo "GIT_BRANCH=${CURRENT_BRANCH}"
echo "GIT_HEAD=${CURRENT_HEAD}"
echo "MODEL_SHAPE=8x16x8_interact18_32x16x1"
echo "SAMPLE_COUNT=256"
echo "DESCRIPTOR_COUNT=5"
echo "WEIGHT_COUNT=1360"
echo "BIAS_COUNT=73"
echo "SOFTWARE_BOTTOM_EXACT=256"
echo "SOFTWARE_INTERACTION_EXACT=256"
echo "SOFTWARE_TOP_EXACT=256"
echo "SOFTWARE_CLASSIFICATION_CORRECT=228"
echo "SOFTWARE_CLASSIFICATION_ACCURACY=0.890625"
echo "OUTPUT_ASSET=${OUTPUT_ASSET}"
echo "OUTPUT_MANIFEST=${OUTPUT_MANIFEST}"
echo "OUTPUT_CSV=${OUTPUT_CSV}"
echo "STATUS=${STATUS}"
echo "EVIDENCE_DIR=${EVIDENCE_DIR}"
echo "NO FPGA ACCESS WAS PERFORMED"
echo "============================================================"
