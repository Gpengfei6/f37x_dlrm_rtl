"""Forward-only and end-to-end benchmark helpers for DLRM software validation."""

import csv
import json
import time
from pathlib import Path

import numpy as np

from model.dlrm.interaction import numpy_dot_interaction, torch_dot_interaction
from model.dlrm.model import TORCH_AVAILABLE
from .metrics import classification_metrics, latency_summary

if TORCH_AVAILABLE:
    import torch


def _synchronize(device):
    if TORCH_AVAILABLE and str(device).startswith("cuda"):
        torch.cuda.synchronize(device)


def _numpy_staged_forward(model, dense, categorical):
    marks = {}
    start = time.perf_counter()
    bottom = model._mlp(dense, "bottom", model.config.bottom_mlp, model.state, True)
    marks["bottom_mlp"] = time.perf_counter() - start
    start = time.perf_counter()
    embeddings = [model.state["embedding_{}".format(index)][categorical[:, index]]
                  for index in range(model.config.num_tables)]
    marks["embedding_lookup"] = time.perf_counter() - start
    start = time.perf_counter()
    interaction = numpy_dot_interaction(bottom, embeddings)
    marks["feature_interaction"] = time.perf_counter() - start
    start = time.perf_counter()
    logits = model._mlp(interaction, "top", model.config.top_mlp, model.state, False)[:, 0]
    probabilities = 1.0 / (1.0 + np.exp(-np.clip(logits, -60, 60)))
    marks["top_mlp"] = time.perf_counter() - start
    return probabilities, marks


def _torch_staged_forward(model, dense, categorical, device):
    marks = {}
    _synchronize(device)
    start = time.perf_counter()
    bottom = model.bottom_mlp(dense)
    _synchronize(device)
    marks["bottom_mlp"] = time.perf_counter() - start
    start = time.perf_counter()
    embeddings = [table(categorical[:, index]) for index, table in enumerate(model.embeddings)]
    _synchronize(device)
    marks["embedding_lookup"] = time.perf_counter() - start
    start = time.perf_counter()
    interaction = torch_dot_interaction(bottom, embeddings)
    _synchronize(device)
    marks["feature_interaction"] = time.perf_counter() - start
    start = time.perf_counter()
    logits = model.top_mlp(interaction).squeeze(-1)
    probabilities = torch.sigmoid(logits)
    _synchronize(device)
    marks["top_mlp"] = time.perf_counter() - start
    return probabilities, marks


def benchmark_dataset(model, dataset, backend, device="cpu", batch_size=16, warmup_batches=2):
    """Benchmark preloaded data while reporting forward-only and host end-to-end latency."""
    if backend not in ("numpy-oracle", "torch"):
        raise ValueError("backend must be numpy-oracle or torch")
    if backend == "torch" and not TORCH_AVAILABLE:
        raise RuntimeError("PyTorch is unavailable")
    sample_count = int(len(dataset["labels"]))
    if sample_count == 0:
        raise ValueError("dataset is empty")
    batch_size = int(batch_size)
    if batch_size <= 0:
        raise ValueError("batch_size must be positive")

    def prepare(start, stop):
        dense = dataset["dense_features"][start:stop]
        categorical = dataset["categorical_ids"][start:stop]
        if backend == "torch":
            dense = torch.as_tensor(dense, dtype=torch.float32, device=device)
            categorical = torch.as_tensor(categorical, dtype=torch.long, device=device)
        return dense, categorical

    model_device = str(device)
    if backend == "torch":
        model.eval()
        context = torch.no_grad()
    else:
        from contextlib import nullcontext
        context = nullcontext()
    with context:
        for index in range(int(warmup_batches)):
            start = (index * batch_size) % sample_count
            stop = min(sample_count, start + batch_size)
            dense, categorical = prepare(start, stop)
            if backend == "torch":
                _torch_staged_forward(model, dense, categorical, device)
            else:
                _numpy_staged_forward(model, dense, categorical)

        probabilities, labels = [], []
        forward_latencies, end_to_end_latencies = [], []
        stage_totals = {name: 0.0 for name in (
            "embedding_lookup", "bottom_mlp", "feature_interaction", "top_mlp"
        )}
        for start in range(0, sample_count, batch_size):
            stop = min(sample_count, start + batch_size)
            end_to_end_start = time.perf_counter()
            dense, categorical = prepare(start, stop)
            _synchronize(device)
            forward_start = time.perf_counter()
            if backend == "torch":
                batch_probabilities, stage_times = _torch_staged_forward(
                    model, dense, categorical, device
                )
                batch_probabilities = batch_probabilities.detach().cpu().numpy()
            else:
                batch_probabilities, stage_times = _numpy_staged_forward(
                    model, dense, categorical
                )
            _synchronize(device)
            forward_latencies.append(time.perf_counter() - forward_start)
            probabilities.append(np.asarray(batch_probabilities))
            labels.append(np.asarray(dataset["labels"][start:stop]))
            end_to_end_latencies.append(time.perf_counter() - end_to_end_start)
            for name, value in stage_times.items():
                stage_totals[name] += value

    probability_array = np.concatenate(probabilities)
    label_array = np.concatenate(labels)
    e2e_total = float(sum(end_to_end_latencies))
    batch_count = len(end_to_end_latencies)
    report = {
        "status": "PASS",
        "backend": backend,
        "device": model_device,
        "batch_size": batch_size,
        "sample_count": sample_count,
        "batch_count": batch_count,
        "warmup_batches": int(warmup_batches),
        "latency_observation_unit": "one batch",
        "timing_scope": {
            "forward_only": "model stages after host/device tensor preparation",
            "end_to_end": "preloaded batch slicing/tensor preparation through probabilities returned to host",
            "gpu_synchronization": bool(str(device).startswith("cuda")),
        },
        "classification": classification_metrics(label_array, probability_array),
        "forward_latency": latency_summary(forward_latencies),
        "end_to_end_latency": latency_summary(end_to_end_latencies),
        "throughput_samples_per_second": sample_count / e2e_total,
        "stage_time_total_ms": {name: value * 1000.0 for name, value in stage_totals.items()},
        "stage_time_average_per_batch_ms": {
            name: value * 1000.0 / batch_count for name, value in stage_totals.items()
        },
        "dataset": dataset.get("metadata", {}),
        "claim_boundary": "software feasibility only; not an FPGA or production baseline",
    }
    return report


def write_benchmark_report(report, json_path, csv_path=None):
    json_path = Path(json_path)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if csv_path is not None:
        csv_path = Path(csv_path)
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        flat = {
            "status": report["status"],
            "backend": report["backend"],
            "device": report["device"],
            "batch_size": report["batch_size"],
            "sample_count": report["sample_count"],
            "auc": report["classification"]["auc"],
            "log_loss": report["classification"]["log_loss"],
            "throughput_samples_per_second": report["throughput_samples_per_second"],
        }
        for scope in ("forward_latency", "end_to_end_latency"):
            for name, value in report[scope].items():
                flat["{}_{}".format(scope, name)] = value
        for name, value in report["stage_time_total_ms"].items():
            flat["stage_{}_total_ms".format(name)] = value
        for name, value in report["stage_time_average_per_batch_ms"].items():
            flat["stage_{}_average_per_batch_ms".format(name)] = value
        with csv_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(flat))
            writer.writeheader()
            writer.writerow(flat)
