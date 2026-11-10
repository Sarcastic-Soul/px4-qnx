#!/usr/bin/env python3
"""Ready-to-running latency of one thread from a traceprinter text dump.

For the given pid/tid, every THREADY event is paired with the next
THRUNNING event of the same thread; the difference (in CPU cycles, converted
with TRACE_CYCLES_PER_SEC from the header) is how long the thread waited for
a CPU after it became runnable. Also counts how many times it ran.

Usage: trace_latency.py <trace.txt> <pid> <tid> [--label X]
"""

import argparse
import json
import re

import numpy as np

EV = re.compile(r"^t:0x([0-9a-f]+) CPU:(\d+) THREAD\s+:(TH\w+)\s+pid:(\d+) tid:(\d+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trace")
    ap.add_argument("pid", type=int)
    ap.add_argument("tid", type=int)
    ap.add_argument("--label", default="")
    a = ap.parse_args()

    cps = None
    ready_at = None
    lat = []
    runs = 0
    first = last = None
    with open(a.trace, errors="replace") as f:
        for line in f:
            if cps is None and "TRACE_CYCLES_PER_SEC::" in line:
                cps = int(line.split("::")[1])
                continue
            m = EV.match(line)
            if not m:
                continue
            t = int(m.group(1), 16)
            first = t if first is None else first
            last = t
            if int(m.group(4)) != a.pid or int(m.group(5)) != a.tid:
                continue
            state = m.group(3)
            if state == "THREADY":
                ready_at = t
            elif state == "THRUNNING":
                runs += 1
                if ready_at is not None:
                    lat.append(t - ready_at)
                    ready_at = None

    if not cps or not lat:
        raise SystemExit(f"no data (cycles/s={cps}, ready->running pairs={len(lat)})")
    us = np.array(lat) * 1e6 / cps
    out = {
        "label": a.label,
        "trace_s": round((last - first) / cps, 2),
        "runs": runs,
        "runs_per_s": round(runs / ((last - first) / cps), 1),
        "ready_to_running_pairs": int(len(us)),
        "median_us": round(float(np.median(us)), 2),
        "p99_us": round(float(np.percentile(us, 99)), 2),
        "max_us": round(float(us.max()), 2),
    }
    print(json.dumps(out))


if __name__ == "__main__":
    main()
