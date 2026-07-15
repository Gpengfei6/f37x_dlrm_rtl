"""Dependency-free binary accuracy and latency metrics."""

import numpy as np


def binary_log_loss(labels, probabilities, epsilon=1e-7):
    labels = np.asarray(labels, dtype=np.float64)
    probabilities = np.clip(np.asarray(probabilities, dtype=np.float64), epsilon, 1.0 - epsilon)
    if labels.shape != probabilities.shape or labels.size == 0:
        raise ValueError("labels and probabilities must be non-empty with matching shape")
    return float(-np.mean(labels * np.log(probabilities) + (1.0 - labels) * np.log(1.0 - probabilities)))


def binary_auc(labels, probabilities):
    """Compute ROC AUC with average ranks for tied scores."""
    labels = np.asarray(labels, dtype=np.int64).reshape(-1)
    scores = np.asarray(probabilities, dtype=np.float64).reshape(-1)
    if labels.shape != scores.shape or labels.size == 0:
        raise ValueError("labels and probabilities must be non-empty with matching shape")
    positives = int(np.sum(labels == 1))
    negatives = int(np.sum(labels == 0))
    if positives == 0 or negatives == 0:
        return None
    order = np.argsort(scores, kind="mergesort")
    sorted_scores = scores[order]
    ranks = np.empty(scores.size, dtype=np.float64)
    start = 0
    while start < scores.size:
        stop = start + 1
        while stop < scores.size and sorted_scores[stop] == sorted_scores[start]:
            stop += 1
        ranks[order[start:stop]] = (start + 1 + stop) / 2.0
        start = stop
    positive_rank_sum = float(np.sum(ranks[labels == 1]))
    return (positive_rank_sum - positives * (positives + 1) / 2.0) / (positives * negatives)


def latency_summary(latencies_seconds):
    values = np.asarray(latencies_seconds, dtype=np.float64)
    if values.size == 0:
        raise ValueError("at least one latency sample is required")
    return {
        "average_ms": float(np.mean(values) * 1000.0),
        "p50_ms": float(np.percentile(values, 50) * 1000.0),
        "p95_ms": float(np.percentile(values, 95) * 1000.0),
        "p99_ms": float(np.percentile(values, 99) * 1000.0),
    }


def classification_metrics(labels, probabilities):
    return {
        "auc": binary_auc(labels, probabilities),
        "log_loss": binary_log_loss(labels, probabilities),
    }
