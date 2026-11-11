# Submission checklist

Things only the author can do are marked **(you)**. Everything else is done and checked in this repo.

## Before submitting

- [ ] **(you)** QGroundControl check by eye: install QGC, `scripts/run-vm.sh && scripts/deploy.sh && scripts/px4-vm.sh start`, vehicle appears on UDP 14550, arm, take off, mission, land.
- [ ] **(you)** Create the public GitHub repo and push:
  ```sh
  gh repo create Sarcastic-Soul/px4-qnx --public --source . --remote origin \
     --description "PX4 Autopilot ported to QNX 8.0 (qcc, QEMU x86_64, SIH flight)"
  git push -u origin main
  ```
  Confirm "BSD-3-Clause" shows in the repo's About box.
- [ ] **(you)** GitHub Pages: Settings → Pages → Deploy from branch `main`, folder `/docs`. Codelab URL: `https://sarcastic-soul.github.io/px4-qnx/codelab-site/`. Optionally open a PR to https://github.com/qnx/codelabs adding `markdown/px4-sih-on-qnx/` (copy `codelab/px4-sih-on-qnx/`).
- [ ] **(you)** Upload a QNX ULog to https://logs.px4.io (`scripts/fetch-ulog.sh` prints the file path) and paste the link into `docs/upstream-pr.md`.
- [ ] **(you)** Open the upstream PR (steps in `docs/upstream-pr.md`) and add its URL to `README.md`.
- [ ] **(you)** Record the video (`docs/video-script.md`), upload to YouTube as public, under 3:00.
- [ ] **(you)** Fill in the Devpost form (field notes below).

## Rules check (from hackathon_details.md / rules_full.md)

| Rule | Where |
|---|---|
| New repo created in the submission period, not a fork | `px4-qnx` (patches only, no upstream source) |
| Open-source license visible | `LICENSE` (BSD-3-Clause, same as PX4) |
| Build/run instructions with QNX version, target, toolchain | `README.md` (SDP 8.0.5, QEMU x86_64, qcc 12.2.0) |
| Upstream project URL | `README.md` (PX4/PX4-Autopilot, v1.17.0) |
| Upstream PR URL | `README.md` **(you: add after opening)** |
| Every claim backed by a script | `docs/results.md` cites `bench/` and `tests/` for each number |
| Video < 3 min, public | **(you)** |
| Codelab URL | **(you: after Pages)** |

## Devpost form drafts

Copy the text below each label. Check every link after pushing.

Category:

Open-Source Contribution & Ports

Public repo URL:

https://github.com/Sarcastic-Soul/px4-qnx

Upstream project URL:

https://github.com/PX4/PX4-Autopilot (tag v1.17.0)

Build and run instructions:

Target: QNX SDP 8.0.5 (QNX 8.0.0) on QEMU x86_64 with KVM, 4 vCPU, 2 GB. Toolchain: qcc/q++ 12.2.0 (gcc_ntox86_64), CMake + Ninja. Host: Linux x86_64 with KVM, QNX SDP at ~/qnx800, uv, git, qemu-system-x86_64.

Commands, from the repo root: scripts/fetch-upstream.sh; scripts/apply-patches.sh; scripts/setup-venv.sh; scripts/build.sh; scripts/make-vm.sh; scripts/run-vm.sh; scripts/deploy.sh; scripts/px4-vm.sh start. Then tests/run-all.sh runs all 7 checks, including a MAVSDK flight. scripts/fresh-clone-test.sh does the whole thing from an empty directory. Full details are in README.md.

How it meets the technology requirement:

PX4 is built with the QNX SDP 8.0.5 toolchain (qcc/q++, platforms/posix/cmake/Toolchain-qnx-x86_64.cmake) and runs on QNX 8.0 in a VM made with mkqnximage. The kernel boots with procnto -C 10000 (scripts/make-vm.sh).

QNX real-time scheduling: every PX4 thread runs SCHED_FIFO at 1..253 (254/255 are reserved in 8.0). PTHREAD_EXPLICIT_SCHED was added because QNX threads inherit scheduling by default (WorkQueueManager.cpp and three others). tests/test_priorities.sh checks this.

QNX resource manager: the PX4 module qnx_state_resmgr (dispatch_create_channel, resmgr_attach, iofunc_*) serves live vehicle state at /dev/px4/state, and QNX message passing runs it at the reader's priority (tests/test_resmgr.sh).

System analysis: tracelogger/traceprinter capture of the rate-controller thread (bench/trace_ratectrl.sh). Process isolation plus dumper core files during a mission (tests/test_fault_isolation.sh). pidin, on -p, slog2info and ntox86_64-gdb were used throughout.

Result: under 2x CPU overload, Linux SITL lost 23% of rate-controller updates, while the QNX build kept 800 Hz even with the load at FIFO priority 200 (docs/results.md, bench/). Full map of files and demo timestamps: docs/qnx-evidence.md.

Pull request URL:

(add after opening, see docs/upstream-pr.md)

Codelab URL:

https://sarcastic-soul.github.io/px4-qnx/codelab-site/

AI tools used:

Kiro (Claude) as a coding agent for porting, scripts, tests and docs. All results were produced by the scripts in the repo and checked by running them.
