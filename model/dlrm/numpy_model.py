"""Independent NumPy DLRM oracle used when PyTorch is unavailable locally."""

import json
from pathlib import Path

import numpy as np

from .config import DLRMConfig
from .interaction import numpy_dot_interaction


class NumpyDLRM:
    def __init__(self, config, state=None):
        if not isinstance(config, DLRMConfig):
            config = DLRMConfig.from_dict(config)
        self.config = config
        self.dtype = np.dtype(config.dtype)
        if state is None:
            self.state = self._initialize_state()
        else:
            self.state = {name: np.asarray(value) for name, value in state.items()}

    def _initialize_state(self):
        rng = np.random.default_rng(self.config.seed)
        state = {}
        current = self.config.num_dense_features
        for index, output_dim in enumerate(self.config.bottom_mlp):
            state["bottom_weight_{}".format(index)] = (
                rng.standard_normal((current, output_dim)) * 0.05
            ).astype(self.dtype)
            state["bottom_bias_{}".format(index)] = np.zeros(output_dim, self.dtype)
            current = output_dim
        for index, table_size in enumerate(self.config.table_sizes):
            state["embedding_{}".format(index)] = rng.uniform(
                -0.05, 0.05, (table_size, self.config.embedding_dim)
            ).astype(self.dtype)
        current = self.config.interaction_output_dim
        for index, output_dim in enumerate(self.config.top_mlp):
            state["top_weight_{}".format(index)] = (
                rng.standard_normal((current, output_dim)) * 0.05
            ).astype(self.dtype)
            state["top_bias_{}".format(index)] = np.zeros(output_dim, self.dtype)
            current = output_dim
        return state

    @staticmethod
    def _mlp(values, prefix, dims, state, activate_last):
        output = values
        for index, _ in enumerate(dims):
            output = (
                output @ state["{}_weight_{}".format(prefix, index)]
                + state["{}_bias_{}".format(prefix, index)]
            )
            if index < len(dims) - 1 or activate_last:
                output = np.maximum(output, 0)
        return output

    def forward_stages(self, dense_features, categorical_ids):
        dense_features = np.asarray(dense_features, dtype=self.dtype)
        categorical_ids = np.asarray(categorical_ids, dtype=np.int64)
        if dense_features.ndim != 2 or dense_features.shape[1] != self.config.num_dense_features:
            raise ValueError("dense feature shape mismatch")
        if categorical_ids.shape != (dense_features.shape[0], self.config.num_tables):
            raise ValueError("categorical ID shape mismatch")
        bottom = self._mlp(
            dense_features, "bottom", self.config.bottom_mlp,
            self.state, activate_last=True
        )
        embedding_vectors = []
        for index, table_size in enumerate(self.config.table_sizes):
            ids = categorical_ids[:, index]
            if np.any(ids < 0) or np.any(ids >= table_size):
                raise ValueError("categorical ID outside table {}".format(index))
            embedding_vectors.append(self.state["embedding_{}".format(index)][ids])
        interaction = numpy_dot_interaction(bottom, embedding_vectors)
        logits = self._mlp(
            interaction, "top", self.config.top_mlp,
            self.state, activate_last=False
        )[:, 0]
        probabilities = 1.0 / (1.0 + np.exp(-np.clip(logits, -60, 60)))
        return {
            "bottom_output": bottom,
            "embedding_vectors": np.stack(embedding_vectors, axis=1),
            "interaction_output": interaction,
            "logits": logits,
            "probabilities": probabilities,
        }

    def forward(self, dense_features, categorical_ids, return_intermediates=False):
        stages = self.forward_stages(dense_features, categorical_ids)
        return stages if return_intermediates else stages["logits"]

    def parameter_summary(self):
        total = sum(value.size for value in self.state.values())
        embedding = sum(
            self.state["embedding_{}".format(index)].size
            for index in range(self.config.num_tables)
        )
        return {
            "total_parameters": int(total),
            "embedding_parameters": int(embedding),
            "dense_parameters": int(total - embedding),
            "embedding_capacity_values": int(self.config.embedding_capacity),
            "embedding_capacity_bytes": int(embedding * self.dtype.itemsize),
        }

    def save(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = dict(self.state)
        payload["__config_json__"] = np.array(
            json.dumps(self.config.to_dict(), sort_keys=True)
        )
        np.savez_compressed(path, **payload)

    @classmethod
    def load(cls, path):
        with np.load(Path(path), allow_pickle=False) as payload:
            config = DLRMConfig.from_dict(json.loads(str(payload["__config_json__"])))
            state = {
                name: payload[name].copy()
                for name in payload.files if name != "__config_json__"
            }
        return cls(config, state=state)
