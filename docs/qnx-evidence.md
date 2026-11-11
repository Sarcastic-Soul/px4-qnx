# QNX technology used

For the "main technology" field of the submission. Every item links to the file that uses it and the test or script that shows it working.

## Toolchain and platform

| What | Where | Proof |
|---|---|---|
| QNX SDP 8.0.5, `qcc`/`q++` 12.2.0 (`gcc_ntox86_64`) | `platforms/posix/cmake/Toolchain-qnx-x86_64.cmake` (patch 0001) | `scripts/build.sh` prints `ELF 64-bit ... interpreter /usr/lib/ldqnx-64.so.2` |
| `mkqnximage` QEMU x86_64 image, custom `procnto -C` options snippet | `scripts/make-vm.sh` | `scripts/run-vm.sh`, `uname` = `QNX px4-qnx 8.0.0` |
| QNX `libsocket`, `io-sock` networking | `platforms/posix/CMakeLists.txt` | `tests/test_flight.py` over MAVLink to `10.0.2.2` |
| `procnto` kernel tick (`-C 10000`) | `scripts/make-vm.sh` | `docs/results.md` §1: idle std dev 440 → 73 us |

## Real-time scheduling

| What | Where | Proof |
|---|---|---|
| `SCHED_FIFO` priorities 1..253 (254/255 reserved in 8.0) | `platforms/common/include/px4_platform_common/tasks.h` (patch 0002) | `tests/test_priorities.sh` |
| `PTHREAD_EXPLICIT_SCHED` (QNX inherits scheduling by default) | `WorkQueueManager.cpp`, `log_writer_file.cpp`, `mavlink_receiver.cpp`, `worker_thread.cpp` (patch 0003) | `tests/test_priorities.sh`: rate_ctrl 253 > INS0 239 > hp 235 > lp 203 |
| `on -p` to run load at chosen priorities | `bench/run_timing_qnx.sh` | `docs/results.md` §1 |
| `pidin` for thread priorities/states | `tests/test_priorities.sh`, `bench/trace_ratectrl.sh` | test output |

## QNX-native APIs in PX4

| What | Where | Proof |
|---|---|---|
| Resource manager: `dispatch_create_channel`, `resmgr_attach`, `iofunc_*`, `dispatch_block/handler` | `src/modules/qnx_state_resmgr/qnx_state_resmgr.cpp` (patch 0005) | `cat /dev/px4/state`, `tests/test_resmgr.sh` |
| Fixed-priority channel (`ChannelCreate(_NTO_CHF_FIXED_PRIORITY)`) to opt out of message-passing priority inheritance | same | `tests/test_resmgr.sh`: server stays at 97 after a FIFO-200 reader |
| POSIX `statvfs`, `fstatat` in place of Linux-only `statfs`, `d_type` | `px4_platform_common/statfs.h`, `dirent.h` (patch 0002) | logger free-space check, MAVLink FTP |
| `times()`, `sysconf(_SC_PHYS_PAGES/_SC_AVPHYS_PAGES)` for CPU/RAM load | `src/modules/load_mon/LoadMon.cpp` (patch 0002) | `listener cpuload` |

## System analysis and robustness

| What | Where | Proof |
|---|---|---|
| `tracelogger` kernel trace, `traceprinter` decode | `bench/trace_ratectrl.sh`, `bench/trace_latency.py` | `docs/results.md` §2: ready-to-running median 2.6 us |
| Process isolation + `dumper` core files | `tests/test_fault_isolation.sh`, `bench/badapp.c` | mission completes while another process hogs CPU/RAM and segfaults; core in `/data/var/dumper` |
| `slog2info`, `ntox86_64-gdb` on core files | `docs/porting-notes.md` (runtime notes) | used to debug the `param_get` crash during the port |

## Demo moments (for the video)

1. `scripts/run-vm.sh` → `uname -a` shows QNX 8.0.
2. `scripts/px4-vm.sh start` → PX4 boot log, `pidin -p px4` with priorities.
3. QGroundControl shows the vehicle; `tests/test_flight.py` flies the mission.
4. `cat /dev/px4/state` in a QNX shell during flight.
5. `docs/img/timing.png`: Linux SITL loses updates under load, QNX does not.
6. `tests/test_fault_isolation.sh`: bad app segfaults mid-mission, vehicle keeps flying.
