"""Configurable DLRM reference implementations."""

from .config import DLRMConfig
from .model import DLRM, TORCH_AVAILABLE
from .numpy_model import NumpyDLRM

__all__ = ["DLRMConfig", "DLRM", "NumpyDLRM", "TORCH_AVAILABLE"]
