/*
 * Compare PX4's hrt_absolute_time() with QNX CLOCK_MONOTONIC.
 *
 * PX4's /dev/px4/state resource manager stamps every snapshot with
 * hrt_absolute_time() (t_us=...) when the file is opened. This helper reads
 * CLOCK_MONOTONIC just before open() and just after read(), so the true
 * offset (monotonic - px4) lies inside [before - t_us, after - t_us].
 *
 * Usage: hrtcheck <samples> <interval_ms>
 * Prints one line per sample: "<before_us> <t_us> <after_us>", then exits 0.
 */
#include <fcntl.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static uint64_t mono_us(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}

int main(int argc, char **argv)
{
	int samples = argc > 1 ? atoi(argv[1]) : 20;
	int interval_ms = argc > 2 ? atoi(argv[2]) : 500;
	char buf[512];

	for (int i = 0; i < samples; i++) {
		uint64_t before = mono_us();
		int fd = open("/dev/px4/state", O_RDONLY);

		if (fd < 0) {
			perror("open /dev/px4/state");
			return 1;
		}

		ssize_t n = read(fd, buf, sizeof(buf) - 1);
		uint64_t after = mono_us();
		close(fd);

		if (n <= 0) {
			fprintf(stderr, "read failed\n");
			return 1;
		}

		buf[n] = '\0';
		const char *t = strstr(buf, "t_us=");

		if (!t) {
			fprintf(stderr, "no t_us in: %s", buf);
			return 1;
		}

		uint64_t px4_us = strtoull(t + 5, NULL, 10);
		printf("%" PRIu64 " %" PRIu64 " %" PRIu64 "\n", before, px4_us, after);

		if (i + 1 < samples) {
			usleep((useconds_t)interval_ms * 1000u);
		}
	}

	return 0;
}
