# Trace-first innovation feasibility tools

`run_trace_feasibility.py` exports canonical lookup traces, measures duplicate
and locality statistics over 1/2/4/8/16/32/64-request windows, simulates five
bounded coalescing policies, and compares five lightweight abstract channel
policies for 4/8/16/32 channels.

The default run uses deterministic synthetic scenarios. That run can be PASS as
a software test while every thesis trace gate remains INCONCLUSIVE. A local
Criteo file or directory must be supplied explicitly:

```powershell
python -m analysis.run_trace_feasibility --criteo-path D:\data\criteo
```

No downloader is included. Queue-aware channel results assume two candidate
placements and are not a physical F37X HBM mapping or an RTL performance claim.
