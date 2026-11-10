# Results

All numbers come from scripts in `bench/` and `tests/`, run on one host (12 CPUs, Linux, KVM). The QNX VM has 4 vCPUs and 2 GB. VM timing includes host jitter, so only compare runs side by side. Do not read them as absolute guarantees.

## Control loop under CPU load

What is measured: time between `mc_rate_control` updates, from the PC_INTERVAL perf counter `mc_rate_control: interval` (patch 0004). Each phase lasts 30 s. Both sides run real-time (non-lockstep) SIH with the same PX4 v1.17.0 source. Target rate is 800 Hz (1250 us).

Scripts: `bench/run_timing_qnx.sh`, `bench/run_timing_linux.sh`. Raw output: `bench/results/*.jsonl`.

| Run | Updates in 30 s | Mean interval | Max interval | Std dev |
|---|---|---|---|---|
| Linux SITL, idle | 23999 | 1250 us | 4138 us | 76 us |
| Linux SITL, 24 busy threads (2x host CPUs) | 15330 | 1958 us | 22376 us | 2080 us |
| QNX, idle | 24022 | 1255 us | 5532 us | 467 us |
| QNX, 8 busy threads at prio 10 (2x vCPUs) | 23995 | 1251 us | 7239 us | 451 us |
| QNX, 8 busy threads at prio 200 FIFO | 24006 | 1250 us | 2173 us | 433 us |

What this shows:

- Under load, Linux SITL dropped 36% of rate-controller updates (24k to 15k) and had a 22 ms gap. Stock Linux SITL runs as a normal user, so PX4's `SCHED_FIFO` requests fail and its threads compete with the hog as equals.
- On QNX the update count did not change under load, even with 8 hog threads at FIFO priority 200. PX4's control threads run at 239 to 253 (see `tests/test_priorities.sh`), so strict priority scheduling keeps them ahead.
- QNX idle jitter (std dev about 440 us) is higher than Linux idle (76 us). QNX timers fire on the 1 ms system tick: a 1250 us period is served as a mix of 1 ms and 2 ms waits that average to 1250 us. Tested and not fixed yet: `procmgr_timer_tolerance()` and `TimerTimeout(TIMER_TOLERANCE)` did not change `usleep()` or `pthread_cond_timedwait()` granularity in this image (still 1 ms). Next things to try: a `timer_create()` high-resolution timer for the PX4 HRT thread, or booting `procnto` with `-C` for a faster tick.

Not measured: Linux SITL with real-time priorities (needs root). That would be a fairer "RT Linux vs QNX" comparison, and this table does not claim it.
