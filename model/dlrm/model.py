"""Standard PyTorch DLRM reference with an import-safe missing-runtime path."""

from pathlib import Path

from .config import DLRMConfig
from .interaction import torch_dot_interaction

try:
    import torch
    from torch import nn
    TORCH_AVAILABLE = True
except ImportError:
    torch = None
    nn = None
    TORCH_AVAILABLE = False


def _missing_torch():
    raise RuntimeError(
        "PyTorch is not installed in this local runtime; CPU and CUDA tests are SKIPPED"
    )


if TORCH_AVAILABLE:
    def _make_mlp(input_dim, layer_dims, activate_last=False):
        modules = []
        current = input_dim
        for index, output_dim in enumerate(layer_dims):
            modules.append(nn.Linear(current, output_dim))
            if index < len(layer_dims) - 1 or activate_last:
                modules.append(nn.ReLU())
            current = output_dim
        return nn.Sequential(*modules)


    class DLRM(nn.Module):
        """Configurable inference/training model faithful to the classic DLRM flow."""

        def __init__(self, config):
            super().__init__()
            if not isinstance(config, DLRMConfig):
                config = DLRMConfig.from_dict(config)
            self.config = config
            torch.manual_seed(config.seed)
            self.bottom_mlp = _make_mlp(
                config.num_dense_features, config.bottom_mlp, activate_last=True
            )
            self.embeddings = nn.ModuleList(
                nn.Embedding(table_size, config.embedding_dim)
                for table_size in config.table_sizes
            )
            self.top_mlp = _make_mlp(
                config.interaction_output_dim, config.top_mlp, activate_last=False
            )
            self.reset_parameters()

        def reset_parameters(self):
            generator = torch.Generator(device="cpu")
            generator.manual_seed(self.config.seed)
            for module in self.modules():
                if isinstance(module, nn.Linear):
                    nn.init.xavier_uniform_(module.weight, generator=generator)
                    nn.init.zeros_(module.bias)
                elif isinstance(module, nn.Embedding):
                    nn.init.uniform_(module.weight, -0.05, 0.05, generator=generator)

        def forward_stages(self, dense_features, categorical_ids):
            if dense_features.ndim != 2:
                raise ValueError("dense_features must have shape [batch, dense_features]")
            if categorical_ids.ndim != 2 or categorical_ids.shape[1] != self.config.num_tables:
                raise ValueError("categorical_ids must have shape [batch, num_tables]")
            bottom = self.bottom_mlp(dense_features)
            embedding_vectors = [
                table(categorical_ids[:, table_index])
                for table_index, table in enumerate(self.embeddings)
            ]
            interaction = torch_dot_interaction(bottom, embedding_vectors)
            logits = self.top_mlp(interaction).squeeze(-1)
            return {
                "bottom_output": bottom,
                "embedding_vectors": torch.stack(embedding_vectors, dim=1),
                "interaction_output": interaction,
                "logits": logits,
                "probabilities": torch.sigmoid(logits),
            }

        def forward(self, dense_features, categorical_ids, return_intermediates=False):
            stages = self.forward_stages(dense_features, categorical_ids)
            return stages if return_intermediates else stages["logits"]

        def parameter_summary(self):
            embedding_parameters = sum(
                parameter.numel() for table in self.embeddings
                for parameter in table.parameters()
            )
            total = sum(parameter.numel() for parameter in self.parameters())
            return {
                "total_parameters": int(total),
                "embedding_parameters": int(embedding_parameters),
                "dense_parameters": int(total - embedding_parameters),
                "embedding_capacity_values": int(self.config.embedding_capacity),
                "embedding_capacity_bytes": int(
                    self.config.embedding_capacity * next(self.parameters()).element_size()
                ),
            }

else:
    class DLRM:
        def __init__(self, *args, **kwargs):
            _missing_torch()


def save_checkpoint(model, config, path, extra=None):
    if not TORCH_AVAILABLE:
        _missing_torch()
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(
        {
            "config": config.to_dict(),
            "state_dict": model.state_dict(),
            "extra": extra or {},
        },
        path,
    )


def load_checkpoint(path, device="cpu"):
    if not TORCH_AVAILABLE:
        _missing_torch()
    payload = torch.load(Path(path), map_location=device)
    config = DLRMConfig.from_dict(payload["config"])
    model = DLRM(config).to(device)
    model.load_state_dict(payload["state_dict"])
    return model, config, payload.get("extra", {})


def torch_runtime_status():
    if not TORCH_AVAILABLE:
        return {
            "torch": "SKIPPED",
            "reason": "PyTorch is not installed",
            "cuda": "SKIPPED",
            "cuda_reason": "PyTorch is not installed",
        }
    return {
        "torch": "AVAILABLE",
        "version": torch.__version__,
        "cuda": "AVAILABLE" if torch.cuda.is_available() else "SKIPPED",
        "cuda_reason": "" if torch.cuda.is_available() else "CUDA is not available",
    }
