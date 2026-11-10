# px4-qnx

PX4 Autopilot ported to QNX 8.0. PX4 builds with `qcc`, runs in a QNX 8.0 QEMU x86_64 VM, flies a simulated quadcopter with PX4's built-in SIH simulator, and talks MAVLink to QGroundControl / MAVSDK on the host.

- Upstream: https://github.com/PX4/PX4-Autopilot, tag `v1.17.0` (BSD-3-Clause)
- Target: QNX SDP 8.0.5 (`QNX 8.0.0`), QEMU x86_64 with KVM, 4 vCPU, 2 GB
- Toolchain: `qcc` / `q++` 12.2.0 (`gcc_ntox86_64`), CMake + Ninja
- This repo holds only our work: `patches/` on top of `v1.17.0`, scripts, tests, benchmarks, docs.

## Requirements

- Linux host with KVM and `qemu-system-x86_64`
- QNX SDP 8.0.5 at `~/qnx800` (override with `QNX_SDP`)
- An ssh key for the VM root login: `~/.ssh/id_ed25519_qnx` (+ `.pub`)
- CMake, Ninja, git, gcc (for the Linux baseline), [uv](https://docs.astral.sh/uv/)
- Optional: QGroundControl

## Build and run

```sh
scripts/fetch-upstream.sh      # PX4 v1.17.0 + submodules into ../work/PX4-Autopilot
scripts/apply-patches.sh       # git am patches/*.patch (branch qnx-port)
scripts/setup-venv.sh          # ../work/venv: PX4 codegen deps + mavsdk-grpc
scripts/build.sh               # qnx_sitl_default -> build/qnx_sitl_default/bin/px4 (QNX ELF)
scripts/make-vm.sh             # mkqnximage -> ~/qnx-vm-px4
scripts/run-vm.sh              # boot headless, ssh on localhost:2222
scripts/deploy.sh              # stripped px4 + ROMFS into /data/px4 in the VM
scripts/px4-vm.sh start        # PX4 SIH quad, MAVLink to the host at 10.0.2.2
```

QGroundControl on the host picks up the vehicle on UDP 14550. MAVSDK uses UDP 14540.

## Tests

```sh
tests/run-all.sh
```

| Test | Checks |
|---|---|
| `tests/test_boot.sh` | 20 SIH-flight modules running, rate/attitude/EKF loops > 100 Hz, `ver` reports QNX |
| `tests/test_priorities.sh` | every PX4 thread at priority 1..253, `wq:rate_ctrl` highest, work queues `SCHED_FIFO` and ordered |
| `tests/test_hrt.sh` | `hrt_absolute_time()` vs `CLOCK_MONOTONIC` over 11 s: no backward steps, drift < 1 ms |
| `tests/test_params_persist.sh` | a parameter survives a PX4 restart |
| `tests/test_flight.py` | MAVSDK: arm, takeoff 10 m, 10 s hold within ±1 m, 4-waypoint mission, land, disarm. Also passes on Linux SITL. |

## Results

See [docs/results.md](docs/results.md). Short version: with 2x-oversubscribed CPU load, stock Linux SITL lost 36% of rate-controller updates; on QNX the update count stayed the same, even with the load at FIFO priority 200, because PX4's control threads hold priorities 239 to 253.

## Docs

- [docs/porting-notes.md](docs/porting-notes.md): every change, why, and every stub
- [docs/module-baseline.md](docs/module-baseline.md): what SIH flight needs, from Linux SITL

## Known limits

- QNX timers use the 1 ms system tick, so loop jitter on QNX idle is higher than on Linux idle (see results).
- uXRCE-DDS (ROS 2 bridge) is not built on QNX.
- Only SIH simulation. No hardware drivers, no Gazebo.

## License

BSD-3-Clause, same as PX4. See [LICENSE](LICENSE).
