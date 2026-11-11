# Porting notes: PX4 v1.17.0 on QNX 8.0

Target: QNX SDP 8.0.5, `qcc` 12.2.0 (`gcc_ntox86_64`), QEMU x86_64 + KVM.
Approach: extend `platforms/posix` with a `__PX4_QNX` code path. No new PX4 platform.

Patches live in `patches/` (exported from branch `qnx-port` with `scripts/export-patches.sh`):

| Patch | Content |
|---|---|
| 0001 | toolchain, `__PX4_QNX` detection, link libs, `qnx_sitl` board |
| 0002 | build fixes: priorities cap, statfs, dirent type, termios, load_mon, version |
| 0003 | explicit thread scheduling, SITL defines for the QNX board, MAVLink partner IP |
| 0004 | `mc_rate_control` interval perf counter |
| 0005 | `qnx_state_resmgr` module (`/dev/px4/state`) |

## Build system

| Change | File | Why |
|---|---|---|
| Toolchain file | `platforms/posix/cmake/Toolchain-qnx-x86_64.cmake` | `qcc`/`q++` from `$QNX_HOST`, sysroot `$QNX_TARGET`. Host programs (Python codegen) found with `FIND_ROOT_PATH_MODE_PROGRAM NEVER`. `MODE_PACKAGE BOTH` so nested ExternalProjects find packages they install in the build dir. |
| `__PX4_QNX`, `_QNX_SOURCE` | `platforms/posix/cmake/px4_impl_os.cmake` | Chosen when `CMAKE_SYSTEM_NAME` is `QNX`. `__PX4_LINUX` is not defined. |
| Link `socket`, not `rt`/`pthread` | `platforms/posix/CMakeLists.txt` | On QNX librt and libpthread are in libc; BSD sockets are in libsocket. |
| Board `qnx_sitl_default` | `boards/qnx/sitl/` | Name contains `sitl`, so PX4 picks the `init.d-posix` ROMFS and `rootfs/` dir (both keyed on the board name). Copy of `boards/px4/sitl/src`. `CONFIG_BOARD_NOLOCKSTEP=y`: real-time SIH, not lockstep. |
| `CONFIG_ARCH_BOARD_QNX_SITL` next to `..._PX4_SITL` | `PWMSim.hpp`, `Commander.cpp`, `px4_log.cpp`, `pwm_out_sim/CMakeLists.txt` | SITL behaviour (PWM_MAIN params, "Ready for takeoff", log flush). First tried `-DCONFIG_ARCH_BOARD_PX4_SITL` globally: it also turns on a param type check in `param.h` that segfaults (`FlightTaskTransition` asks for VTOL params that this board does not build). |

Ruling: board placed at `boards/qnx/sitl/default.px4board`, not `boards/qnx/x86_64/sih.px4board` as first planned, because of the `sitl` name checks above.

## Source changes (grouped by cause)

Linux-only API / header:

- `sys/statfs.h` missing. New `px4_platform_common/statfs.h`: on QNX builds `statfs()` on POSIX `statvfs()` with the fields PX4 uses. Used by logger (free space), MAVLink `STORAGE_INFORMATION`, commander SD card check.
- `struct dirent::d_type` missing. New `px4_platform_common/dirent.h` with `px4_dirent_type()`: on QNX uses `fstatat(dirfd(dp), ...)`. Used by MAVLink FTP and log handler.
- `B230400` and `CRTSCTS` not defined. Numeric fallback for the baud rate (QNX baud constants are numeric); `CRTSCTS` = `IHFLOW | OHFLOW`. `SerialImpl.cpp`, `mavlink_main.cpp`.
- `px4_os_version()` / `px4_os_name()`: QNX uses `uname()` like Linux and reports `QNX`. `version.c`.

Compiler (`-Werror`, gcc 12 in qcc):

- `ModeManagement.cpp`: `-Wformat-truncation` on a 20-byte buffer. Raised to 32.
- `statfs.h`: function and struct both named `statfs` trips `-Wshadow`; local pragma.

Scheduling (runtime, found in Stage 4):

