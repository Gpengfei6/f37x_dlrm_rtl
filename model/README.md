# Configurable software DLRM

This tree is a software-first feasibility reference. `model.dlrm.model.DLRM`
implements the standard PyTorch flow (bottom MLP, per-field embeddings,
pairwise dot interaction, top MLP) when PyTorch is available. The deterministic
`NumpyDLRM` is an independent local oracle used to validate structure in the
current runtime; it is not a substitute for the required PyTorch CPU result.

No command downloads Criteo. Pass a user-supplied classic TSV file or directory
with `--dataset criteo --criteo-path <local-path>`. Synthetic datasets are
explicitly tagged as tooling-only evidence.

The Criteo adapter expects the classic tab-separated row layout: one binary
label, 13 continuous columns, then 26 hexadecimal categorical columns. The
configured model consumes prefixes of those feature groups and maps categorical
IDs into the configured table capacities. A directory may contain `.txt`,
`.tsv`, `.csv`, or extensionless `day_*` files; they are read in sorted name
order. URLs are rejected.

Inference/training maps parsed IDs modulo the configured table capacities so a
small local model can execute. Trace feasibility deliberately disables that
mapping and preserves raw parsed hexadecimal IDs; otherwise small test tables
would create artificial duplicates. A formal trained-model evaluation still
requires the user's reviewed vocabulary/hash mapping and matching checkpoint.

Example commands:

```powershell
python -m model.inference.run_inference --backend torch --device cpu
python -m model.inference.run_inference --backend torch --device cuda
python -m model.inference.run_inference --backend numpy-oracle
python -m model.training.train_dlrm --dataset criteo --criteo-path D:\data\criteo
```
