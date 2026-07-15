"""Simple deterministic channel mappings; these are not physical address maps."""


def map_channel(table_id, embedding_id, channel_count, policy="modulo", table_map=None):
    if channel_count <= 0:
        raise ValueError("channel_count must be positive")
    table_id, embedding_id = int(table_id), int(embedding_id)
    if policy == "modulo":
        return ((table_id * 2654435761) ^ embedding_id) % channel_count
    if policy == "static_table":
        if table_map is not None and table_id in table_map:
            return int(table_map[table_id]) % channel_count
        return table_id % channel_count
    raise ValueError("mapping policy must be modulo or static_table")


def candidate_channels(table_id, embedding_id, channel_count):
    primary = map_channel(table_id, embedding_id, channel_count, "modulo")
    secondary = ((embedding_id * 17) ^ (table_id * 131) ^ 0x9E3779B9) % channel_count
    if channel_count > 1 and secondary == primary:
        secondary = (primary + 1) % channel_count
    return primary, secondary
