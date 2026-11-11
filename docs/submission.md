# Submission

Devpost form answers and the checklist of what is left. Copy the text under each label. Fields marked **(you)** need your input or a link that does not exist yet.

## Left to do

- [x] Public GitHub repo: https://github.com/Sarcastic-Soul/px4-qnx (BSD-3-Clause shows in About)
- [x] GitHub Pages from `main` `/docs`. Site: https://sarcastic-soul.github.io/px4-qnx/ (landing page links both codelabs)
- [x] QGroundControl check: QGC v5.1.5 on the host connected to PX4 on QNX over UDP 14550 with no setup (Ready, 10 sats, battery) and showed the full `tests/test_flight.py` mission. Recorded for the demo video.
- [ ] **(you)** Upload a QNX ULog to https://logs.px4.io (`scripts/fetch-ulog.sh` prints the file path) and paste the link into `docs/upstream-pr.md`.
- [x] Upstream draft PR opened: https://github.com/PX4/PX4-Autopilot/pull/29765
- [ ] Optional: PR to https://github.com/qnx/codelabs adding `markdown/px4-sih-on-qnx/` (copy of `codelab/px4-sih-on-qnx/`).
- [x] Demo video (2:21) on YouTube: https://youtu.be/ayAlSFN90dM
- [x] Devpost form submitted.

## Rules check (from hackathon_details.md / rules_full.md)

| Rule | Where | Status |
|---|---|---|
| New repo created in the submission period, not a fork | `px4-qnx` (patches only, no upstream source) | done |
| Open-source license visible in About | `LICENSE` (BSD-3-Clause, same as PX4) | done |
| Build/run instructions with QNX version, target, toolchain | `README.md` (SDP 8.0.5, QEMU x86_64, qcc 12.2.0) | done |
| Upstream project URL | `README.md` (PX4/PX4-Autopilot, v1.17.0) | done |
| Upstream PR URL | https://github.com/PX4/PX4-Autopilot/pull/29765 | done (draft) |
| Every claim backed by a script | `docs/results.md` cites `bench/` and `tests/` for each number | done |
| Video under 3 min, public or unlisted, YouTube | https://youtu.be/ayAlSFN90dM | done |
| Codelab URL | GitHub Pages | done (one URL per form; see note under "Codelab URL") |

---

## Devpost form

### Project name

PX4 on QNX: Open-Source Autopilot Ported to QNX 8.0

### Elevator pitch

PX4, the open-source drone autopilot, ported to QNX 8.0. Built with qcc, flies a simulated quadcopter in a QNX VM, and keeps its 800 Hz control loop steady under CPU overload where Linux drops 21%.

### About the project

