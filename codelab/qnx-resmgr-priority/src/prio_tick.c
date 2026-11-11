/*
 * prio_tick: a stand-in for a control loop. Wakes every 1 ms for <seconds>
 * (default 3) and prints the worst gap between two wakeups.
 *
 *   qcc -Vgcc_ntox86_64 -o prio_tick prio_tick.c
 *   on -p 100f ./prio_tick 3
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static uint64_t now_us(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}

int main(int argc, char **argv)
{
	int secs = argc > 1 ? atoi(argv[1]) : 3;
	const struct timespec period = {0, 1000 * 1000};
	uint64_t start = now_us();
	uint64_t last = start;
	uint64_t worst = 0;
	unsigned cycles = 0;

	while (last - start < (uint64_t)secs * 1000000u) {
		nanosleep(&period, NULL);
		uint64_t t = now_us();

		if (t - last > worst) {
			worst = t - last;
		}

		last = t;
		cycles++;
	}

	printf("tick: %u cycles in %d s, worst gap %.1f ms\n", cycles, secs, (double)worst / 1000.0);
	return 0;
}
