# Stage 2N-A10 Final Evidence Collector v3

The v2 final-evidence collector failed before copying evidence because it
looked for the XO packaging Tcl file under:

```text
scripts/package_stage2n_a10_xo_v2.tcl
```

The committed canonical file is:

```text
tcl/package_stage2n_a10_xo_v2.tcl
```

Collector v3 corrects only this path and writes into a new evidence directory:

```text
docs/evidence/stage2n_a10_final_v3
```

It does not overwrite or delete the historical v2 failure status. It performs
no FPGA access, programming, or reset. After validation it collects the XSim,
XO packaging, F37X link, timing, link-acceptance, and board-smoke evidence and
generates a SHA256 manifest.
