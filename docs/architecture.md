# Architecture: PX4 on QNX 8.0

PX4 has three platform layers: NuttX (flight controllers), POSIX (Linux, macOS, SITL), and QuRT. This port does not add a fourth. It adds a QNX path to the POSIX layer, the same way PX4 already handles macOS (`__PX4_DARWIN`) and Cygwin. Everything above the platform layer (uORB, work queues, modules, MAVLink) is unchanged upstream code.

```
 Linux host                                   QNX 8.0 VM (QEMU x86_64, KVM, 4 vCPU)
 ─────────────────────────────                ──────────────────────────────────────────────
                                              procnto-smp-instr -C 10000 (10 kHz tick)
 QGroundControl  ◄── UDP 14550 ─┐             │
 MAVSDK tests    ◄── UDP 14540 ─┤             ├─ io-sock (network)        ┌──────────────────────┐
                                │  QEMU NAT   ├─ devb-eide → /data (QNX6) │ px4 (one process)    │
 tests/*.sh  ── ssh :2222 ──────┼─────────────┤   /data/px4/{bin,etc,     │  uORB (shared mem)   │
                                │  10.0.2.2   │    rootfs}                │  work queue threads: │
                                └─────────────┤                           │   wq:rate_ctrl  253f │
                                              ├─ dumper → /data/var/dumper│   wq:INS0       239f │
                                              │                           │   nav_and_ctrl  240f │
                                              ├─ /dev/px4/state  ◄────────┤   hp_default    235f │
                                              │   (resmgr in px4)         │   lp_default    203f │
                                              │                           │  tasks: commander,   │
                                              └─ other processes          │   navigator, mavlink,│
                                                 (cat, badapp, hog, ...)  │   logger, sih, ...   │
                                                                          └──────────────────────┘
```

## Build

- Code generation (uORB message headers, parameters, MAVLink, ROMFS) runs on the Linux host with a Python venv.
- Only C/C++ is cross-compiled with `qcc`/`q++` (`gcc_ntox86_64`) through `platforms/posix/cmake/Toolchain-qnx-x86_64.cmake`.
- The board `boards/qnx/sitl` reuses SITL's startup scripts (`ROMFS/px4fmu_common/init.d-posix`) and SIH, so the vehicle model and startup sequence are exactly upstream's.
- Output: one dynamically linked QNX ELF (`interpreter /usr/lib/ldqnx-64.so.2`), needing `libc`, `libm`, `libsocket`, `libc++`.

## Threads and priorities

PX4 runs everything as threads in one process. Work queues (`wq:*`) run many small modules each. The rate controller, mixer and actuator output share `wq:rate_ctrl`.

PX4 sets priorities as offsets below `sched_get_priority_max(SCHED_FIFO)`. On QNX 8.0 that is 253, because 254 is the clock interrupt thread and 255 is for IPIs. On QNX the port caps both `SCHED_PRIORITY_MAX` (tasks) and the work-queue base at 253, so this holds even if `sched_get_priority_max()` returned more.

Threads inherit their creator's scheduling unless `PTHREAD_EXPLICIT_SCHED` is set. That is POSIX, and glibc does the same. Upstream PX4 never noticed because Linux SITL usually runs unprivileged, where the requested priorities fail anyway. On QNX (running as root) the effect was visible: every work queue ran at 253. The fix sets `PTHREAD_EXPLICIT_SCHED` in the four places PX4 creates threads with explicit priorities (QNX-only in this port; worth making unconditional upstream).

`tests/test_priorities.sh` checks the result: every thread in 1..253, work queues `SCHED_FIFO` and ordered rate_ctrl > INS0 > hp_default > lp_default.

## Time

`hrt_absolute_time()` = `clock_gettime(CLOCK_MONOTONIC)` in microseconds, as on Linux (no lockstep on this board). Periodic work is driven by PX4's HRT thread and condvar timeouts. On QNX those round to the kernel tick, so the VM boots with a 10 kHz tick. `tests/test_hrt.sh` checks PX4 time against `CLOCK_MONOTONIC` from a separate process.

## Storage

The VM root is a read-only boot image. PX4 runs from `/data/px4` on the QNX6 data partition: parameters (`parameters.bson`), mission storage (`dataman`), ULogs (`log/`). The QNX `dumper` writes core files of crashed processes to `/data/var/dumper`.

## Networking

QEMU user-mode NAT: the guest sees the host at `10.0.2.2`, and the host reaches the guest's sshd through a forward on `localhost:2222`. PX4 MAVLink sends to the partner IP set by `PX4_MAVLINK_PARTNER_IP` (patch 0003), so QGroundControl and MAVSDK on the host need no port forwards.

## QNX-native interface

`qnx_state_resmgr` registers `/dev/px4/state` with `resmgr_attach()`. Each `open()` gets its own OCB holding a fresh snapshot of `vehicle_status`, `vehicle_local_position` and `battery_status`. `read()` returns it as one text line. The channel uses `_NTO_CHF_FIXED_PRIORITY`, so the handler thread stays at its own low priority whatever the reader's priority is.
