/*
 * prio_dev: a minimal QNX 8.0 resource manager at /dev/prio.
 *
 * Every open() gets a one-line answer that says at which priority the
 * server thread handled the request. Optional argument: milliseconds of
 * busy work per request (default 0). Build it twice to see the difference:
 *
 *   qcc -Vgcc_ntox86_64 -o prio_dev prio_dev.c                 (inherits)
 *   qcc -Vgcc_ntox86_64 -DFIXED -o prio_dev_fixed prio_dev.c   (fixed)
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/* Each open() gets its own OCB (open control block) that holds its text. */
struct prio_ocb;
#define IOFUNC_OCB_T struct prio_ocb
#define RESMGR_OCB_T struct prio_ocb

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/dispatch.h>
#include <sys/iofunc.h>
#include <sys/neutrino.h>
#include <time.h>
#include <unistd.h>

struct prio_ocb {
	iofunc_ocb_t hdr; /* must be first */
	char text[128];
	size_t len;
};

static unsigned g_count;
static unsigned g_work_ms; /* busy work per request, from argv[1] */

/* Burn CPU for ms milliseconds, like a server that computes its answer. */
static void busy_work(unsigned ms)
{
	struct timespec t0, t;
	clock_gettime(CLOCK_MONOTONIC, &t0);

	do {
		clock_gettime(CLOCK_MONOTONIC, &t);
	} while ((t.tv_sec - t0.tv_sec) * 1000 + (t.tv_nsec - t0.tv_nsec) / 1000000 < (long)ms);
}

/* The priority this thread is running at right now. On QNX that can differ
 * from its own set priority: sched_curpriority shows the inherited value. */
static int current_priority(void)
{
	struct sched_param param;
	int policy;

	if (pthread_getschedparam(pthread_self(), &policy, &param) != EOK) {
		return -1;
	}

	return param.sched_curpriority;
}

/* Runs in the server thread when a client calls open(). */
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

static void ocb_free(struct prio_ocb *ocb)
{
	free(ocb);
}

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

int main(int argc, char **argv)
{
	g_work_ms = argc > 1 ? (unsigned)atoi(argv[1]) : 0;

	static resmgr_connect_funcs_t connect_funcs;
	static resmgr_io_funcs_t io_funcs;
	static iofunc_funcs_t ocb_funcs = {.nfuncs = _IOFUNC_NFUNCS, .ocb_calloc = ocb_calloc, .ocb_free = ocb_free};
	static iofunc_mount_t mount = {.funcs = &ocb_funcs};
	static iofunc_attr_t attr;

#ifdef FIXED
	/* The server keeps its own priority, whoever sends the message. */
	unsigned flags = _NTO_CHF_FIXED_PRIORITY;
#else
	/* Default: the server runs at the priority of the client. */
	unsigned flags = 0;
#endif
	int chid = ChannelCreate(flags | _NTO_CHF_DISCONNECT | _NTO_CHF_UNBLOCK);

	if (chid == -1) {
		perror("ChannelCreate");
		return 1;
	}

	dispatch_t *dpp = dispatch_create_channel(chid, DISPATCH_FLAG_NOLOCK);

	if (dpp == NULL) {
		perror("dispatch_create_channel");
		return 1;
	}

	iofunc_func_init(_RESMGR_CONNECT_NFUNCS, &connect_funcs, _RESMGR_IO_NFUNCS, &io_funcs);
	io_funcs.read = io_read;
	iofunc_attr_init(&attr, S_IFCHR | 0444, NULL, NULL);
	attr.mount = &mount;

	if (resmgr_attach(dpp, NULL, "/dev/prio", _FTYPE_ANY, 0, &connect_funcs, &io_funcs, &attr) == -1) {
		perror("resmgr_attach (run as root)");
		return 1;
	}

	printf("/dev/prio ready, server priority %d, channel %s, work %u ms\n", current_priority(),
	       (flags & _NTO_CHF_FIXED_PRIORITY) ? "FIXED_PRIORITY" : "default (inherits)", g_work_ms);
	fflush(stdout);

	dispatch_context_t *ctp = dispatch_context_alloc(dpp);

	for (;;) {
		ctp = dispatch_block(ctp);

		if (ctp == NULL) {
			perror("dispatch_block");
			return 1;
		}

		dispatch_handler(ctp);
	}
}
