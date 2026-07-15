"""DLRM pairwise dot-product feature interaction."""

import numpy as np

try:
    import torch
except ImportError:  # The local bundled runtime intentionally has no PyTorch.
    torch = None


def numpy_dot_interaction(bottom_output, embedding_vectors):
    bottom_output = np.asarray(bottom_output)
    vectors = [bottom_output] + [np.asarray(value) for value in embedding_vectors]
    if not vectors:
        raise ValueError("at least the bottom-MLP vector is required")
    batch_size, embedding_dim = vectors[0].shape
    if any(value.shape != (batch_size, embedding_dim) for value in vectors):
        raise ValueError("all feature vectors must share [batch, embedding_dim]")
    stacked = np.stack(vectors, axis=1)
    gram = np.matmul(stacked, np.swapaxes(stacked, 1, 2))
    rows, columns = np.tril_indices(len(vectors), k=-1)
    interactions = gram[:, rows, columns]
    return np.concatenate((bottom_output, interactions), axis=1)


def torch_dot_interaction(bottom_output, embedding_vectors):
    if torch is None:
        raise RuntimeError("PyTorch is not installed; torch interaction is SKIPPED")
    vectors = [bottom_output] + list(embedding_vectors)
    stacked = torch.stack(vectors, dim=1)
    gram = torch.bmm(stacked, stacked.transpose(1, 2))
    indices = torch.tril_indices(
        len(vectors), len(vectors), offset=-1, device=bottom_output.device
    )
    interactions = gram[:, indices[0], indices[1]]
    return torch.cat((bottom_output, interactions), dim=1)
