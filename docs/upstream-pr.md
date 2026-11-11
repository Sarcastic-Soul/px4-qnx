# Upstream PR (PX4/PX4-Autopilot)

Opened as a draft: https://github.com/PX4/PX4-Autopilot/pull/29765

- Title: `feat(platforms/posix): add QNX 8.0 support with qnx_sitl board`
- Head: `Sarcastic-Soul/PX4-Autopilot` branch `sarcastic-soul/qnx-support`, base `main` (rebased onto `main` at `3695a9e9`, 2026-11-11).
- 8 conventional commits (7 for QNX support, 1 to keep QNX out of the default CI, which has no QNX SDP), each with the `Assisted-by:` trailer PX4's [AI policy](https://github.com/PX4/PX4-Autopilot/blob/main/CONTRIBUTING.md#ai-assisted-contributions) asks for.

## How the PR differs from `patches/` (v1.17.0)

`patches/` stays on the v1.17.0 tag, which is what the hackathon build and results use. The PR is the same work moved to PX4 `main` (about 3,900 commits newer), with these changes:

- `statfs()` on QNX is now `px4_statfs()` / `px4_statfs_t` on every platform (no `-Wshadow` pragma), and the per-file Darwin `#ifdef`s in logger, MAVLink and commander are gone.
- `main` reworked `mavlink_log_handler.cpp` and `ModeManagement.cpp`; the `d_type` uses in the new code go through `px4_dirent_type()`, and the `ModeManagement` buffer fix is no longer needed.
- `qnx_state_resmgr` uses the new non-template `ModuleBase` with a `Descriptor`.
- The board follows `main`'s SITL layout (`CONFIG_BOARD_ROOT_PATH="./fs"`) and enables `failure_injection_manager`, which `main`'s rcS starts by default.
- Logger old-log cleanup checks that the joined path fits (newer GCC `-Wformat-truncation`).
- Patch 0004 (rate-controller interval perf counter) is left out: it is a benchmark aid, not QNX support.
- PX4 CI has no QNX SDP: `qnx_sitl` is excluded from the build-all matrix (as PX4 already does for `aifoundry_erbium`) and `qnx_state_resmgr` from `px4_sitl_allyes`. The first CI run failed on both.

## What was run on the PR branch

QNX SDP 8.0.5, QEMU x86_64 + KVM, `qnx_sitl_default` built at every commit from the board commit on. On the final commit: `tests/run-all.sh` passes all 7 checks (boot, priorities, hrt, params, resmgr, fault isolation, MAVSDK flight), and QGroundControl connects. `px4_sitl_default` (Linux) builds and passes `tests/test_flight.py`. `make check_format` (astyle 3.1) is clean on every changed file.

The fault-isolation test reads the 0004 perf counter, so it was run with 0004 applied on top of the PR branch.

## Possible review points

- `PTHREAD_EXPLICIT_SCHED` is set only on QNX. It is also correct on Linux and changes behaviour there only when SITL runs with real-time privileges; offered to make it unconditional.
- No `docs/en` page yet; can add one under the POSIX/Linux section if the approach is accepted.
- No ULog on logs.px4.io linked yet (the board-addition guideline asks for one for hardware boards).
