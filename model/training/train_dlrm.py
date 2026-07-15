"""Small deterministic PyTorch training CLI; no dataset download is performed."""

import argparse
import json
from pathlib import Path

from model.data import generate_synthetic_dataset, load_criteo_tsv
from model.dlrm.config import DLRMConfig
from model.dlrm.model import DLRM, TORCH_AVAILABLE, save_checkpoint, torch_runtime_status


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="config/dlrm_software_config.json")
    parser.add_argument("--dataset", choices=("synthetic", "criteo"), default="synthetic")
    parser.add_argument("--criteo-path")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--epochs", type=int, default=1)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--checkpoint", default="results/dlrm_software_checkpoint.pt")
    parser.add_argument("--summary", default="results/dlrm_training_summary.json")
    args = parser.parse_args()
    runtime = torch_runtime_status()
    cuda_unavailable = args.device.startswith("cuda") and runtime["cuda"] != "AVAILABLE"
    if not TORCH_AVAILABLE or cuda_unavailable:
        report = {"status": "SKIPPED", "device": args.device, "reason": runtime}
        Path(args.summary).parent.mkdir(parents=True, exist_ok=True)
        Path(args.summary).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 0
    import numpy as np
    import torch

    config = DLRMConfig.load(args.config)
    if args.dataset == "criteo":
        if not args.criteo_path:
            raise ValueError("--criteo-path is required; data is never downloaded")
        dataset = load_criteo_tsv(args.criteo_path, config)
    else:
        dataset = generate_synthetic_dataset(config)
    torch.manual_seed(config.seed)
    model = DLRM(config).to(args.device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.learning_rate)
    loss_function = torch.nn.BCEWithLogitsLoss()
    losses = []
    for _ in range(args.epochs):
        order = np.arange(len(dataset["labels"]))
        for start in range(0, len(order), config.batch_size):
            selection = order[start:start + config.batch_size]
            dense = torch.as_tensor(
                dataset["dense_features"][selection], dtype=torch.float32, device=args.device
            )
            categorical = torch.as_tensor(dataset["categorical_ids"][selection], dtype=torch.long, device=args.device)
            labels = torch.as_tensor(
                dataset["labels"][selection], dtype=torch.float32, device=args.device
            )
            optimizer.zero_grad(set_to_none=True)
            loss = loss_function(model(dense, categorical), labels)
            loss.backward()
            optimizer.step()
            losses.append(float(loss.detach().cpu()))
    save_checkpoint(model, config, args.checkpoint, {"losses": losses})
    report = {
        "status": "PASS", "device": args.device, "epochs": args.epochs,
        "final_loss": losses[-1], "checkpoint": str(Path(args.checkpoint).resolve()),
        "dataset": dataset["metadata"],
    }
    Path(args.summary).parent.mkdir(parents=True, exist_ok=True)
    Path(args.summary).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
