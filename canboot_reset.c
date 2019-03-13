/* $Id: canboot_reset.c,v 1.2 2017/07/21 20:37:59 bouyer Exp $ */
/*
 * Copyright (c) 2017 Manuel Bouyer
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

int s;

static void
usage()
{
	fprintf(stderr, "usage: canboot_reset <interface> <addr>\n");
	exit(1);
}

static void
send_reset(int addr)
{
	struct can_frame cf;
	int i, j, r;
	uint16_t csum;

	cf.can_id =  (NMEA2000_PRIORITY_CONTROL << 26) | ((PRIVATE_REMOTE_CONTROL >> 8) << 16) | (addr << 8) | NMEA2000_ADDR_NULL | CAN_EFF_FLAG;
	cf.data[0] = CONTROL_RESET;
	cf.can_dlc = CONTROL_RESET_SIZE;
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
	int addr;

	if (argc != 3) {
		usage();
	}

	addr = strtol(argv[2], NULL, 0);
	if (addr >=NMEA2000_ADDR_MAX)
		errx(1, "bad address %s", argv[2]);

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

	send_reset(addr);
	exit(0);
}
