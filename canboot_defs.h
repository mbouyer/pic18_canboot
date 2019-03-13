/* $Id: canboot_defs.h,v 1.5 2017/07/21 20:37:59 bouyer Exp $ */
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

/*
 * packet type, in the 3 lower bits of the SID. The 8 upper bits are the low
 * bits of the device unique number.
 * due to what appears to be a bug in the pic18 CAN controller,
 * packets from the PIC18 have to have the 3 lower bits set to 0.
 * For the pic->host packets, the type is the first data byte.
 */

#define CANBOOT_BLKLEN 	128

/* pic to host */
#define PKT_SID		0
/*
 * sent by the target when it's ready.
 * Data: the full 16bits device unique number
 */
#define PKT_HELO	0
/*
 * sent by the target to programmer to ack a block
 */
#define PKT_BLKACK	1
/*
 * sent by the target to programmer to nack a block
 */
#define PKT_BLKNACK	2


/* host to pic. */
/*
 * sent by the programmer to target to start writing a block of 128 bytes
 * data: 24 bits address of block
 */
#define PKP_BLKADDR	1
/*
 * sent by the programmer to target to with 8 data bytes
 */
#define PKP_BLKDATA	2
/*
 * sent by the programmer to target at end of block
 * data: 16bit CRC
 */
#define PKP_BLKEOB	3
/*
 * sent by the programmer to target to end tramsission
 */
#define PKP_EOF		4
