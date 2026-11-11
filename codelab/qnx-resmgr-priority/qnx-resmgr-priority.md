id: qnx-resmgr-priority
title: Write a QNX 8.0 Resource Manager and Control Its Priority
summary: Build a /dev resource manager in 150 lines of C, then measure how QNX message passing hands priority from client to server, when that helps, and when it breaks a real-time loop.
categories: real-time, message passing, resource managers
tags: beginner
difficulty: 2
status: published
authors: Anish Kumar
feedback_link: https://github.com/Sarcastic-Soul/px4-qnx/issues


# Write a QNX 8.0 Resource Manager and Control Its Priority

## Overview
Duration: 2:00

On QNX almost everything is a **resource manager**: a normal process that registers a path such as `/dev/ser1` or `/dev/shmem` and answers `open()`, `read()` and `write()` as **messages**. A client calls `read()`, the C library turns it into `MsgSend()`, and the kernel delivers it to the server's channel.

That message has a side effect most tutorials skip: by default the server thread **runs at the client's priority** while it handles the request. In this codelab you see that happen, then measure two cases where it matters in real systems.

### What you'll do
- Write `/dev/prio`, a resource manager that reports the priority it runs at
- Read it at priority 10, 60 and 200 and watch the server follow the client
- Turn inheritance off with `_NTO_CHF_FIXED_PRIORITY`
- Measure a 1 kHz control loop losing **200 ms** to a server with inheritance
- Measure a server without inheritance starving a client for **1.7 s** (priority inversion)
- Pick the right channel flag for your own server

