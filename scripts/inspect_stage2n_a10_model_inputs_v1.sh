#!/usr/bin/env bash
#
# Stage 2N-A10 v1 — read-only inventory of reusable Stage 2M model assets.
#
# Purpose:
#   Locate the existing quantized DLRM model package, software golden code,
#   sample inputs, and Stage 2M host-side regression assets before building
#   the A10 automatic-pipeline batch regression.
#
# Safety:
#   - no Vivado/Vitis build;
#   - no xclbin link;
#   - no xbutil;
#   - no render-node access;
#   - no FPGA programming or reset;
#   - no tracked file is modified.
#
# Usage:
#   bash scripts/inspect_stage2n_a10_model_inputs_v1.sh
#

set -Eeuo pipefail

REPO_ROOT="${1:-/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n}"

cd "${REPO_ROOT}" || {
    echo "ERROR: cannot enter repository: ${REPO_ROOT}" >&2
    exit 2
}

OUT_DIR="results/stage2n_a10_inventory_v1"
OUT_FILE="${OUT_DIR}/stage2n_a10_model_inputs_inventory_v1.txt"

mkdir -p "${OUT_DIR}"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(git rev-parse HEAD)"

STAGE2M_COMMIT="b3fc997"
if ! git cat-file -e "${STAGE2M_COMMIT}^{commit}" 2>/dev/null; then
    STAGE2M_COMMIT=""
fi

{
    echo "============================================================"
    echo "Stage 2N-A10 v1 Model/Input Inventory"
    echo "TIME=$(date -Is)"
    echo "REPO=${REPO_ROOT}"
    echo "BRANCH=${CURRENT_BRANCH}"
    echo "HEAD=${CURRENT_HEAD}"
    echo "STAGE2M_COMMIT=${STAGE2M_COMMIT:-NOT_FOUND}"
    echo
    echo "READ_ONLY_INVENTORY=1"
    echo "NO_BUILD=1"
    echo "NO_XCLBIN_LINK=1"
    echo "NO_FPGA_ACCESS=1"
    echo "============================================================"
    echo

    echo "========== CURRENT TRACKED CANDIDATES =========="
    git ls-files |
        grep -Ei \
            '(^|/)(stage2m|model|models|package|golden|reference|inference|dataset|sample|vector|quant|dlrm|embedding|interaction|host)(/|_|\.|$)' |
        grep -Ei \
            '\.(c|cc|cpp|h|hpp|py|sh|tcl|sv|v|json|csv|tsv|txt|md|bin|dat|npy|npz|pt|pth)$' |
        sort -u ||
        true

    echo
    echo "========== CURRENT UNTRACKED CANDIDATES =========="
    git status --porcelain |
        sed -n 's/^?? //p' |
        grep -Ei \
            '(^|/)(stage2m|model|models|package|golden|reference|inference|dataset|sample|vector|quant|dlrm|embedding|interaction|host)(/|_|\.|$)' |
        sort -u ||
        true

    echo
    echo "========== STAGE 2M TREE CANDIDATES =========="
    if [[ -n "${STAGE2M_COMMIT}" ]]; then
        git ls-tree -r --name-only "${STAGE2M_COMMIT}" |
            grep -Ei \
                '(^|/)(stage2m|model|models|package|golden|reference|inference|dataset|sample|vector|quant|dlrm|embedding|interaction|host)(/|_|\.|$)' |
            grep -Ei \
                '\.(c|cc|cpp|h|hpp|py|sh|tcl|sv|v|json|csv|tsv|txt|md|bin|dat|npy|npz|pt|pth)$' |
            sort -u ||
            true
    else
        echo "STAGE2M_COMMIT_NOT_FOUND"
    fi

    echo
    echo "========== STAGE 2M COMMIT SUMMARY =========="
    if [[ -n "${STAGE2M_COMMIT}" ]]; then
        git show \
            --no-renames \
            --stat \
            --oneline \
            --summary \
            "${STAGE2M_COMMIT}" ||
            true
    else
        echo "STAGE2M_COMMIT_NOT_FOUND"
    fi

    echo
    echo "========== KEYWORD HITS IN CURRENT TRACKED TEXT =========="
    grep -RInE \
        --exclude-dir=.git \
        --exclude-dir=build \
        --exclude-dir=results \
        --exclude-dir=logs \
        --exclude-dir=server_results \
        --exclude='*.xclbin' \
        --exclude='*.xo' \
        --exclude='*.dcp' \
        --exclude='*.bit' \
        --exclude='*.bundle' \
        '(768/768|model[_ -]?pack|golden|quantized|quantisation|quantization|sample[_ -]?count|batch[_ -]?inference|bottom[_ -]?mlp|top[_ -]?mlp|feature[_ -]?interaction)' \
        . 2>/dev/null |
        head -n 500 ||
        true

    echo
    echo "========== LIKELY DATA FILES BY SIZE =========="
    find . \
        -path './.git' -prune -o \
        -path './build' -prune -o \
        -path './logs' -prune -o \
        -path './results' -prune -o \
        -path './server_results' -prune -o \
        -type f \
        \( \
            -iname '*.json' -o \
            -iname '*.csv' -o \
            -iname '*.tsv' -o \
            -iname '*.txt' -o \
            -iname '*.bin' -o \
            -iname '*.dat' -o \
            -iname '*.npy' -o \
            -iname '*.npz' \
        \) \
        -printf '%s\t%p\n' |
        sort -nr |
        head -n 200 ||
        true

    echo
    echo "========== LIKELY HOST/GOLDEN ENTRY POINTS =========="
    find host software scripts tools tests tb \
        -type f \
        \( \
            -iname '*.cpp' -o \
            -iname '*.cc' -o \
            -iname '*.c' -o \
            -iname '*.py' -o \
            -iname '*.sh' \
        \) \
        2>/dev/null |
        grep -Ei \
            '(stage2m|dlrm|golden|model|inference|regression|batch|interaction|quant)' |
        sort -u ||
        true

    echo
    echo "========== EXISTING A7/A8/A9 ARTIFACT POINTERS =========="
    for path in \
        "build/stage2n_a8/package_v3/dlrm_f37x_rtl_kernel_stage2n_a7.xo" \
        "build/stage2n_a8/link_v3/hw/dlrm_f37x_rtl_kernel_stage2n_a7.xclbin" \
        "results/stage2n_a8/link_v3/stage2n_a8_f37x_link_v3_status.txt" \
        "results/stage2n_a9_board_v3"
    do
        if [[ -e "${path}" ]]; then
            if [[ -f "${path}" ]]; then
                stat -c '%s bytes  %n' "${path}"
            else
                echo "DIRECTORY  ${path}"
            fi
        else
            echo "MISSING  ${path}"
        fi
    done

    echo
    echo "========== RECOMMENDED A10 INPUT CLASSES =========="
    echo "1. Quantized model descriptors"
    echo "2. Weight and bias arrays"
    echo "3. Embedding vectors or embedding lookup outputs"
    echo "4. Dense input samples"
    echo "5. CPU golden interaction and top-MLP implementation"
    echo "6. Expected per-sample final outputs"
    echo "7. Existing Stage 2M batch-pass evidence"
    echo
    echo "STAGE2N_A10_MODEL_INPUTS_INVENTORY_V1_COMPLETE"
} | tee "${OUT_FILE}"

echo
echo "OUTPUT=${REPO_ROOT}/${OUT_FILE}"
echo "NO FPGA ACCESS WAS PERFORMED"
