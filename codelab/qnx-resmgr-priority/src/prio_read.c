/*
 * prio_read: open and read a path once, print what came back and how long
 * it took. Used to show priority inheritance (and inversion) with prio_dev.
 *
 *   qcc -Vgcc_ntox86_64 -o prio_read prio_read.c
 *   on -p 60f ./prio_read /dev/prio
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include <fcntl.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static uint64_t now_us(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}

int main(int argc, char **argv)
{
	const char *path = argc > 1 ? argv[1] : "/dev/prio";
	char buf[256];

	uint64_t t0 = now_us();
	int fd = open(path, O_RDONLY);

	if (fd == -1) {
		perror(path);
		return 1;
	}

	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	uint64_t t1 = now_us();

	if (n < 0) {
		perror("read");
		return 1;
	}

	struct sched_param param;
	int policy;
	pthread_getschedparam(pthread_self(), &policy, &param);

	buf[n] = '\0';
	printf("client_prio=%d took_ms=%.1f %s", param.sched_priority, (double)(t1 - t0) / 1000.0, buf);
	return 0;
}
