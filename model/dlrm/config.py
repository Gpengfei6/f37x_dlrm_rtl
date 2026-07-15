"""Configuration contract for the software DLRM reference."""

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Tuple


@dataclass(frozen=True)
class DLRMConfig:
    seed: int = 3701
    num_dense_features: int = 8
    table_sizes: Tuple[int, ...] = (64, 80, 96, 128)
    embedding_dim: int = 8
    bottom_mlp: Tuple[int, ...] = (16, 8)
    top_mlp: Tuple[int, ...] = (32, 16, 1)
    synthetic_samples: int = 256
    batch_size: int = 16
    dtype: str = "float32"

    def __post_init__(self):
        object.__setattr__(self, "table_sizes", tuple(self.table_sizes))
        object.__setattr__(self, "bottom_mlp", tuple(self.bottom_mlp))
        object.__setattr__(self, "top_mlp", tuple(self.top_mlp))
        self.validate()

    @property
    def num_tables(self):
        return len(self.table_sizes)

    @property
    def feature_vector_count(self):
        return self.num_tables + 1

    @property
    def interaction_pair_count(self):
        count = self.feature_vector_count
        return count * (count - 1) // 2

    @property
    def interaction_output_dim(self):
        return self.embedding_dim + self.interaction_pair_count

    @property
    def embedding_capacity(self):
        return sum(self.table_sizes) * self.embedding_dim

    def validate(self):
        if self.seed < 0:
            raise ValueError("seed must be non-negative")
        if self.num_dense_features <= 0:
            raise ValueError("num_dense_features must be positive")
        if not self.table_sizes or any(size <= 0 for size in self.table_sizes):
            raise ValueError("all embedding table sizes must be positive")
        if self.embedding_dim <= 0:
            raise ValueError("embedding_dim must be positive")
        if not self.bottom_mlp or self.bottom_mlp[-1] != self.embedding_dim:
            raise ValueError("bottom_mlp must end at embedding_dim")
        if not self.top_mlp or self.top_mlp[-1] != 1:
            raise ValueError("top_mlp must end at one output logit")
        if self.synthetic_samples <= 0 or self.batch_size <= 0:
            raise ValueError("synthetic_samples and batch_size must be positive")
        if self.dtype not in ("float32", "float64"):
            raise ValueError("dtype must be float32 or float64")

    def to_dict(self):
        result = asdict(self)
        result["table_sizes"] = list(self.table_sizes)
        result["bottom_mlp"] = list(self.bottom_mlp)
        result["top_mlp"] = list(self.top_mlp)
        return result

    def save(self, path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(self.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    @classmethod
    def from_dict(cls, raw):
        return cls(
            seed=int(raw.get("seed", 3701)),
            num_dense_features=int(raw["num_dense_features"]),
            table_sizes=tuple(int(value) for value in raw["table_sizes"]),
            embedding_dim=int(raw["embedding_dim"]),
            bottom_mlp=tuple(int(value) for value in raw["bottom_mlp"]),
            top_mlp=tuple(int(value) for value in raw["top_mlp"]),
            synthetic_samples=int(raw.get("synthetic_samples", 256)),
            batch_size=int(raw.get("batch_size", 16)),
            dtype=str(raw.get("dtype", "float32")),
        )

    @classmethod
    def load(cls, path):
        return cls.from_dict(json.loads(Path(path).read_text(encoding="utf-8")))
