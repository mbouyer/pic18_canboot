; Copyright (c) 2017, Manuel Bouyer
; All rights reserved.
; 
;  Redistribution and use in source and binary forms, with or without
;  modification, are permitted provided that the following conditions
;  are met:
;  1. Redistributions of source code must retain the above copyright
;     notice, this list of conditions and the following disclaimer.
;  2. Redistributions in binary form must reproduce the above copyright
;     notice, this list of conditions and the following disclaimer in the
;     documentation and/or other materials provided with the distribution.
; 
;  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
;  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
;  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
;  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
;  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
;  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
;  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
; 
;

LIST   P=PIC18F26K80
#include <p18f26k80.inc> 
errorlevel -302

	RADIX dec;

	CBLOCK 0x00C            ; start vars
	devidl	: 1	;
	devidh	: 1	;
	tmp	: 1	;
	cmpt1	: 1	;
	cmpt2	: 1	;
	blkaddru : 1	;
	blkaddrh : 1	;
	blkaddrl : 1	;
	crch	: 1;
	crcl	: 1;
	ENDC                    ; end of vars

; flash-related defines
OFFSET	EQU 0x200
IFDEF DEBUG
UOFFSET	EQU 0x500
ELSE
UOFFSET	EQU 0x400
ENDIF
WRBLK	EQU 8

DEVIDP	EQU 0x200000

; device-related defines
CLOCKHZ EQU 10
MTXIF   EQU     TX2IF
MRCIF   EQU     RC2IF
MPIR    EQU     PIR3
MTXREG  EQU     TXREG2
MRCREG  EQU     RCREG2
MRCSTA  EQU     RCSTA2
MTXSTA  EQU     TXSTA2
MSPBRG  EQU     SPBRG2

; protocol defines - has to match the programmer
PKT_SID		EQU	0
PKT_HELO	EQU	0
PKT_BLKACK      EQU	1
PKT_BLKNACK     EQU	2

PKP_BLKADDR     EQU	1
PKP_BLKDATA     EQU	2
PKP_BLKEOB      EQU	3
PKP_EOF         EQU	4

print	macro str
IFDEF DEBUG
	movlw LOW str
	rcall txstr
ENDIF
	endm

printcr	macro str
IFDEF DEBUG
	movlw LOW str
	rcall txstrcrlf
ENDIF
	endm

	ORG OFFSET
	nop;
	bra start
crlfstr DA "\r\n\0"; ! only 4 bytes available
	ORG OFFSET + 0x0008 ; interrupt vector;
	bra 	UOFFSET + 0x08 ;
	ORG OFFSET + 0x0018;
	bra 	UOFFSET + 0x18; low priority interrupt vector

IFDEF DEBUG
;strings has to be low in memory, because we set TBLPTRU and TBLPTRH to a
; fixed value
bootstr DA "canboot 0.1 0x\0";
startstr	DA "start\0";
pktstr	DA "pkt \0";
endstr	DA "write done\0";
ENDIF

start
	clrf INTCON, a;
; assume oscillator and serial ports are already set up

	; setup CAN
	movlw	0x80
	movwf	CANCON, a
wconf:
	movlw	0xe0
	andwf	CANSTAT, w, a
	xorlw	0x80
	bnz	wconf

	; switch to mode 2
	movlw	0x80
	movwf	ECANCON, a

; get the device ID, use as the filter mask
	movlw	UPPER DEVIDP
	movwf	TBLPTRU, a
	movlw	HIGH DEVIDP
	movwf	TBLPTRH, a
	movlw	LOW DEVIDP + 1
	movwf	TBLPTRL, a
	tblrd*-;
	movf	TABLAT, w;
	movwf	devidh, a
	tblrd*;
	movf	TABLAT, w;
	movwf	devidl, a
	banksel	RXF0SIDH
	movwf	RXF0SIDH, b
	clrf	RXF0SIDL, b
	setf	RXM0SIDH, b
	movlw	(1 << EXIDEN)
	movwf	RXM0SIDL, b
	; associate filters and mask
	clrf	MSEL0, b
	; All TX/RX buffers are for receive
	clrf	BSEL0, b
	; all filters associated with RXB0
	clrf	RXFBCON0, b
	; enable filter 0
	movlw	0x1
	movwf	RXFCON0, b
	clrf	RXFCON1
	; setup for 250Kbs
	banksel	BRGCON1
	movlw	0x41
	movwf	BRGCON1, b
	movlw	0x92
	movwf	BRGCON2, b
	movlw	0x82
	movwf	BRGCON3, b
	movlw	0x21
	movwf	CIOCON, a
	; setup receive buffers
	clrf	RXB0CON, a
	clrf	RXB1CON, a
	banksel	B0CON
	clrf	B0CON, b
	clrf	B1CON, b
	clrf	B2CON, b
	clrf	B3CON, b
	clrf	B4CON, b
	clrf	B5CON, b
	; setup transmit buffers
	banksel	TXB0CON
	clrf	TXB0CON, b
	clrf	TXB1CON, b
	clrf	TXB2CON, b
	; switch to normal mode
	clrf	CANCON, a
