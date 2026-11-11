# Upstream PR draft (PX4/PX4-Autopilot)

Status: draft, not opened. Opening it needs a GitHub fork of PX4 and the user's go-ahead (see "Steps" below).

## Scope

Send patches 0001–0003 and 0005 as one draft PR: "posix: add QNX 8.0 support". Leave 0004 (rate-control interval perf counter) out, or send it on its own. It is a measurement aid, not part of QNX support.

Also before opening: replace the `-Wshadow` pragma in `statfs.h` with a `px4_statfs()` / `struct px4_statfs` name to avoid review friction.

Before opening: rebase `qnx-port` on PX4 `main`, rebuild `qnx_sitl_default` and `px4_sitl_default`, rerun `tests/run-all.sh` and the Linux flight test, and run `make format` / `make check_format` (astyle) on the changed files.

## Title

posix: add QNX 8.0 support (qcc toolchain, qnx_sitl board, SIH)

## Body

### Solved Problem
PX4 does not build or run on QNX. QNX is a common RTOS for safety-related and automotive systems, and it is POSIX, so most of PX4's POSIX layer already fits.

### Solution
Extends `platforms/posix` with a `__PX4_QNX` path, the same way `__PX4_DARWIN` and `__PX4_CYGWIN` are handled. No new platform.

- `platforms/posix/cmake/Toolchain-qnx-x86_64.cmake`: `qcc`/`q++` from the QNX SDP environment. `px4_impl_os.cmake` defines `__PX4_QNX` when `CMAKE_SYSTEM_NAME` is `QNX`. On QNX, link `libsocket` instead of `rt`/`pthread`.
- `boards/qnx/sitl`: SIH-only board (multicopter set, no Gazebo / uXRCE-DDS).
- Portability fixes with no behaviour change on other platforms:
  - `px4_platform_common/statfs.h` (QNX has only `statvfs`)
  - `px4_platform_common/dirent.h` (`d_type` is not POSIX)
  - `B230400` / `CRTSCTS` fallbacks
  - `px4_os_name()` returns "QNX"
  - `load_mon` uses `times()` + `sysconf()`
- Scheduling:
  - QNX 8.0 reserves priorities 254/255, so `SCHED_PRIORITY_MAX` is capped at 253.
  - Threads inherit scheduling unless `PTHREAD_EXPLICIT_SCHED` is set (POSIX; glibc too), so the requested priorities were being ignored. It is set in WorkQueueManager, log_writer_file, mavlink_receiver and commander's worker_thread. Done QNX-only in this branch. For the PR, consider making it unconditional: it is a real bug on Linux when run with RT privileges, and it changes Linux behaviour only in that case.
- `px4-rc.mavlink`: optional `PX4_MAVLINK_PARTNER_IP` for the GCS/offboard links. Default unchanged.
- `qnx_state_resmgr`: optional module that serves vehicle state at `/dev/px4/state` through a QNX resource manager. Built only for the QNX board.
- `CONFIG_ARCH_BOARD_QNX_SITL` sits next to `..._PX4_SITL` in `PWMSim.hpp`, `Commander.cpp`, `px4_log.cpp`, `pwm_out_sim/CMakeLists.txt`.

### Test coverage
QNX SDP 8.0.5, QEMU x86_64 + KVM. Scripts and full results: https://github.com/Sarcastic-Soul/px4-qnx

- SIH quad: arm, takeoff 10 m, hold (±1 m), 4-waypoint mission, land (MAVSDK). Passes on QNX and on `px4_sitl_default` (Linux).
- All threads in 1..253 with the expected work-queue ordering. `hrt_absolute_time()` matches `CLOCK_MONOTONIC` within 0.1 ms over 12 s (consistency check). Params persist across restarts.
- `px4_sitl_default` still builds and flies with these changes.
- ULog from a QNX flight: <Flight Review link to add>

### Changelog Entry
```
Feature: QNX 8.0 support for the POSIX platform (board qnx_sitl_default, SIH)
Documentation: needs a "QNX" page under the POSIX/Linux section
```

### Alternatives
A separate `platforms/qnx` would duplicate most of the POSIX layer. QNX is POSIX enough that small `#if` blocks were the smaller change.

## Steps (user)

1. Fork PX4/PX4-Autopilot on GitHub (`gh repo fork PX4/PX4-Autopilot --clone=false`).
2. In `work/PX4-Autopilot`: `git fetch origin main && git rebase origin/main` (from the `qnx-port` branch). Fix conflicts, rebuild, rerun tests.
3. `git remote add fork git@github.com:Sarcastic-Soul/PX4-Autopilot.git && git push -u fork qnx-port`
4. `gh pr create --repo PX4/PX4-Autopilot --draft --title "posix: add QNX 8.0 support (qcc toolchain, qnx_sitl board, SIH)" --body-file <this file's Body section>`
5. Add the PR URL to `README.md`.