```markdown
## Inspiration

PX4 is the open-source autopilot behind a large share of research and commercial drones. It runs on NuttX for flight controllers and on Linux for simulation and companion computers. QNX is the RTOS that cars, medical devices and industrial systems trust for hard real-time and safety work, and QNX 8.0 is now free for non-commercial use. A flight stack is a good fit for a real-time OS, yet PX4 had never run on QNX. I wanted to find out how far PX4's POSIX layer was from QNX, and whether QNX's scheduler would show a measurable difference for a real control loop.

## What it does

- PX4 v1.17.0 builds with the QNX SDP 8.0.5 toolchain (`qcc`/`q++` 12.2.0) and runs on QNX 8.0 in a QEMU x86_64 VM.
- It boots PX4's normal startup script with the built-in SIH simulator and flies a full mission: arm, take off to 10 m, hold, fly a 4-waypoint square, land.
- It talks MAVLink to QGroundControl and MAVSDK on the host.
- Every PX4 thread gets a real QNX `SCHED_FIFO` priority, with the rate controller at the top (253).
- A new PX4 module, `qnx_state_resmgr`, is a native QNX resource manager: any QNX process can `cat /dev/px4/state` to read live vehicle state.
- 7 automated tests and a set of benchmarks back every claim, and one script rebuilds everything from an empty directory.

## How I built it

I did not create a new PX4 platform. PX4 already handles macOS and Cygwin as small branches inside `platforms/posix`, so I added a `__PX4_QNX` branch the same way. The work is 6 patches on top of the `v1.17.0` tag:

1. A CMake toolchain file for `qcc`, QNX platform detection, `libsocket` linking, and a `qnx_sitl` board with only the modules SIH flight needs.
2. Build fixes: QNX has `statvfs` but no `statfs`, no `dirent::d_type`, different termios constants, and reserves priorities 254 and 255.
3. Explicit thread scheduling, SITL defines for the QNX board, and a MAVLink partner address so the VM can reach the host at `10.0.2.2`.
4. A rate-controller interval counter used by the benchmarks.
5. The `/dev/px4/state` resource manager.
6. Review fixes: a fixed-priority channel for the resource manager, per-open snapshots, and a work-queue priority cap.

Code generation (uORB, parameters, MAVLink) stays on the Linux host; only the C/C++ is cross-compiled. The VM is built with `mkqnximage`, and PX4 runs from the writable `/data` partition because the root image is read-only.

## Results

All numbers come from scripts in the repo, run on the same host. I only compare runs side by side, never absolute VM timings.

| Run (30 s, 800 Hz target = 24000 updates) | Updates | Worst gap |
|---|---|---|
| Linux SITL, idle | 24003 | 2.8 ms |
| Linux SITL, 2x CPU overload | 18953 | 28.0 ms |
| QNX, 2x CPU overload at priority 10 | 24006 | 1.4 ms |
| QNX, 2x CPU overload at FIFO 200 | 24037 | 1.4 ms |

Under load, stock Linux SITL (unprivileged, so without real-time priorities) lost 21% of rate-controller updates. On QNX the control loop did not change, even when the load ran at FIFO priority 200. Only the lower-priority PX4 tasks waited, as strict priorities say they should. A kernel trace with `tracelogger` shows the rate-controller thread gets a CPU a median 2.6 µs after it becomes ready.

In a fault test, a separate process grabs CPU and 512 MiB, then crashes mid-mission. The mission still completes, PX4's process is untouched, and QNX's `dumper` saves a core file.

## Challenges

- **Priorities that silently did nothing.** POSIX threads inherit their creator's scheduling unless `PTHREAD_EXPLICIT_SCHED` is set. Linux SITL hides this because it runs without privileges. On QNX every work queue ended up at 253. Setting explicit scheduling fixed the order: rate control 253, EKF2 239, high-priority work 235, low-priority work 203.
- **Timer granularity.** QNX timers round to the kernel tick, 1 ms by default, so the 800 Hz loop ran as a mix of 1 ms and 2 ms waits. Booting `procnto -C 10000` (10 kHz tick) cut the jitter about 6x, with no PX4 code change.
- **Priority inheritance in message passing.** QNX gives a server thread the priority of its client. A FIFO-253 reader of `/dev/px4/state` would have run the server above the rate controller. Creating the channel with `_NTO_CHF_FIXED_PRIORITY` keeps it at 97, and a test checks this.
- **A board-name trap.** PX4 picks its startup scripts by checking whether the board name contains `sitl`. Turning on the Linux SITL define globally enabled a parameter type check that crashed on VTOL params this board does not build. I tracked it down with `ntox86_64-gdb` on a core file.

## What I learned

QNX is POSIX enough that a large C++ codebase ports with small `#if` blocks, but the details that matter for real time (priority ranges, inheritance, tick-based timers, message-passing priority) are exactly where QNX differs. Strict priorities are a tool, not magic: with a load at FIFO 245, EKF2 at 239 ran once in 30 seconds. On QNX the system designer decides who wins, and a wrong choice shows up right away.

## What's next