- QNX 8.0 reserves priority 255 (IPIs) and 254 (clock IST). `sched_get_priority_max(SCHED_FIFO)` returns 253 on our image, and PX4 priorities are offsets below it. `tasks.h` caps `SCHED_PRIORITY_MAX` at 253 for `__PX4_QNX` anyway. Verified: a thread at 254 fails `pthread_create` with `EINVAL`.
- Threads inherit the creator's scheduling by default (POSIX, glibc too), so `pthread_attr_setschedparam()` alone is ignored. Linux SITL hides this because it runs unprivileged. Before the fix every work queue ran at 253 (inherited from `wq:manager`), log writer at 228, etc. Added `PTHREAD_EXPLICIT_SCHED` + `SCHED_FIFO` on QNX in `WorkQueueManager.cpp`, `log_writer_file.cpp`, `mavlink_receiver.cpp`, `commander/worker_thread.cpp`. Result (`tests/test_priorities.sh`): rate_ctrl 253 > INS0 239 > hp_default 235 > lp_default 203, log_writer_file 87.

Networking:

- MAVLink defaults to sending to `127.0.0.1`. From a QEMU user-NAT guest the host is `10.0.2.2`. `px4-rc.mavlink` now passes `-t $PX4_MAVLINK_PARTNER_IP` to the GCS and offboard instances when that variable is set (`scripts/px4-vm.sh` sets `10.0.2.2`). Unset = upstream behaviour.

Timing:

- QNX normal timers (nanosleep, condvar/semaphore timeouts) round to the system tick, 1 ms by default. PX4's 800 Hz loop then runs as a mix of 1 ms and 2 ms waits (idle std dev 440 us). `procmgr_timer_tolerance()` and `TimerTimeout(TIMER_TOLERANCE)` did not change this in our tests. `scripts/make-vm.sh` boots `procnto -C 10000` (10 kHz tick) through a mkqnximage `options.*` snippet, which brings idle std dev to 73 us. No PX4 code change. Set `TICK_HZ=0` for the default.

QNX-specific additions:

- `src/modules/qnx_state_resmgr`: QNX resource manager at `/dev/px4/state` (patch 0005), started from `rcS` only on `QNX_SITL`.
- `mc_rate_control: interval` perf counter (patch 0004), used by `bench/`. Platform-neutral.

## Stubs and "not available" values

| Function | QNX behaviour | Honest? |
|---|---|---|
| `load_mon` CPU load | `times()` user+system of the PX4 process / wall time, same formula as Linux. On 4 cores this is summed over cores. | Real data. |
| `load_mon` RAM | `(_SC_PHYS_PAGES - _SC_AVPHYS_PAGES) / _SC_PHYS_PAGES`, whole system. `-1` if sysconf fails. | Real data (system-wide, not per process). |
| `top` (`print_load`) | Prints "TOP NOT IMPLEMENTED ... QNX", same as Linux. Use `pidin`/`hogs`. | Says it's missing. |
| uXRCE-DDS client | Not built: Micro-XRCE-DDS `ip_posix.c` misses `AF_INET` on QNX (needs `<sys/socket.h>`). Not needed for SIH flight. Startup prints "uxrce_dds_client: cannot execute" and continues. | Absent, not faked. |

## Modules left out of `qnx_sitl_default`

Not needed for SIH quad flight (see `docs/module-baseline.md`): Gazebo bridge, uXRCE-DDS, Zenoh, GPS/serial drivers, fixed-wing/VTOL/rover/UUV controllers, examples. Startup prints harmless `Parameter ... not found` lines for some of them (`UXRCE_DDS_*`).

## Runtime notes

- VM root `/` is a read-only IFS. PX4 runs from `/data/px4` (`bin/`, `etc/`, `rootfs/`). Start: `px4 -d /data/px4/etc` from `rootfs/` (PX4 symlinks `rootfs/etc`).
- Binary is 31 MB with debug info; `deploy.sh` ships a stripped 2.3 MB copy and keeps the debug one on the host for `ntox86_64-gdb` on core files from `/data/var/dumper`.
- QNX `sshd` can keep a session open while a backgrounded PX4 runs; `px4-vm.sh start` fires the launch with a short timeout and then polls.
- Params are auto-saved with a delay. `tests/test_params_persist.sh` runs `param save` before stopping PX4.
- Real-time SIH runs the rate loop at 800 Hz on QNX (IMU_GYRO_RATEMAX default, non-lockstep). Linux SITL uses lockstep at 250 Hz. Timing comparisons in `bench/` must use the same mode on both sides.

## Decision gates

Gate A (compile): passed, no blocker. Gate B (stable boot): passed. SOEM fallback not needed.
