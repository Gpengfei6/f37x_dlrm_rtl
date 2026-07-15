"""Read user-supplied local Criteo-style TSV files without downloading data."""

from pathlib import Path

import numpy as np

from model.dlrm.config import DLRMConfig


def resolve_criteo_input(path):
    raw = str(path)
    if "://" in raw:
        raise ValueError("Criteo input must be a local file or directory; URLs are forbidden")
    resolved = Path(path).expanduser().resolve()
    if not resolved.exists():
        raise FileNotFoundError(
            "Criteo data was not found at {}. Supply a local TSV file or directory.".format(resolved)
        )
    if resolved.is_file():
        return [resolved]
    candidates = sorted({
        value for pattern in ("*.txt", "*.tsv", "*.csv")
        for value in resolved.glob(pattern) if value.is_file()
    } | {value for value in resolved.glob("day_*") if value.is_file()})
    if not candidates:
        raise FileNotFoundError(
            "no .txt/.tsv/.csv or day_* Criteo files found in {}".format(resolved)
        )
    return candidates


def _parse_dense(value):
    if value == "":
        return 0.0
    return float(value)


def _parse_category(value, table_size, map_to_table_size):
    if value == "":
        return 0
    try:
        parsed = int(value, 16)
    except ValueError:
        parsed = int(value)
    return parsed % table_size if map_to_table_size else parsed


def load_criteo_tsv(
        path, config, max_samples=None, delimiter=None, map_to_table_sizes=True):
    """Load classic Criteo rows: label, 13 dense columns, then 26 categorical columns.

    A configurable model may consume a prefix of the dense and categorical
    columns. The function never downloads or discovers files outside ``path``.
    """
    if not isinstance(config, DLRMConfig):
        config = DLRMConfig.from_dict(config)
    if config.num_dense_features > 13 or config.num_tables > 26:
        raise ValueError("classic Criteo TSV exposes at most 13 dense and 26 categorical features")
    max_samples = None if max_samples is None else int(max_samples)
    dense_rows, categorical_rows, labels = [], [], []
    sources = resolve_criteo_input(path)
    required_columns = 1 + 13 + config.num_tables
    for source in sources:
        source_delimiter = delimiter if delimiter is not None else (
            "," if source.suffix.lower() == ".csv" else "\t"
        )
        with source.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                if max_samples is not None and len(labels) >= max_samples:
                    break
                columns = line.rstrip("\r\n").split(source_delimiter)
                if len(columns) < required_columns:
                    raise ValueError(
                        "{}:{} has {} columns; at least {} required".format(
                            source, line_number, len(columns), required_columns
                        )
                    )
                labels.append(float(columns[0]))
                dense_rows.append([_parse_dense(value) for value in columns[1:1 + config.num_dense_features]])
                categorical_source = columns[14:14 + config.num_tables]
                categorical_rows.append([
                    _parse_category(value, config.table_sizes[index], map_to_table_sizes)
                    for index, value in enumerate(categorical_source)
                ])
        if max_samples is not None and len(labels) >= max_samples:
            break
    if not labels:
        raise ValueError("Criteo input contained no rows")
    return {
        "dense_features": np.asarray(dense_rows, dtype=config.dtype),
        "categorical_ids": np.asarray(categorical_rows, dtype=np.int64),
        "labels": np.asarray(labels, dtype=np.float32),
        "metadata": {
            "source": "criteo_local",
            "files": [str(value) for value in sources],
            "sample_count": len(labels),
            "categorical_id_mapping": (
                "modulo_configured_table_size" if map_to_table_sizes else "raw_parsed_hex"
            ),
        },
    }
