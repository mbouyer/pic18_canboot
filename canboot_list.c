/*
 * Copyright (c) 2017,2021 Manuel Bouyer
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE NETBSD FOUNDATION, INC. AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <err.h>
#include <string.h>

#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/sockio.h>
#include <net/if.h>
#ifdef __NetBSD__
#include <netcan/can.h>
#else
#include <linux/can.h>
#include <linux/can/raw.h>
#endif
#include "nmea2000_pgn.h"
#include "nmea2000_class.h"

int s;

static void
usage()
{
	fprintf(stderr, "usage: canboot_list <interface>\n");
	exit(1);
}

static void
send_iso_request()
{
	struct can_frame cf;
	int i, j, r;
	uint16_t csum;
again:
	cf.can_id =  (NMEA2000_PRIORITY_CONTROL << 26) | ((ISO_REQUEST >> 8) << 16) | (NMEA2000_ADDR_GLOBAL << 8) | NMEA2000_ADDR_NULL | CAN_EFF_FLAG;
	cf.data[0] = (ISO_ADDRESS_CLAIM >> 16);
	cf.data[1] = (ISO_ADDRESS_CLAIM >>  8);
	cf.data[2] = (ISO_ADDRESS_CLAIM & 0xff);
	cf.can_dlc = 3;
	if (write(s, &cf, sizeof(cf)) <= 0) {
		err(1, "write ISO_REQUEST to socket");
	}
}

int
main(int argc, const char *argv[])
{
	struct ifreq ifr;
	struct sockaddr_can sa;
	struct can_frame cf;
	struct can_filter cfi;
	int r;

	if (argc != 2) {
		usage();
	}

	if ((s = socket(AF_CAN, SOCK_RAW, CAN_RAW)) < 0) {
		err(1, "CAN socket");
	}
	strncpy(ifr.ifr_name, argv[1], IFNAMSIZ );
	if (ioctl(s, SIOCGIFINDEX, &ifr) < 0) {
		err(1, "SIOCGIFINDEX for %s", argv[1]);
	}
	sa.can_family = AF_CAN;
	sa.can_ifindex = ifr.ifr_ifindex;
	if (bind(s, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
		err(1, "bind socket");
	}

	cfi.can_id = ((ISO_ADDRESS_CLAIM >> 8) << 16) | CAN_EFF_FLAG;
	cfi.can_mask = (0xff << 16) | CAN_EFF_FLAG;
        if (setsockopt(s,
	    SOL_CAN_RAW, CAN_RAW_FILTER, &cfi, sizeof(cfi)) < 0) {
                err(1, "setsockopt(CAN_RAW_FILTER)");
        }

	send_iso_request();

	while (1) {
		int n, class, function;
		r = read(s, &cf, sizeof(cf));
		if (r < 0) {
			err(1, "read from socket");
		}
		if (r == 0)
			continue;
		if (cf.can_dlc != 8)
			continue;

		printf("device at address %d: ", cf.can_id & 0xff);
		function = cf.data[5];
		class = cf.data[6] >> 1;
		for (n = 0; n2k_descs[n].desc != NULL; n++) {
			if (n2k_descs[n].class == class &&
			    n2k_descs[n].function == function)
				break;
		}
		if (n2k_descs[n].desc != NULL) {
			printf("%s\n", n2k_descs[n].desc);
		} else {
			printf("unknown class %d function %d\n",
			    class, function);
		}
		n = cf.data[0];
		n |= (cf.data[1] << 8);
		n |= (cf.data[2] & 0x1f) << 16;
		printf("   unique number: %d\n", n);
		n = (cf.data[2] >> 5);
		n |= (cf.data[3] << 3);
		printf("   manufacturer code: %d\n", n);
		printf("   device instance: %d\n", cf.data[4]);
		printf("   system instance: %d\n", (cf.data[7] & 0xf));
	}
	exit(0);
}
