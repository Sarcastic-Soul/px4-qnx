/*
 * A misbehaving "companion app" for the fault-isolation test: it runs as its
 * own QNX process next to PX4, burns CPU, grabs memory, then dereferences a
 * NULL pointer and dies with SIGSEGV.
 *
 * Usage: badapp <threads> <MiB> <seconds-before-crash>
 */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void *spin(void *arg)
{
	volatile unsigned long x = 0;
	(void)arg;

	for (;;) {
		x++;
	}

	return NULL;
}

int main(int argc, char **argv)
{
	int threads = argc > 1 ? atoi(argv[1]) : 4;
	int mib = argc > 2 ? atoi(argv[2]) : 256;
	int secs = argc > 3 ? atoi(argv[3]) : 10;

	printf("badapp: pid %d, %d busy threads, %d MiB, crash in %d s\n", getpid(), threads, mib, secs);
	fflush(stdout);

	for (int i = 0; i < threads; i++) {
		pthread_t t;
		pthread_create(&t, NULL, spin, NULL);
	}

	for (int i = 0; i < mib; i++) {
		char *p = malloc(1 << 20);

		if (!p) {
			printf("badapp: malloc failed after %d MiB\n", i);
			break;
		}

		memset(p, 0xa5, 1 << 20); // touch it so it is really allocated
	}

	sleep(secs);
	printf("badapp: crashing now\n");
	fflush(stdout);
	volatile int *null_ptr = NULL;
	*null_ptr = 1;
	return 0;
}
