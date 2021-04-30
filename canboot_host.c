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
#include "canboot_defs.h"
#include "nmea2000_pgn.h"
#include "nmea2000_class.h"

static char sendbuf[CANBOOT_BLKLEN];
static int blkaddr, blksize;
static int firstblock;
static int s;
static int devid;

static void
usage()
{
	fprintf(stderr, "usage: canboot_host [-r] <interface> <id> <file>\n");
	exit(1);
}

static int
getint(char *linep)
{
	char charsv = linep[2];
	int ret;
	linep[2] = '\0';
	ret = strtol(linep, NULL, 16);
	linep[2] = charsv;
	return ret;
}

static void
sendtotarget()
{
	struct can_frame cf;
	int i, j, r;
	uint16_t csum;
again:
	cf.can_id = ((devid & 0xff) << 3) | PKP_BLKADDR;
	cf.data[0] = devid & 0xff;
	cf.data[1] = ((devid >> 8) & 0xff);
	cf.data[2] = (blkaddr & 0xff);
	cf.data[3] = ((blkaddr >> 8) & 0xff);
	cf.data[4] = ((blkaddr >> 16) & 0xff);
	cf.can_dlc = 5;
	if (write(s, &cf, sizeof(cf)) <= 0) {
		err(1, "write PKP_BLKADDR to socket");
	}

	csum = 0;
	for (i = 0; i < CANBOOT_BLKLEN; i += 8) {
		cf.can_id = ((devid & 0xff) << 3) | PKP_BLKDATA;
		for (j = 0; j < 8; j++) {
			cf.data[j] = sendbuf[i+j];
			csum += sendbuf[i+j];
		}
		cf.can_dlc = 8;
		if (write(s, &cf, sizeof(cf)) <= 0) {
			err(1, "write PKP_BLKDATA to socket");
		}
	}
	cf.can_id = ((devid & 0xff) << 3) | PKP_BLKEOB;
	cf.data[0] = csum & 0xff;
	cf.data[1] = csum >> 8;
	cf.can_dlc = 2;
	if (write(s, &cf, sizeof(cf)) <= 0) {
		err(1, "write PKP_BLKEOB to socket");
	}
	/* wait for ACK (or NACK) */
	while (1) {
		r = read(s, &cf, sizeof(cf));
		if (r < 0) {
			err(1, "read from socket");
		}
		if (r > 0) {
			if ((cf.can_id & 0x7) != PKT_SID)
				continue;

			if (cf.can_dlc == 1) {

				if (cf.data[0] == PKT_BLKACK) {
					printf("."); fflush(stdout);
					return;
				}
				if (cf.data[0] == PKT_BLKNACK) {
					printf("n"); fflush(stdout);
					goto again;
				}
			}
			if (firstblock &&
			    cf.can_dlc == 3 && cf.data[0] == PKT_HELO) {
				if (cf.data[1] == (devid & 0xff) &&
				    cf.data[2] == ((devid >> 8) & 0xff)) {
					printf("restart\n");
					goto again;
				}
			}
		}
	}
}


static void
wrbuf(uint8_t val)
{
	sendbuf[blksize++] = val;
	if (blksize == CANBOOT_BLKLEN) {
		sendtotarget();
		blkaddr+= CANBOOT_BLKLEN;
		blksize = 0;
		firstblock = 0;
	}
}

static void
readfile(FILE *f)
{
#define BLKBOOT_MASK (~(CANBOOT_BLKLEN-1))

	int lineno, rlen, rtype, raddr;
	u_int8_t val;
	u_int8_t rsum;
	static char line[1024];
	char *linep;
	int i;

	lineno = blkaddr = blksize = 0;

	while (fgets(line, 1020, f) != NULL) {
		lineno++;
		rsum = 0;
		linep = &line[0];
		if (*linep != ':') {
			errx(1,
			    "error at line %d: record not starting with :\n",
			    lineno);
		}
		linep++;
		rlen = getint(linep);
		rsum += rlen;
		linep += 2;
		raddr = getint(linep);
		rsum += raddr;
		linep += 2;
		raddr = raddr << 8;
		raddr |= getint(linep);
		rsum += (raddr & 0xff);
		linep += 2;
		rtype = getint(linep);
		rsum += rtype;
		linep += 2;

		switch(rtype) {
		case 00: /* data record */
			if ((raddr & BLKBOOT_MASK) != blkaddr) {
				/* new block: fill the current one and send */
				if (blksize > 0) {
					printf("fill1 0x%x -> 0x%x\n",
					    blkaddr + blksize,
					    blkaddr + CANBOOT_BLKLEN - 1);
					while (blksize > 0)
						wrbuf(0xff);
				}
				blkaddr = (raddr & BLKBOOT_MASK);
				blksize = 0;
			}
			if ((blkaddr + blksize) < raddr) {
				printf("fill2 0x%x -> 0x%x\n",
				    blkaddr + blksize, raddr);
				while (blkaddr + blksize < raddr)
					wrbuf(0xff);
			}
			for (i = 0; i < rlen; i++) {
				val = getint(linep);
				rsum += val;
				wrbuf(val);
				linep += 2;
			}
			break;
		case 01: /* end of file */
			val = getint(linep);
			if (((rsum + val) & 0xff) != 0) {
				errx(1, 
				    "invalid checksum (%d %d) line %d\n",
				    rsum, val, lineno);
			}
			/* finish current block */
			if (blksize > 0) {
				printf("fill3 0x%x -> 0x%x\n",
				    blkaddr + blksize,
				    blkaddr + CANBOOT_BLKLEN - 1);
				while (blksize > 0)
					wrbuf(0xff);
			}
			return;
		case 04: /* start linear address record */
			raddr = getint(linep);
			rsum += raddr;
			linep += 2;
			raddr = raddr << 8;
			raddr |= getint(linep);
			rsum += (raddr & 0xff);
			linep += 2;
			if (raddr != 0) {
				errx(1, 
				    "invalid address 0x%x line %d\n",
				    raddr, lineno);
			}
			break;
		default:
			errx(1,
			    "unsupported record type 0x%x line %d\n",
			    rtype, lineno);

		}
		val = getint(linep);
		if (((rsum + val) & 0xff) != 0) {
			errx(1, "invalid checksum (%d %d) line %d\n",
			    rsum, val, lineno);
		}
	}
	errx(1, "no EOF record");
}

