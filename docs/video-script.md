# Demo video script (under 3:00)

Target 2:45. Screen recording at 1080p, voice-over, no copyrighted music. Each shot lists what is on screen, what to say, and the command that produces it. Prepare beforehand: VM built, PX4 deployed, QGroundControl open, two terminals side by side.

| Time | On screen | Say |
|---|---|---|
| 0:00–0:15 | Title card: "PX4 Autopilot on QNX 8.0" + repo URL | "PX4 is the open-source autopilot behind many drones. It runs on NuttX and Linux. I ported it to QNX 8.0." |
| 0:15–0:30 | Terminal: `scripts/build.sh` tail showing `ELF ... ldqnx-64.so.2`, then `git -C ../work/PX4-Autopilot log --oneline v1.17.0..` | "Same PX4 v1.17.0 source plus six small patches. It builds with qcc and adds a QNX path to PX4's POSIX layer. No fork of the platform." |
| 0:30–0:45 | `scripts/run-vm.sh`, `scripts/vm-ssh.sh uname -a`, `scripts/px4-vm.sh start` and `log` showing "Ready for takeoff" | "A QNX 8.0 VM in QEMU. PX4 boots its normal startup script with the built-in SIH simulator." |
| 0:45–1:15 | QGroundControl: vehicle appears, take off, fly the mission (speed up 4x) | "QGroundControl on the host sees it right away. Arm, take off, fly a mission. The same flight runs as an automated test." |
| 1:15–1:35 | `scripts/vm-ssh.sh "pidin -p px4 -F '%h %p'"` | "Every PX4 thread gets a real QNX FIFO priority. Rate controller at 253, estimator 239, logging near the bottom. Getting this right needed one QNX-specific fix: threads inherit their creator's priority unless told otherwise." |
| 1:35–2:05 | `docs/img/timing.png` full screen, then `bench/run_timing_qnx.sh` output | "Then I loaded the CPU with twice as many busy threads as cores. Stock Linux SITL, running without real-time priorities, lost almost a quarter of its control updates, with a 28 millisecond gap. On QNX the rate controller didn't move. Even with the load at FIFO priority 200, the control loops kept running, and only the lower-priority tasks waited, exactly as configured." |
| 2:05–2:25 | Terminal: `tests/test_fault_isolation.sh` running next to QGC mid-mission: "Memory fault (core dumped)", then "PASS" | "Mid-mission, a separate process grabs CPU and memory and crashes. The vehicle keeps flying, and QNX saves a core file for debugging." |
| 2:25–2:40 | `scripts/vm-ssh.sh cat /dev/px4/state` during flight | "PX4 also shows up as a native QNX resource manager. Any QNX process can read live vehicle state with plain cat, and the server stays at a fixed low priority." |
| 2:40–2:50 | Repo README, codelab page, PR link | "Everything is reproducible from one script, with tests for every claim, a codelab, and an upstream pull request." |

Notes:
- Don't claim absolute microsecond numbers. Say "on the same host".
- If QGC isn't available, use `tests/test_flight.py` output in a terminal for 0:45–1:15.