wnorm:
	movlw	0xe0
	andwf	CANSTAT, w, a
	bnz	wnorm

IFDEF DEBUG
	; print version string
	print bootstr;

	swapf devidh, w
	rcall printhex
	movf  devidh, w
	rcall printhex
	swapf devidl, w
	rcall printhex
	movf  devidl, w
	rcall printhex
	rcall crlf
ENDIF

	; send the HELO packet, 2 tries
	movlw	0x3
	movwf	cmpt1
tryagain:
	decf	cmpt1, f
	bnz	hello;
	bra 	UOFFSET

doend:
IFDEF DEBUG
	rcall crlf
	rcall crlf
ENDIF
	reset
hello:
	movlw	PKT_HELO
	rcall	sendpacket
	; TXB0CON already selected
b2:
	btfsc	TXB0CON, TXREQ, b
	bra 	b2

waitaddr:
	rcall	waitrxtout1s
	bz	tryagain
	movf	RXB0SIDL, w, a
	xorlw	(PKP_BLKADDR << 5)
	bnz	doend

	movf	RXB0DLC, w, a
	xorlw	0x5
	bnz	doend	; bad len, ignore
	clrf	FSR0H, a
	movlw	0x80;
	movwf	FSR0L, a; receive 128 bytes: stop when fsr0 == 0x100;
	clrf	crch, a;
	clrf	crcl, a;
	movf	RXB0D2, w, a
	movwf	blkaddrl
	andlw	(WRBLK - 1)
	bnz	doend; bad alignement, ignore
	movff	RXB0D3, blkaddrh
	movf	RXB0D4, w, a
	movwf	blkaddru, a
	bnz	addrok
	movlw	HIGH UOFFSET
	cpfslt	blkaddrh, a ; ignore if too low
	bra addrok;
	bra doend;
addrok:
	clrf  RXB0CON, a

rxdata:
	rcall	waitrxtout1s
	bz	doend
	movf	RXB0SIDL, w, a
	xorlw	(PKP_BLKDATA << 5)
	bnz	doend
	movf	RXB0DLC, w, a
	movwf	tmp
	xorlw	0x8
	bnz	doend	; bad len, ignore
	movlw	LOW RXB0D0
	movwf	FSR1L, a
	movlw	HIGH RXB0D0
	movwf	FSR1H, a
rdloop
	movf	POSTINC1, w, a
	movwf	POSTINC0, a
	addwf	crcl, f, a
	movlw	0
	addwfc	crch, f, a
	decfsz	tmp, f, a
	bra rdloop
	clrf  RXB0CON, a
	btfss	FSR0H, 0, a
	bra	rxdata

rxeob
	rcall	waitrxtout1s
	bz	doend
	movf	RXB0SIDL, w, a
	xorlw	(PKP_BLKEOB << 5)
	bnz	doend
	movf	RXB0DLC, w, a
	xorlw	0x2
	bnz	doend	; bad len, ignore

	movf	crcl, w, a
	xorwf	RXB0D0, w, a
	bnz	badcrc
	movf	crch, w, a
	xorwf	RXB0D1, w, a
	bnz	badcrc
	clrf	RXB0CON, a
IFDEF DEBUG
	print	pktstr
	movf	blkaddru, w, a
	rcall	printhex
	swapf	blkaddrh, w, a
	rcall	printhex
	movf	blkaddrh, w, a
	rcall	printhex
	swapf	blkaddrl, w, a
	rcall	printhex
	movf	blkaddrl, w, a
	rcall	printhex
	rcall	crlf
ENDIF
	; write the block to flash
	clrf FSR0H;
	movlw 0x80;
	movwf FSR0L; write 128 bytes: stop when fsr0 == 0x100;
	movff	blkaddru, TBLPTRU
	movff	blkaddrh, TBLPTRH
	movff	blkaddrl, TBLPTRL
