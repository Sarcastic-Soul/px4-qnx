#!/usr/bin/env python3
"""Plot rate-controller timing from bench/results/*.jsonl into docs/img/timing.png.

Two panels: rate-controller updates in 30 s (target 24000 at 800 Hz) and the
worst gap between updates, for every run in the results directory.
"""

import json
import pathlib
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

root = pathlib.Path(__file__).resolve().parent
results = root / "results"
out = root.parent / "docs" / "img" / "timing.png"
out.parent.mkdir(parents=True, exist_ok=True)

order = [
    "linux.jsonl",
    "qnx-hog-prio10.jsonl",
    "qnx-hog-prio200.jsonl",
    "qnx-hog-prio245.jsonl",
]
rows = []
for name in order:
    f = results / name
    if f.exists():
        rows += [
            json.loads(line) for line in f.read_text().splitlines() if line.strip()
        ]
if not rows:
    sys.exit("no results; run bench/run_timing_*.sh first")

labels = [
    r["label"].replace("qnx-hog-", "qnx ").replace(" hog ", "\nhog ") for r in rows
]
colors = [
    "#b0b0b0"
    if "idle" in r["label"]
    else ("#c0392b" if r["label"].startswith("linux") else "#2e86c1")
    for r in rows
]

fig, (a, b) = plt.subplots(2, 1, figsize=(11, 7), sharex=True)
a.bar(range(len(rows)), [r["events"] for r in rows], color=colors)
a.axhline(24000, color="k", lw=0.8, ls="--")
a.set_ylabel("updates in 30 s\n(target 24000)")
a.set_title(
    "PX4 mc_rate_control on the same host: Linux SITL vs QNX 8.0 VM, idle vs CPU hog"
)
b.bar(range(len(rows)), [r["max_us"] / 1000 for r in rows], color=colors)
b.set_ylabel("worst gap (ms)")
b.set_xticks(range(len(rows)), labels, fontsize=8)
for ax in (a, b):
    ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(out, dpi=110)
print(out)
