/*
 * pomona-t1-boot - boot an Apple T1 (iBridge1,1) that sits in recovery mode
 * (USB 05ac:1281) from the EmbeddedOS image macOS keeps on the EFI System
 * Partition (EFI/APPLE/EMBEDDEDOS/combined.memboot).
 *
 * This is what macOS does after login on machines whose firmware does not
 * hand the image to the T1 at power-on. Everything happens in the T1's RAM:
 * no restore, no saveenv, nothing written to disk or to the chip. In the
 * worst case the T1 stays in recovery mode, where it started.
 *
 * Only libusb-1.0 is needed. The recovery-mode protocol is the one
 * libirecovery implements (upload: vendor request 0x41/0 then bulk OUT on
 * endpoint 0x04 in 32 KiB chunks; command: vendor request 0x40 with the
 * NUL-terminated string), reduced to what the T1 needs.
 *
 * usage: pomona-t1-boot [--breq N] [--no-bootargs] [--dry-run] FILE
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libusb.h>

#define APPLE_VID     0x05ac
#define RECOVERY_PID  0x1281
#define T1_CPID       "CPID:8002"
#define CHUNK         0x8000
#define TIMEOUT_MS    10000

/* combined.memboot is a concatenation of IMG4 containers; the first one
 * starts with a DER SEQUENCE header followed by IA5String "IMG4". */
static int looks_like_img4(const unsigned char *buf, unsigned long len)
{
	unsigned long i;

	if (len < 16 || buf[0] != 0x30)
		return 0;
	for (i = 1; i < 12 && i + 4 <= len; i++)
		if (memcmp(buf + i, "IMG4", 4) == 0)
			return 1;
	return 0;
}

static unsigned char *read_file(const char *path, unsigned long *len)
{
	FILE *f = fopen(path, "rb");
	unsigned char *buf;
	long n;

	if (!f) {
		perror(path);
		return NULL;
	}
	if (fseek(f, 0, SEEK_END) != 0 || (n = ftell(f)) <= 0 || fseek(f, 0, SEEK_SET) != 0) {
		fprintf(stderr, "%s: cannot read size\n", path);
		fclose(f);
		return NULL;
	}
	buf = malloc(n);
	if (!buf || fread(buf, 1, n, f) != (size_t)n) {
		fprintf(stderr, "%s: short read\n", path);
		fclose(f);
		free(buf);
		return NULL;
	}
	fclose(f);
	*len = (unsigned long)n;
	return buf;
}

static int send_command(libusb_device_handle *h, const char *cmd, uint8_t breq)
{
	size_t len = strlen(cmd) + 1;

	if (len > 0x100)
		return -1;
	return libusb_control_transfer(h, 0x40, breq, 0, 0, (unsigned char *)cmd, (uint16_t)len, TIMEOUT_MS);
}

static int upload(libusb_device_handle *h, unsigned char *buf, unsigned long len)
{
	unsigned long off = 0;
	int sent, r;

	r = libusb_control_transfer(h, 0x41, 0, 0, 0, NULL, 0, TIMEOUT_MS);
	if (r < 0) {
		fprintf(stderr, "upload start failed: %s\n", libusb_error_name(r));
		return -1;
	}
	while (off < len) {
		int size = (len - off) > CHUNK ? CHUNK : (int)(len - off);
		r = libusb_bulk_transfer(h, 0x04, buf + off, size, &sent, TIMEOUT_MS);
		if (r < 0 || sent != size) {
			libusb_clear_halt(h, 0x04);
			fprintf(stderr, "upload failed at %lu: %s\n", off, libusb_error_name(r));
			return -1;
		}
		off += size;
	}
	if (len % 512 == 0)
		libusb_bulk_transfer(h, 0x04, buf, 0, &sent, TIMEOUT_MS);
	return 0;
}

/* opens the T1 in recovery mode, or returns NULL */
static libusb_device_handle *open_t1(void)
{
	libusb_device_handle *h;
	unsigned char serial[256] = {0};
	struct libusb_device_descriptor d;
	int r;

	h = libusb_open_device_with_vid_pid(NULL, APPLE_VID, RECOVERY_PID);
	if (!h) {
		fprintf(stderr, "no Apple device in recovery mode (05ac:1281)\n");
		return NULL;
	}
	if (libusb_get_device_descriptor(libusb_get_device(h), &d) == 0 && d.iSerialNumber)
		libusb_get_string_descriptor_ascii(h, d.iSerialNumber, serial, sizeof(serial) - 1);
	if (!strstr((char *)serial, T1_CPID)) {
		fprintf(stderr, "device in recovery mode is not an Apple T1 (%s), refusing\n", serial);
		libusb_close(h);
		return NULL;
	}
	libusb_set_auto_detach_kernel_driver(h, 1);
	int cfg = 0;
	libusb_get_configuration(h, &cfg);
	if (cfg != 1 && (r = libusb_set_configuration(h, 1)) < 0) {
		fprintf(stderr, "cannot select configuration 1: %s\n", libusb_error_name(r));
		libusb_close(h);
		return NULL;
	}
	if ((r = libusb_claim_interface(h, 0)) < 0) {
		fprintf(stderr, "cannot claim interface 0: %s\n", libusb_error_name(r));
		libusb_close(h);
		return NULL;
	}
	printf("T1 found (%s)\n", T1_CPID);
	return h;
}

int main(int argc, char **argv)
{
	const char *path = NULL;
	int breq = 1, bootargs = 1, dry = 0, i, rc = 1;
	libusb_device_handle *h = NULL;
	unsigned char *image = NULL;
	unsigned long len = 0;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--breq") && i + 1 < argc)
			breq = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--no-bootargs"))
			bootargs = 0;
		else if (!strcmp(argv[i], "--dry-run"))
			dry = 1;
		else if (argv[i][0] == '-') {
			fprintf(stderr, "unknown option %s\n", argv[i]);
			return 2;
		} else
			path = argv[i];
	}
	if (!path) {
		fprintf(stderr, "usage: %s [--breq N] [--no-bootargs] [--dry-run] FILE\n", argv[0]);
		return 2;
	}

	image = read_file(path, &len);
	if (!image)
		return 1;
	if (!looks_like_img4(image, len)) {
		fprintf(stderr, "%s does not look like an IMG4 memboot image, refusing\n", path);
		goto out;
	}
	printf("image: %lu bytes\n", len);
	if (dry) {
		printf("dry run: image is valid, not talking to the device\n");
		rc = 0;
		goto out;
	}

	if (libusb_init(NULL) < 0) {
		fprintf(stderr, "libusb_init failed\n");
		goto out;
	}
	h = open_t1();
	if (!h)
		goto exit_usb;

	if (upload(h, image, len) < 0)
		goto close;
	printf("upload complete\n");

	/* RAM only: never followed by saveenv */
	if (bootargs && send_command(h, "setenv boot-args rd=md0", 0) < 0) {
		fprintf(stderr, "setenv boot-args failed\n");
		goto close;
	}

	/* blind memboot: the T1 resets its USB link, so the result is ignored */
	printf("memboot (bRequest=%d)\n", breq);
	send_command(h, "memboot", (uint8_t)breq);
	printf("sent; the T1 should reappear as 05ac:8600 within a few seconds\n");
	rc = 0;

close:
	libusb_release_interface(h, 0);
	libusb_close(h);
exit_usb:
	libusb_exit(NULL);
out:
	free(image);
	return rc;
}
