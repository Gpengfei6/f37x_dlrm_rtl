#!/usr/bin/env python3
"""Dependency-light regression for software DLRM and trace feasibility tools."""

import argparse
import json
import sys
import tempfile
import traceback
from pathlib import Path

import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

from analysis.channel_mapping import simulate_channel_schedule
from analysis.embedding_trace import analyze_trace, build_embedding_trace, load_trace, save_trace
from analysis.request_coalescing import CoalescerConfig, simulate_coalescing
from model.data import generate_synthetic_dataset, load_criteo_tsv, resolve_criteo_input
from model.data.synthetic_dataset import TRACE_MODES
from model.dlrm.config import DLRMConfig
from model.dlrm.interaction import numpy_dot_interaction
from model.dlrm.model import (
    DLRM, TORCH_AVAILABLE, load_checkpoint, save_checkpoint, torch_runtime_status,
)
from model.dlrm.numpy_model import NumpyDLRM
from model.inference.benchmark import benchmark_dataset, write_benchmark_report
from model.inference.metrics import binary_auc, binary_log_loss


class TestRun:
    def __init__(self):
        self.tests = []

    def run(self, name, function):
        try:
            detail = function() or {}
            self.tests.append({"name": name, "status": "PASS", "detail": detail})
        except Exception as error:  # Keep the complete suite visible.
            self.tests.append({
                "name": name, "status": "FAIL", "reason": str(error),
                "traceback": traceback.format_exc(),
            })

    def skip(self, name, reason):
        self.tests.append({"name": name, "status": "SKIPPED", "reason": reason})


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def make_criteo_file(path, rows=5):
    lines = []
    for row in range(rows):
        dense = [str(row + index) if index % 3 else "" for index in range(13)]
        categorical = [format(row * 31 + index, "x") for index in range(26)]
        lines.append("\t".join([str(row % 2)] + dense + categorical))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config/dlrm_software_config.json")
    parser.add_argument("--output", default="results/software_feasibility_summary.json")
    args = parser.parse_args()
    config = DLRMConfig.load(args.config)
    run = TestRun()
    with tempfile.TemporaryDirectory(prefix="f37x_dlrm_software_") as raw_temp:
        temp = Path(raw_temp)

        def config_test():
            require(config.interaction_output_dim == 18, "interaction dimension mismatch")
            require(config.embedding_capacity == 2944, "embedding capacity mismatch")
            saved = temp / "config.json"
            config.save(saved)
            require(DLRMConfig.load(saved) == config, "configuration round trip differs")
            return {"interaction_output_dim": config.interaction_output_dim,
                    "embedding_capacity_values": config.embedding_capacity}
        run.run("config_roundtrip_and_dimensions", config_test)

        datasets = {mode: generate_synthetic_dataset(config, 64, mode) for mode in TRACE_MODES}

        def synthetic_test():
            for mode, dataset in datasets.items():
                repeated = generate_synthetic_dataset(config, 64, mode)
                require(np.array_equal(dataset["dense_features"], repeated["dense_features"]), mode)
                require(np.array_equal(dataset["categorical_ids"], repeated["categorical_ids"]), mode)
                require(dataset["metadata"]["source"] == "synthetic", mode)
            return {"modes": list(TRACE_MODES), "samples_per_mode": 64}
        run.run("synthetic_trace_classes_reproducible", synthetic_test)

        model = NumpyDLRM(config)

        def numpy_forward_test():
            dataset = datasets["deterministic"]
            stages = model.forward(
                dataset["dense_features"], dataset["categorical_ids"], True
            )
            repeated_logits = NumpyDLRM(config).forward(
                dataset["dense_features"], dataset["categorical_ids"]
            )
            require(stages["bottom_output"].shape == (64, config.embedding_dim), "bottom shape")
            require(stages["embedding_vectors"].shape == (64, config.num_tables, config.embedding_dim), "embedding shape")
            require(stages["interaction_output"].shape == (64, config.interaction_output_dim), "interaction shape")
            require(stages["logits"].shape == (64,), "logit shape")
            require(np.array_equal(stages["logits"], repeated_logits), "model seed is not reproducible")
            return model.parameter_summary()
        run.run("numpy_oracle_forward_and_intermediates", numpy_forward_test)

        def save_reload_test():
            path = temp / "numpy_model.npz"
            model.save(path)
            restored = NumpyDLRM.load(path)
            dataset = datasets["deterministic"]
            first = model.forward(dataset["dense_features"], dataset["categorical_ids"])
            second = restored.forward(dataset["dense_features"], dataset["categorical_ids"])
            require(np.array_equal(first, second), "save/reload output is not bit-identical")
            return {"checkpoint_bytes": path.stat().st_size}
        run.run("numpy_oracle_save_reload_exact", save_reload_test)

        def interaction_test():
            bottom = np.array([[1.0, 2.0]])
            embedding = [np.array([[3.0, 4.0]]), np.array([[5.0, 6.0]])]
            actual = numpy_dot_interaction(bottom, embedding)
            expected = np.array([[1.0, 2.0, 11.0, 17.0, 39.0]])
            require(np.array_equal(actual, expected), "lower-triangle interaction order differs")
        run.run("dot_interaction_known_vector", interaction_test)

        def criteo_test():
            criteo = temp / "day_0.tsv"
            make_criteo_file(criteo)
            loaded = load_criteo_tsv(temp, config)
            raw_ids = load_criteo_tsv(temp, config, map_to_table_sizes=False)
            require(loaded["dense_features"].shape == (5, config.num_dense_features), "dense load shape")
            require(loaded["categorical_ids"].shape == (5, config.num_tables), "cat load shape")
            require(loaded["metadata"]["source"] == "criteo_local", "source tag")
            require(raw_ids["categorical_ids"][-1, 0] > loaded["categorical_ids"][-1, 0],
                    "raw trace IDs were unexpectedly table-mapped")
            require(raw_ids["metadata"]["categorical_id_mapping"] == "raw_parsed_hex",
                    "raw ID metadata")
            try:
                resolve_criteo_input("https://example.invalid/criteo")
            except ValueError:
                pass
            else:
                raise AssertionError("URL was not rejected")
            return {"rows": 5, "local_path_guard": "PASS", "url_guard": "PASS"}
        run.run("local_criteo_loader_and_no_download_guard", criteo_test)

        def metric_test():
            require(binary_auc([0, 0, 1, 1], [0.1, 0.4, 0.35, 0.8]) == 0.75, "AUC")
            loss = binary_log_loss([0, 1], [0.25, 0.75])
            require(abs(loss - -np.log(0.75)) < 1e-12, "LogLoss")
            return {"auc_known_vector": 0.75, "log_loss_known_vector": loss}
        run.run("classification_metrics_known_vectors", metric_test)

        benchmark_report = {}

        def benchmark_test():
            nonlocal benchmark_report
            benchmark_report = benchmark_dataset(
                model, generate_synthetic_dataset(config, 128), "numpy-oracle",
                batch_size=config.batch_size, warmup_batches=2,
            )
            json_path, csv_path = temp / "benchmark.json", temp / "benchmark.csv"
            write_benchmark_report(benchmark_report, json_path, csv_path)
            require(json_path.stat().st_size > 0 and csv_path.stat().st_size > 0, "benchmark output")
            require(benchmark_report["throughput_samples_per_second"] > 0, "throughput")
            require(set(benchmark_report["stage_time_average_per_batch_ms"]) == {
                "embedding_lookup", "bottom_mlp", "feature_interaction", "top_mlp"
            }, "stage timing fields")
            return {"throughput_samples_per_second": benchmark_report["throughput_samples_per_second"],
                    "forward_latency": benchmark_report["forward_latency"]}
        run.run("numpy_benchmark_json_csv_and_timing_scopes", benchmark_test)

        traces = {}

        def trace_roundtrip_test():
            for mode, dataset in datasets.items():
                trace = build_embedding_trace(dataset["categorical_ids"], config.batch_size)
                traces[mode] = trace
                for extension in ("jsonl", "csv", "npy"):
                    path = temp / "{}_trace.{}".format(mode, extension)
                    save_trace(trace, path)
                    require(load_trace(path) == trace, "{} {} trace roundtrip".format(mode, extension))
            return {"formats": ["JSONL", "CSV", "NPY"], "records_per_trace": len(traces["deterministic"])}
        run.run("trace_export_all_formats_roundtrip", trace_roundtrip_test)

        def trace_statistics_test():
            high = analyze_trace(traces["high_duplicate"])
            low = analyze_trace(traces["low_duplicate"])
            require(set(high["windows"]) == {"1", "2", "4", "8", "16", "32", "64"}, "windows")
            require(high["windows"]["8"]["duplicate_ratio"] > low["windows"]["8"]["duplicate_ratio"], "duplicate ordering")
            require(high["hot_keys"] and high["per_table_skew"], "locality statistics absent")
            require("adjacent_window_reuse_ratio" in high["windows"]["8"], "adjacent reuse absent")
            require("frequency_histogram" in high["per_table_skew"]["0"], "frequency distribution absent")
            return {"high_duplicate_w8": high["windows"]["8"]["duplicate_ratio"],
                    "low_duplicate_w8": low["windows"]["8"]["duplicate_ratio"]}
        run.run("trace_window_locality_and_skew_statistics", trace_statistics_test)

        coalesced_entries = []

        def coalescing_test():
            nonlocal coalesced_entries
            reports = {}
            for policy in ("none", "fixed_count", "fixed_time", "dual", "adaptive"):
                report, entries = simulate_coalescing(
                    traces["high_duplicate"], CoalescerConfig(policy=policy)
                )
                reports[policy] = report
                require(report["tag_occupancy"]["maximum"] <= 256, "tag bound")
                require(report["wait_time"]["maximum"] <= 8.0, "wait bound")
                require(report["fanout_tag_occupancy"]["maximum"] <= 32, "fanout tag bound")
                if policy == "dual":
                    coalesced_entries = entries
            require(reports["none"]["read_reduction_count"] == 0, "none policy reduced reads")
            require(reports["dual"]["read_reduction_ratio"] > 0.25, "dual reduction unexpectedly low")
            require(min(value["timestamp"] for value in coalesced_entries) == 7.0,
                    "coalesced reads were issued before the first window closed")
            faster, _ = simulate_coalescing(
                traces["high_duplicate"], CoalescerConfig(policy="dual", arrival_rate=2.0)
            )
            require(faster["wait_time"]["average"] < reports["dual"]["wait_time"]["average"],
                    "arrival-rate parameter did not change wait")
            return {policy: {"read_reduction_ratio": value["read_reduction_ratio"],
                             "average_wait": value["wait_time"]["average"]}
                    for policy, value in reports.items()}
        run.run("five_bounded_coalescing_policies", coalescing_test)

        def channel_test():
            tested = 0
            for channels in (4, 8, 16, 32):
                for scheduler in ("modulo", "static_table", "per_channel_fifo_rr", "queue_aware", "age_queue"):
                    report = simulate_channel_schedule(coalesced_entries, channels, scheduler)
                    require(len(report["channel_request_counts"]) == channels, "channel count")
                    require(report["estimated_completion_cycles"] > 0, "completion")
                    require(0 <= report["aggregate_channel_utilization"] <= 1.0, "utilization")
                    tested += 1
            return {"configurations": tested, "channel_counts": [4, 8, 16, 32]}
        run.run("channel_mapping_and_scheduler_grid", channel_test)

        if TORCH_AVAILABLE:
            def torch_cpu_test():
                import torch
                torch_model = DLRM(config).cpu()
                dataset = datasets["deterministic"]
                dense = torch.as_tensor(dataset["dense_features"][:8])
                categorical = torch.as_tensor(dataset["categorical_ids"][:8], dtype=torch.long)
                stages = torch_model(dense, categorical, True)
                require(tuple(stages["logits"].shape) == (8,), "torch CPU shape")
                checkpoint = temp / "torch_model.pt"
                save_checkpoint(torch_model, config, checkpoint, {"test": True})
                restored, restored_config, extra = load_checkpoint(checkpoint)
                require(restored_config == config and extra["test"], "torch checkpoint metadata")
                require(torch.equal(torch_model(dense, categorical), restored(dense, categorical)),
                        "torch save/reload output")
                return {"torch_version": torch.__version__, "parameters": torch_model.parameter_summary()}
            run.run("pytorch_cpu_forward", torch_cpu_test)
        else:
            run.skip("pytorch_cpu_forward", "PyTorch is not installed in the local runtime")

        if TORCH_AVAILABLE:
            import torch
            cuda_available = torch.cuda.is_available()
        else:
            cuda_available = False
        if cuda_available:
            def torch_cuda_test():
                import torch
                torch_model = DLRM(config).cuda()
                dataset = datasets["deterministic"]
                dense = torch.as_tensor(dataset["dense_features"][:8], device="cuda")
                categorical = torch.as_tensor(dataset["categorical_ids"][:8], dtype=torch.long, device="cuda")
                logits = torch_model(dense, categorical)
                torch.cuda.synchronize()
                require(tuple(logits.shape) == (8,), "torch CUDA shape")
                return {"device": torch.cuda.get_device_name(0)}
            run.run("pytorch_cuda_forward", torch_cuda_test)
        else:
            run.skip("pytorch_cuda_forward", torch_runtime_status().get("cuda_reason", "CUDA unavailable"))

    counts = {
        status.lower(): sum(test["status"] == status for test in run.tests)
        for status in ("PASS", "FAIL", "SKIPPED")
    }
    summary = {
        "overall_status": "FAIL" if counts["fail"] else "PASS",
        "counts": counts,
        "runtime": torch_runtime_status(),
        "tests": run.tests,
        "numpy_benchmark": benchmark_report,
        "evidence_boundary": {
            "numpy_oracle": "structural/tool validation, not a PyTorch PASS or formal baseline",
            "synthetic_traces": "tool validation only; GATE-T1/T2/T3 remain INCONCLUSIVE",
            "real_criteo": "not present; no download attempted",
        },
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("software_feasibility: {} PASS={} FAIL={} SKIPPED={}".format(
        summary["overall_status"], counts["pass"], counts["fail"], counts["skipped"]
    ))
    for test in run.tests:
        print("{}: {}{}".format(test["name"], test["status"],
              " - " + test.get("reason", "") if test["status"] != "PASS" else ""))
    return 1 if counts["fail"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