static void
send_iso_request()
{   
	struct can_frame cf;
	int i, j, r;
	uint16_t csum;
	again:
	cf.can_id =  (NMEA2000_PRIORITY_CONTROL << 26) | ((ISO_REQUEST >> 8) <<
	16) | (NMEA2000_ADDR_GLOBAL << 8) | NMEA2000_ADDR_NULL | CAN_EFF_FLAG;
	cf.data[0] = (ISO_ADDRESS_CLAIM >> 16);
	cf.data[1] = (ISO_ADDRESS_CLAIM >>  8);
	cf.data[2] = (ISO_ADDRESS_CLAIM & 0xff);
	cf.can_dlc = 3;
	if (write(s, &cf, sizeof(cf)) <= 0) {
		err(1, "write ISO_REQUEST to socket");
	}
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


static void
find_and_reset(int r_devid)
{
	struct can_filter cfi;
	struct can_frame cf;
	int myid;
	int r;

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

		myid = cf.data[0];
		myid |= (cf.data[1] << 8);
		myid |= (cf.data[2] & 0x1f) << 16;
		if (myid != r_devid)
			continue;

		printf("found device at address %d: ", cf.can_id & 0xff);
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
		n = (cf.data[2] >> 5);
		n |= (cf.data[3] << 3);
		printf("   manufacturer code: %d\n", n);
		printf("   device instance: %d\n", cf.data[4]);
		printf("   system instance: %d\n", (cf.data[7] & 0xf));
		send_reset(cf.can_id & 0xff);
		return;
	}
}

int
main(int argc, char * const argv[])
{
	FILE *f;
	struct ifreq ifr;
	struct sockaddr_can sa;
	struct can_frame cf;
	struct can_filter cfi;
	int r;
	int rflag = 0;
	extern char *optarg;
	extern int optind;
	int ch;

	while ((ch = getopt(argc, argv, "r")) != -1) {
		switch(ch) {
		case 'r':
			rflag++;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;
		
	if (argc != 3) {
		usage();
	}
	devid = strtol(argv[1], NULL, 0);

	f = fopen(argv[2], "r");
	if (f == NULL) {
		err(1, "open %s", argv[2]);
	}

	if ((s = socket(AF_CAN, SOCK_RAW, CAN_RAW)) < 0) {
		err(1, "CAN socket");
	}
	strncpy(ifr.ifr_name, argv[0], IFNAMSIZ );
	if (ioctl(s, SIOCGIFINDEX, &ifr) < 0) {
		err(1, "SIOCGIFINDEX for %s", argv[0]);
	}
	sa.can_family = AF_CAN;
	sa.can_ifindex = ifr.ifr_ifindex;
	if (bind(s, (struct sockaddr *)&sa, sizeof(sa)) < 0) {
		err(1, "bind socket");
	}

	if (rflag) {
		find_and_reset(devid);
	}

	cfi.can_id = ((devid & 0xff) << 3);
	cfi.can_mask = (0xff << 3) | CAN_EFF_FLAG;
        if (setsockopt(s,
	    SOL_CAN_RAW, CAN_RAW_FILTER, &cfi, sizeof(cfi)) < 0) {
                err(1, "setsockopt(CAN_RAW_FILTER)");
        }

	while (1) {
		r = read(s, &cf, sizeof(cf));
		if (r < 0) {
			err(1, "read from socket");
		}
		if (r > 0) {
			if ((cf.can_id & 0x7) != PKT_SID)
				continue;
			if (cf.can_dlc != 3)
				continue;
			if (cf.data[0] != PKT_HELO)
				continue;

			if (cf.data[1] == (devid & 0xff) &&
			    cf.data[2] == ((devid >> 8) & 0xff))
				break;
		}
	}
	printf("programming start\n");
	firstblock = 1;

	readfile(f);
	cf.can_id = ((devid & 0xff) << 3) | PKP_EOF;
	cf.can_dlc = 0;
	if (write(s, &cf, sizeof(cf)) <= 0) {
		err(1, "write to socket");
	}
	printf("programming done\n");
	exit(0);
}
