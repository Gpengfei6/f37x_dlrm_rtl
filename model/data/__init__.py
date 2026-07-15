"""Dataset adapters for the software DLRM reference."""

from .criteo_dataset import load_criteo_tsv, resolve_criteo_input
from .synthetic_dataset import generate_synthetic_dataset

__all__ = ["generate_synthetic_dataset", "load_criteo_tsv", "resolve_criteo_input"]