Get the upstream PR to PX4 reviewed and merged (https://github.com/PX4/PX4-Autopilot/pull/29765, draft), add uXRCE-DDS for ROS 2, and try real hardware on a Raspberry Pi 5 running QNX 8.0.
```

### Built with

qnx, qnx-sdp-8.0, qcc, mkqnximage, qemu, kvm, px4, c++, c, cmake, ninja, python, mavlink, mavsdk, qgroundcontrol, tracelogger, bash, git, github-pages, claat

### "Try it out" links

- https://github.com/Sarcastic-Soul/px4-qnx
- https://sarcastic-soul.github.io/px4-qnx/ (project site, both codelabs)
- https://github.com/PX4/PX4-Autopilot/pull/29765

### Image gallery (3:2, under 5 MB)

- `docs/img/timing.png`: rate-loop timing, Linux vs QNX under load
- **(you)** screenshots: QGroundControl with the vehicle mid-mission; terminal with `pidin` priorities; terminal with `cat /dev/px4/state`; `tests/run-all.sh` ending in `ALL TESTS PASSED`; codelab page

### Demo video URL

https://youtu.be/ayAlSFN90dM

---

### Additional info

Submitter type: Individual

Country of residence: India

Organization name: (leave blank)

New or existed before November 2, 2026: New

If it existed before: N/A

Category: Open-Source Contribution & Ports

Public code repository:

https://github.com/Sarcastic-Soul/px4-qnx

Build and run instructions:

QNX version: QNX SDP 8.0.5 (QNX 8.0.0). Target: QEMU x86_64 with KVM, 4 vCPU, 2 GB RAM, image built with mkqnximage. Toolchain: qcc/q++ 12.2.0 (gcc_ntox86_64 / gcc_ntox86_64_cxx), CMake + Ninja; PX4 code generation runs in a host Python venv.

Host needs: Linux x86_64 with KVM, qemu-system-x86_64, QNX SDP 8.0.5 at ~/qnx800, an ssh key at ~/.ssh/id_ed25519_qnx, git, CMake, Ninja, uv. QGroundControl optional.

From the repo root:
scripts/fetch-upstream.sh (PX4 v1.17.0 + submodules)
scripts/apply-patches.sh (git am the 6 QNX patches)
scripts/setup-venv.sh
scripts/build.sh (outputs a QNX ELF, interpreter /usr/lib/ldqnx-64.so.2)
scripts/make-vm.sh (mkqnximage, procnto -C 10000)
scripts/run-vm.sh (headless, ssh on localhost:2222)
scripts/deploy.sh (PX4 into /data/px4 in the VM)
scripts/px4-vm.sh start (PX4 SIH quad, MAVLink to the host on UDP 14550/14540)

tests/run-all.sh runs all 7 checks, including a full MAVSDK flight. scripts/fresh-clone-test.sh does the whole thing from an empty directory. Full details in README.md and the codelab.

How it meets the main technology requirement:

PX4 runs on QNX 8.0 in QEMU. QNX products and features used, with where to look:

- QNX SDP 8.0.5 with qcc/q++ 12.2.0: cross-compiles all of PX4. Toolchain file platforms/posix/cmake/Toolchain-qnx-x86_64.cmake and __PX4_QNX detection in px4_impl_os.cmake (patch 0001). scripts/build.sh prints the QNX ELF check.
- mkqnximage + QEMU: builds the QNX 8.0 VM with a 10 kHz kernel tick (procnto -C 10000) through an options snippet. scripts/make-vm.sh. Demo: uname -a shows QNX 8.0.0.
- QNX real-time scheduling: every PX4 thread runs SCHED_FIFO at 1..253 (254/255 are reserved in 8.0). PTHREAD_EXPLICIT_SCHED added in WorkQueueManager.cpp, log_writer_file.cpp, mavlink_receiver.cpp, worker_thread.cpp (patch 0003). tests/test_priorities.sh checks pidin output: rate_ctrl 253 > INS0 239 > hp 235 > lp 203.
- Resource manager and Neutrino message passing: new PX4 module src/modules/qnx_state_resmgr (patches 0005/0006) uses dispatch_create_channel, resmgr_attach, iofunc_* with a per-open OCB, and ChannelCreate with _NTO_CHF_FIXED_PRIORITY so the server stays at priority 97 for real-time readers. Demo: cat /dev/px4/state during flight. tests/test_resmgr.sh.
- QNX networking (libsocket, io-sock): MAVLink to the host at 10.0.2.2. tests/test_flight.py flies the mission over it.
- System analysis: tracelogger + traceprinter capture of the rate-controller thread (bench/trace_ratectrl.sh, bench/trace_latency.py): ready-to-running median 2.6 us under load.
- Process isolation and dumper: tests/test_fault_isolation.sh crashes a separate CPU/RAM-hogging process mid-mission; the mission completes and the core file lands in /data/var/dumper.
- pidin, on -p, slog2info, ntox86_64-gdb: used for testing, loading at chosen priorities, and debugging core files.

Result: under 2x CPU overload, stock Linux SITL (no real-time priorities) lost 21% of rate-controller updates; on QNX the 800 Hz loop did not change, even with the load at FIFO 200 (docs/results.md). Full map of files and proofs: docs/qnx-evidence.md.

Upstream project URL:

https://github.com/PX4/PX4-Autopilot

Pull request URL:

https://github.com/PX4/PX4-Autopilot/pull/29765

Codelab URL:

https://sarcastic-soul.github.io/px4-qnx/codelab-site/qnx-resmgr-priority/

Note: the form takes one URL and the prize is judged per codelab. This one is the stronger entry: short (about 38 min), needs only a QNX target (no PX4 build), teaches a QNX-only behaviour (message-passing priority inheritance) and measures both sides of it on QNX 8.0 (200 ms control-loop stall vs 1.7 s priority inversion), with `codelab/qnx-resmgr-priority/run-demo.sh` checking every number. The PX4 codelab is linked from the site and from inside this one. The rules allow more than one submission only if each is "substantially different", so a second Devpost entry just for the PX4 codelab is not worth the risk.

How likely are you to use QNX again: **(you)** pick your own answer

How much did this hackathon help you develop new skills: **(you)** pick your own answer

AI tools used:

Kiro (Claude) as a coding agent for porting, scripts, tests and docs. All results come from the scripts in the repo and were checked by running them.

Checkboxes (age of majority, eligible jurisdiction, not sponsor staff): **(you)** confirm and tick all three.
