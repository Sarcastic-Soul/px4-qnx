/*
 * Print CLOCK_MONOTONIC in microseconds, the same unit as PX4's
 * hrt_absolute_time(). Built with qcc and run inside the QNX VM by
 * tests/test_hrt.sh.
 */
#include <inttypes.h>
#include <stdio.h>
#include <time.h>

int main(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
		perror("clock_gettime");
		return 1;
	}

	printf("%" PRIu64 "\n", (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u);
	return 0;
}
