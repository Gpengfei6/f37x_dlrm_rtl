"""CLI for configurable local DLRM inference without any data download."""

import argparse
import csv
import json
import sys
from pathlib import Path

from model.data import generate_synthetic_dataset, load_criteo_tsv
from model.dlrm.config import DLRMConfig
from model.dlrm.model import DLRM, TORCH_AVAILABLE, load_checkpoint, torch_runtime_status
from model.dlrm.numpy_model import NumpyDLRM
from model.inference.benchmark import benchmark_dataset, write_benchmark_report


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config/dlrm_software_config.json")
    parser.add_argument("--backend", choices=("auto", "torch", "numpy-oracle"), default="auto")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--dataset", choices=("synthetic", "criteo"), default="synthetic")
    parser.add_argument("--criteo-path")
    parser.add_argument("--synthetic-mode", default="deterministic")
    parser.add_argument("--max-samples", type=int)
    parser.add_argument("--checkpoint")
    parser.add_argument("--batch-size", type=int)
    parser.add_argument("--warmup-batches", type=int, default=2)
    parser.add_argument("--json-out", default="results/dlrm_inference_summary.json")
    parser.add_argument("--csv-out", default="results/dlrm_inference_summary.csv")
    return parser.parse_args()


def write_skipped(report, json_path, csv_path):
    json_path = Path(json_path)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if csv_path:
        csv_path = Path(csv_path)
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        with csv_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=("status", "backend", "device", "reason"))
            writer.writeheader()
            writer.writerow({
                "status": report["status"], "backend": report["backend"],
                "device": report["device"],
                "reason": json.dumps(report["reason"], sort_keys=True),
            })


def main():
    args = parse_args()
    config = DLRMConfig.load(args.config)
    backend = args.backend
    if backend == "auto":
        backend = "torch" if TORCH_AVAILABLE else "numpy-oracle"
    runtime = torch_runtime_status()
    cuda_unavailable = (
        backend == "torch" and args.device.startswith("cuda")
        and runtime["cuda"] != "AVAILABLE"
    )
    if backend == "torch" and (not TORCH_AVAILABLE or cuda_unavailable):
        report = {
            "status": "SKIPPED",
            "backend": "torch",
            "device": args.device,
            "reason": runtime,
        }
        write_skipped(report, args.json_out, args.csv_out)
        print(json.dumps(report, indent=2))
        return 0
    if args.dataset == "criteo":
        if not args.criteo_path:
            raise ValueError("--criteo-path is required for local Criteo input")
        dataset = load_criteo_tsv(args.criteo_path, config, args.max_samples)
    else:
        dataset = generate_synthetic_dataset(
            config, args.max_samples, args.synthetic_mode
        )
    if backend == "torch":
        if args.checkpoint:
            model, checkpoint_config, _ = load_checkpoint(args.checkpoint, args.device)
            if checkpoint_config != config:
                raise ValueError("checkpoint and requested config differ")
        else:
            model = DLRM(config).to(args.device)
    else:
        model = NumpyDLRM.load(args.checkpoint) if args.checkpoint else NumpyDLRM(config)
        if model.config != config:
            raise ValueError("checkpoint and requested config differ")
    report = benchmark_dataset(
        model, dataset, backend, args.device,
        args.batch_size or config.batch_size, args.warmup_batches
    )
    report["parameter_summary"] = model.parameter_summary()
    write_benchmark_report(report, args.json_out, args.csv_out)
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