wrerloop:
IFDEF __18F27J53
	movf  TBLPTRL, w
	bnz noerase
	movf  TBLPTRH, w
	andlw 0x3
	bnz noerase
ENDIF	__18F27J53
	movlw b'10010100'
	movwf EECON1; point to flash, access flash, enable write, enable erase
	rcall dowrite
noerase
	movlw 64 / WRBLK
	movwf cmpt1; 8 boucle de 8 ecritures -> 64 bytes
wrloop
	movlw WRBLK
	movwf cmpt2; 
wrblkloop;
	movff POSTINC0, TABLAT;
	tblwt*+;
	decfsz cmpt2, f;
	bra wrblkloop;
	tblrd*-; point back into block
	movlw b'10000100'
	movwf EECON1; point to flash, access flash, enable write
	rcall dowrite
	tblrd*+;
	decfsz cmpt1, f;
	bra wrloop;
	btfss FSR0H, 0;
	bra wrerloop;
	bcf EECON1, WREN; disable write
	movlw	PKT_BLKACK
	rcall	sendpacket
	bra	waitaddr;
badcrc
	clrf	RXB0CON, a
	movlw	PKT_BLKNACK
	rcall	sendpacket
	bra	waitaddr;

dowrite
	movlw 0x55;
	movwf EECON2;
	movlw 0xAA;
	movwf EECON2;
	bsf EECON1, WR; start write;
	nop
	return;
	; send a control packet; code is in W
sendpacket:
	banksel TXB0CON;
	btfsc	TXB0CON, TXREQ, b
	bra 	sendpacket;
	banksel	TXB0SIDL
	movwf	TXB0D0, b
	clrf	TXB0SIDL, b
	movff	devidl, TXB0SIDH
	clrf	TXB0DLC, b
	incf	TXB0DLC, f, b ; assume DLC=1
	movf	TXB0D0, f, b ; test for 0
	bnz	nothelo
	movff	devidl, TXB0D1
	movff	devidh, TXB0D2
	incf	TXB0DLC, f, b ; 
	incf	TXB0DLC, f, b ; DLC=3
nothelo:
	movlw	(1 << TXREQ)
	movwf	TXB0CON, b
	return

waitrxtout1s
	movlw 5 * CLOCKHZ / 10; 1s timeout
waitrxtout; wait for a frame, with timeout (w / 5) seconds
	movwf cmpt2, a;
	; setup timer1
	movlw 0x30;
	movwf T1CON, a; 1:8 prescale, 8bit mode, internal clock, timer stopped
	movlw 0x0c;
	movwf TMR1H, a; period=62464. At 10Mhz clock, fout=5hz
	clrf TMR1L, a
	bsf T1CON, TMR1ON, a; start timer
; entry point for waiting for a frame without timeout (assume timer1 stopped)
waitrx
	bcf PIR1, TMR1IF, a; clear overflow
waitrxloop
	btfsc COMSTAT, NOT_FIFOEMPTY, a; did we receive a frame ? 
	bra gotframe       ; yes.      
	btfss PIR1, TMR1IF, a; did timer1 overflow ?
	bra waitrxloop     ; no       
	decfsz  cmpt2, f, a   ; yes, decrease cmpt2
	bra    waitrx      ; not yet 0, loop
rxret
	bcf T1CON, TMR1ON, a; stop timer;
	movf cmpt2, f, a; bz after rcall to test for timeout.
	return;
gotframe
	; map receive buffer in access bank
	movf	ECANCON, w, a
	andlw	0xe0;
	; in normal mode, no abort pending, all but the buffer bits are 0
	iorwf	CANCON, w, a
	iorlw	0x10
	movwf	ECANCON, a
	bra	rxret

IFDEF DEBUG
txstrcrlf
	rcall txstr
crlf
	movlw LOW crlfstr;
txstr
	movwf TBLPTRL, a;
	clrf TBLPTRU, a;
	movlw	HIGH OFFSET
	movwf TBLPTRH, a;
txstrloop
	tblrd*+;
	movf TABLAT, w;
	bz doreturn;
	rcall dotx;
	bra txstrloop;
printhex
	andlw 0x0f;
	sublw 9;
	bc decimal;
	sublw '@';
	bra dotx;
decimal 
	sublw '9';
	; bra dotx

dotx
	btfss MPIR, MTXIF, a;
	bra dotx;
	movwf MTXREG, a;
doreturn
	return;
ENDIF

	END
