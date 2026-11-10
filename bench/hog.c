/*
 * CPU hog for the timing benchmarks: N busy threads running for <seconds>
 * (default 60). Same source builds with qcc (QNX) and gcc (Linux).
 *
 * Every thread checks the deadline itself. A separate timer thread would not
 * work when the hog runs at a real-time priority: with more busy threads
 * than CPUs at the same SCHED_FIFO priority, a sleeping timer thread never
 * gets the CPU back.
 *
 * Usage: hog <threads> [seconds]
 */
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static uint64_t deadline_ns;

static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}

static void *spin(void *arg)
{
	volatile unsigned long x = 0;
	(void)arg;

	while (now_ns() < deadline_ns) {
		for (int i = 0; i < 100000; i++) {
			x++;
		}
	}

	return NULL;
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 4;
	int secs = argc > 2 ? atoi(argv[2]) : 60;

	if (n < 1 || n > 256 || secs < 1) {
		fprintf(stderr, "usage: hog <threads 1..256> [seconds >= 1]\n");
		return 2;
	}

	deadline_ns = now_ns() + (uint64_t)secs * 1000000000u;
	pthread_t t[256];

	for (int i = 0; i < n; i++) {
		if (pthread_create(&t[i], NULL, spin, NULL) != 0) {
			perror("pthread_create");
			return 1;
		}
	}

	for (int i = 0; i < n; i++) {
		pthread_join(t[i], NULL);
	}

	return 0;
}