### What you'll need
- QNX SDP 8.0 with a non-commercial QNX Everywhere license (see the [license codelab](https://qnx.github.io/codelabs/get-non-commercial-qnx-license/))
- A QNX 8.0 target you can ssh into as root. A QEMU VM from `mkqnximage` works: see [Get started with QNX in a VM](https://qnx.github.io/codelabs/) or the `scripts/make-vm.sh` / `scripts/run-vm.sh` pair in the [px4-qnx](https://github.com/Sarcastic-Soul/px4-qnx) repo
- At least 2 CPUs on the target (the experiments pin work to CPU 0 with `on -C 0`)
- Basic C

All source files are in [`codelab/qnx-resmgr-priority/src`](https://github.com/Sarcastic-Soul/px4-qnx/tree/main/codelab/qnx-resmgr-priority/src). `run-demo.sh` next to them builds everything, runs every step on the target, and fails if QNX does not behave as described here.

---

## How a resource manager works
Duration: 3:00

```
client process                         server process (/dev/prio)
--------------                         --------------------------
fd = open("/dev/prio")  -- _IO_CONNECT -->  connect_funcs.open
read(fd, buf, n)        -- _IO_READ ----->  io_funcs.read
          ^                                     |
          +------------ MsgReply ---------------+
```

1. The server creates a **channel** and calls `resmgr_attach()` to register `/dev/prio` in the path space.
2. `open("/dev/prio")` asks the process manager who owns that path, then connects to the server's channel.
3. Every call on the fd is a message. The server's dispatch loop receives it and calls your handler.
4. Your handler fills in the reply and the client's `read()` returns.

The QNX `iofunc_*` library has default handlers for almost everything (permissions, `stat`, `lseek`, `close`). You only write the parts that make your device different. Here that is two functions:

| Function | Called when | Our version |
|---|---|---|
| `ocb_calloc` | each `open()` | allocate a per-open block and format one line of text into it |
| `io_read` | each `read()` | copy that text to the client |

The **OCB** (open control block) is per open file descriptor. Keeping the text there means two readers never see each other's bytes.

---

## Write the server
Duration: 8:00

Create `prio_dev.c`. Start with the OCB. Defining `IOFUNC_OCB_T` and `RESMGR_OCB_T` before the QNX headers makes the library's handler types use your struct:

```c
struct prio_ocb;
#define IOFUNC_OCB_T struct prio_ocb
#define RESMGR_OCB_T struct prio_ocb

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/dispatch.h>
#include <sys/iofunc.h>
#include <sys/neutrino.h>
#include <time.h>

struct prio_ocb {
    iofunc_ocb_t hdr; /* must be first */
    char text[128];
    size_t len;
};
```

QNX's `struct sched_param` has a field POSIX doesn't: `sched_curpriority`, the priority the thread is running at **right now**, including any priority it was handed by a client.

```c
static int current_priority(void)
{
    struct sched_param param;
    int policy;

    if (pthread_getschedparam(pthread_self(), &policy, &param) != EOK) {
        return -1;
    }

    return param.sched_curpriority;
}
```

On each `open()`, do some optional busy work (we use it later to stand in for a server that computes its answer), then record the priority:

```c
static struct prio_ocb *ocb_calloc(resmgr_context_t *ctp, iofunc_attr_t *attr)
{
    (void)attr;
    struct prio_ocb *ocb = calloc(1, sizeof(*ocb));

    if (ocb != NULL) {
        g_count++;
        busy_work(g_work_ms);
        int n = snprintf(ocb->text, sizeof(ocb->text),
                 "request=%u server_prio=%d client_pid=%d\n",
                 g_count, current_priority(), ctp->info.pid);
        ocb->len = (n > 0) ? (size_t)n : 0;
    }

    return ocb;
}
```

`ctp->info` carries details about the sender, such as its process ID, filled in by the kernel.

The read handler checks access, then returns whatever is left of the text from the current offset. Returning 0 bytes is how the client sees end of file:

```c
static int io_read(resmgr_context_t *ctp, io_read_t *msg, struct prio_ocb *ocb)
{
    int status = iofunc_read_verify(ctp, msg, &ocb->hdr, NULL);

    if (status != EOK) {
        return status;
    }

    if ((msg->i.xtype & _IO_XTYPE_MASK) != _IO_XTYPE_NONE) {
        return ENOSYS;
    }

    size_t off = (size_t)ocb->hdr.offset;
    size_t nbytes = 0;

    if (off < ocb->len) {
        nbytes = ocb->len - off;

        if (nbytes > msg->i.nbytes) {
            nbytes = msg->i.nbytes;
        }
    }

    if (nbytes > 0) {
        SETIOV(ctp->iov, ocb->text + off, nbytes);
        ocb->hdr.offset += nbytes;
    }

    _IO_SET_READ_NBYTES(ctp, nbytes);
    return _RESMGR_NPARTS(nbytes > 0 ? 1 : 0);
}
```

`SETIOV` points the reply at our buffer. The resource manager library sends it with `MsgReply` after the handler returns, so nothing is copied twice.

The full file, with `busy_work()` and the globals, is [`src/prio_dev.c`](https://github.com/Sarcastic-Soul/px4-qnx/blob/main/codelab/qnx-resmgr-priority/src/prio_dev.c).

---

## Attach the path and run the loop
Duration: 4:00

`main()` creates the channel itself, so we control its flags. A compile-time switch picks the flag we compare later:

```c
int main(int argc, char **argv)
{
    g_work_ms = argc > 1 ? (unsigned)atoi(argv[1]) : 0;

    static resmgr_connect_funcs_t connect_funcs;
    static resmgr_io_funcs_t io_funcs;
    static iofunc_funcs_t ocb_funcs = {.nfuncs = _IOFUNC_NFUNCS,
                       .ocb_calloc = ocb_calloc, .ocb_free = ocb_free};
    static iofunc_mount_t mount = {.funcs = &ocb_funcs};
    static iofunc_attr_t attr;

#ifdef FIXED
    unsigned flags = _NTO_CHF_FIXED_PRIORITY; /* server keeps its own priority */
#else
    unsigned flags = 0;                       /* server runs at the client's priority */
#endif
    int chid = ChannelCreate(flags | _NTO_CHF_DISCONNECT | _NTO_CHF_UNBLOCK);
    dispatch_t *dpp = dispatch_create_channel(chid, DISPATCH_FLAG_NOLOCK);

    iofunc_func_init(_RESMGR_CONNECT_NFUNCS, &connect_funcs, _RESMGR_IO_NFUNCS, &io_funcs);
    io_funcs.read = io_read;
    iofunc_attr_init(&attr, S_IFCHR | 0444, NULL, NULL);
    attr.mount = &mount;

    resmgr_attach(dpp, NULL, "/dev/prio", _FTYPE_ANY, 0, &connect_funcs, &io_funcs, &attr);

    dispatch_context_t *ctp = dispatch_context_alloc(dpp);

    for (;;) {
        ctp = dispatch_block(ctp);   /* MsgReceive */
        dispatch_handler(ctp);       /* calls our handlers, then MsgReply */
    }
}
```

(Error checks are left out above to keep it short. The source file has them.)

Notes:
- When you create the channel yourself for a resource manager, the `dispatch_create_channel()` docs say to set at least `_NTO_CHF_UNBLOCK` and `_NTO_CHF_DISCONNECT`.
- `mount.funcs` is how the library finds your `ocb_calloc`/`ocb_free`.
- `0444` sets the mode `ls -l` shows. Root still passes the permission check, so if writes must fail for everyone, return `EROFS` from your own `open` handler when `msg->connect.ioflag & _IO_FLAG_WR` is set (the PX4 module does this).
- `resmgr_attach` needs the `PATHSPACE` ability. Root has it.

<aside class="negative">
Most examples call <code>dispatch_create()</code>, which creates the channel for you with <strong>no</strong> <code>_NTO_CHF_FIXED_PRIORITY</code>. If you want a fixed-priority server, create the channel yourself and pass it to <code>dispatch_create_channel()</code>.
</aside>

---

## Build and copy
Duration: 4:00

You also need two small clients from the repo:

- [`src/prio_read.c`](https://github.com/Sarcastic-Soul/px4-qnx/blob/main/codelab/qnx-resmgr-priority/src/prio_read.c): opens a path once, prints its own priority, how long the call took, and what it read.
- [`src/prio_tick.c`](https://github.com/Sarcastic-Soul/px4-qnx/blob/main/codelab/qnx-resmgr-priority/src/prio_tick.c): a stand-in control loop. Wakes every 1 ms and prints the worst gap between wakeups.

And a CPU hog, [`bench/hog.c`](https://github.com/Sarcastic-Soul/px4-qnx/blob/main/bench/hog.c), for the last experiment.

On the host, in **bash**:

```bash
source ~/qnx800/qnxsdp-env.sh
qcc -Vgcc_ntox86_64 -Wall -O2 -o prio_dev        prio_dev.c
qcc -Vgcc_ntox86_64 -Wall -O2 -o prio_dev_fixed  prio_dev.c -DFIXED
qcc -Vgcc_ntox86_64 -Wall -O2 -o prio_read       prio_read.c
qcc -Vgcc_ntox86_64 -Wall -O2 -o prio_tick       prio_tick.c
qcc -Vgcc_ntox86_64 -Wall -O2 -o hog             hog.c
```

Use `-Vgcc_ntoaarch64le` instead for a Raspberry Pi or other ARM target.

Copy them to a writable directory on the target (QEMU VMs from `mkqnximage` have `/data`):

```bash
ssh root@<target> mkdir -p /data/codelab
scp -O prio_dev prio_dev_fixed prio_read prio_tick hog root@<target>:/data/codelab/
```

<aside class="positive">
<code>scp -O</code> uses the legacy SCP protocol. The QNX image's <code>sshd</code> has no SFTP server by default, so plain <code>scp</code> fails without it.
</aside>

---

## Who runs the server?
Duration: 4:00

ssh into the target, then start the server in the background. It starts at the shell's priority, 10:

```bash
cd /data/codelab
./prio_dev &
```

```
/dev/prio ready, server priority 10, channel default (inherits), work 0 ms
```

It's a normal file now. `ls -l /dev/prio` and `cat /dev/prio` both work. Read it from clients at three priorities. `on -p 60f` runs a command at priority 60 with `SCHED_FIFO`:

```bash
./prio_read
on -p 60f ./prio_read
on -p 200f ./prio_read
```

```
client_prio=10 took_ms=0.1 request=1 server_prio=10 client_pid=1753110
client_prio=60 took_ms=0.1 request=2 server_prio=60 client_pid=1761302
client_prio=200 took_ms=0.1 request=3 server_prio=200 client_pid=1773590
```

The server's own priority is 10, but it handled each request at the **client's** priority. Look at the thread while it waits:

```bash
pidin -p prio_dev -F "%N %h %p %J"
```

```
name               thread name          prio STATE
prio_dev           1                    200r RECEIVE
```

It stays at the last priority it was given until the next message arrives.

Now the fixed-priority build:

```bash
slay prio_dev
./prio_dev_fixed &
./prio_read
on -p 60f ./prio_read
on -p 200f ./prio_read
slay prio_dev_fixed
```

```
client_prio=10 took_ms=0.2 request=1 server_prio=10 client_pid=1818646
client_prio=60 took_ms=0.1 request=2 server_prio=10 client_pid=1826838
client_prio=200 took_ms=0.1 request=3 server_prio=10 client_pid=1839126
```

The server stays at 10 for every client.

---

## Experiment 1: a client runs server work above your control loop
Duration: 5:00

Inheritance means a high-priority client can make a server do **its work at high priority**, even if that work has nothing to do with real time. Here:

- `prio_tick` is a 1 kHz control loop at FIFO **100**.
- `prio_dev 200` spends **200 ms** of CPU on each request. Think of a logger formatting a big status dump.
- A client at FIFO **200** reads it once.
- Everything runs on CPU 0 (`on -C 0`) so they really compete.

```bash
on -C 0 ./prio_dev 200 &
sleep 1
on -C 0 -p 100f ./prio_tick 2 &
sleep 0.5
on -C 0 -p 200f ./prio_read
wait $!
slay prio_dev
```

```
client_prio=200 took_ms=200.1 request=1 server_prio=200 client_pid=1921047
tick: 1521 cycles in 2 s, worst gap 201.7 ms
```

The control loop missed **200 cycles in a row**. The server's code ran at 200, above the loop at 100, because the client asked for it. Same test with `prio_dev_fixed 200`:

```
client_prio=200 took_ms=200.1 request=1 server_prio=10 client_pid=1990679
tick: 1691 cycles in 2 s, worst gap 1.4 ms
```

The loop is untouched. The 200 ms of work now runs at 10, below the loop, and the client still gets its answer in the same time, because the loop sleeps between ticks and leaves CPU time free.

<aside class="negative">
This is what a fixed-priority channel is for: a server that does <strong>non-critical work</strong> for <strong>critical clients</strong>. The <a href="https://github.com/Sarcastic-Soul/px4-qnx">PX4 on QNX port</a> uses it for <code>/dev/px4/state</code>, so a real-time reader can't run the state server above the flight controller.
</aside>

---

## Experiment 2: priority inversion
Duration: 5:00

Fixed priority has a cost. If the server's own priority is low, **anything** between it and the client can delay the client. That is priority inversion, and inheritance exists to prevent it.

- `prio_dev 5`: 5 ms of work per request, own priority 10
- `hog 1 2`: one busy thread at round-robin priority **30** for 2 s
- A client at FIFO **60** reads once

All on CPU 0:

```bash
on -C 0 ./prio_dev 5 &
sleep 1
on -C 0 -p 30r ./hog 1 2 > /dev/null &
sleep 0.3
on -C 0 -p 60f ./prio_read
sleep 2; slay prio_dev
```

```
client_prio=60 took_ms=5.0 request=1 server_prio=60 client_pid=2084887
```

With inheritance the server ran at 60, above the hog, and replied in 5 ms. With `prio_dev_fixed 5`:

```
client_prio=60 took_ms=1701.7 request=1 server_prio=10 client_pid=2162711
```

**1.7 seconds** for a 5 ms request. The client at 60 was blocked on a server at 10, and the hog at 30 sat in between until it finished.

### Run all of it in one go
From the repo root on the host, with the VM running:

```bash
codelab/qnx-resmgr-priority/run-demo.sh
```

```
PASS: inheritance gap 201.7 ms vs fixed 1.4 ms; inversion: inherit 5.0 ms vs fixed 1701.7 ms
```

---

## Choosing the flag
Duration: 2:00

| Server does | Clients are | Use |
|---|---|---|
| Real-time work for real-time clients (a driver, a sensor server) | any | default channel: inheritance prevents inversion |
| Non-critical work, may be slow (logging, status, diagnostics) | may be real-time | `_NTO_CHF_FIXED_PRIORITY`, and set the server's own priority on purpose |
| Mixed | mixed | split it: one fixed-priority channel for slow requests, a normal one for fast ones |

With a fixed-priority server, its own priority is now **your** design decision. Pick it above anything that could block its clients for too long, and below anything it must never delay.

Also worth knowing:
- Pulses (`MsgSendPulse`) carry a priority too, and a server thread receiving one also switches to it.
- `pidin` with `%p` shows a thread's current priority with its policy letter (`f` FIFO, `r` round robin, `o` other).
- Priorities 254 and 255 are reserved for the kernel in QNX 8.0. Applications use 1..253.

---

## Clean up and next steps
Duration: 1:00

```bash
slay -f prio_dev; slay -f prio_dev_fixed
rm -r /data/codelab
```

You wrote a QNX resource manager, saw Neutrino message passing hand the client's priority to the server, and measured both sides of that design: a 200 ms control-loop stall when a fixed-priority server would have been right, and a 1.7 s inversion when inheritance would have been right.

### Learn more
- [Writing a Resource Manager](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.resmgr/topic/about.html)
- [`ChannelCreate()`](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.lib_ref/topic/c/channelcreate.html): all channel flags
- [Getting Started with QNX: message passing and priority inheritance](https://www.qnx.com/developers/docs/8.0/com.qnx.doc.neutrino.getting_started/topic/about.html)
- [PX4 on QNX 8.0](https://sarcastic-soul.github.io/px4-qnx/): a real fixed-priority resource manager inside a flight controller
