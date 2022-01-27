; Copyright (c) 2022, Manuel Bouyer
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

#include <xc.inc>

PSECT udata_acs                 ; start vars
devidl:
	DS 1	;
devidh:
	DS 1	;
tmp:
	DS 1	;
cmpt1:
	DS 1	;
cmpt2:
	DS 1	;
blkaddru:
	DS 1	;
blkaddrh:
	DS 1	;
blkaddrl:
	DS 1	;
crch:
	DS 1;
crcl:
	DS 1;
bsrsave:
	DS 1;

; flash-related defines
OFFSET	EQU 0x300
#ifdef DEBUG
UOFFSET	EQU 0x700
#else
UOFFSET	EQU 0x600
#endif

XBLK	EQU 128 ; size of a xmodem (over canbus) block

#ifdef __18F27Q84
WRBLK   EQU 256
NVMRAMBANK EQU 55
CANRAMBANK EQU 56
#else
	ERROR "unknown pic"
#endif
WRBLKMSK EQU (WRBLK - 1)

CANTX_SIDL EQU (CANRAMBANK * 256) + 0
CANTX_SIDH EQU (CANRAMBANK * 256) + 1
CANTX_DLC  EQU (CANRAMBANK * 256) + 4
CANTX_DATA EQU (CANRAMBANK * 256) + 8

CANRX_OSIDL EQU 0
CANRX_OSIDH EQU 1
CANRX_ODLC  EQU 4
CANRX_ODATA EQU 8

DEVIDP	EQU 0x200000

; device-related defines
CLOCKHZ EQU 10

#ifdef DEBUG
UxBRGL  EQU     U1BRGL
UxCON0  EQU     U1CON0
UxCON1  EQU     U1CON1
UxCON2  EQU     U1CON2
UxRXB   EQU     U1RXB
UxTXB   EQU     U1TXB
UxFIFO  EQU     U1FIFO
#endif

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
#ifdef DEBUG
	movlw LOW str
	rcall txstr
#endif
	endm

printcr	macro str
#ifdef DEBUG
	movlw LOW str
	rcall txstrcrlf
#endif
	endm

printc	macro char
#ifdef DEBUG
	movlw char
	rcall dotx
#endif
	endm

PSECT resetVec,class=CODE,reloc=2
	goto start
crlfstr: ; ! only 4 bytes available
	DB 10, 13, 0

PSECT ivth,class=CODE,reloc=2
	goto 	UOFFSET + 0x08 ;

PSECT ivtl,class=CODE,reloc=2
	goto 	UOFFSET + 0x18; low priority interrupt vector

PSECT code
#ifdef DEBUG
;strings has to be low in memory, because we set TBLPTRU and TBLPTRH to a
; fixed value
bootstr:
	IRPC char,canboot 0.1 0x
	    DB 'char'
	ENDM
	DB 0
txq:
	IRPC char,txq
	    DB 'char'
	ENDM
	DB 0
rxq:
	IRPC char,rxq
	    DB 'char'
	ENDM
	DB 0
startstr:
	IRPC char,start
	    DB 'char'
	ENDM
	DB 0
pktstr:
	IRPC char,pkt 
	    DB 'char'
	ENDM
	DB ' '
	DB 0
endstr:
	IRPC char,write done
	    DB 'char'
	ENDM
	DB 0
hellostr:
	IRPC char,hello
	    DB 'char'
	ENDM
	DB 0
#endif

#define UPPER(x) (((x) >> 16) & 0xff)

ALIGN 2
start:
	clrf INTCON0, a;
; assume oscillator and serial ports are already set up

	; setup CAN
	banksel ANSELB
	clrf    ANSELB, b
	; canRX on RB3, this is the default
	; movlw 00001011B
	; movwf CANRXPPS
	; canTX on RB2
	bsf LATB, 2, a;  output value when idle
	bcf TRISB, 2, a;
	banksel RB2PPS
	movlw	0x46
	movwf	RB2PPS, b
	banksel C1CONT
	movlw	0x80
	movwf	C1CONH, b ; enable CAN
	movlw	0x04
	movwf	C1CONT, b ; config mode
wconf:
	movlw	0xe0
	andwf	C1CONU, w, b
	xorlw	0x80
	bnz	wconf

	movlw	0x10
	movwf	C1CONU, b; TXQ en, STEF disable
	movlw	0x90
	movwf	C1CONH, b ; enable CAN, BRSDIS
	movlw	0x40
	movwf	C1CONL, b ; PXEDIS
	; setup FIFOs
	clrf C1FIFOBAT, b
	clrf C1FIFOBAU, b
	movlw CANRAMBANK
	movwf C1FIFOBAH, b
	clrf C1FIFOBAL, b
	; transmit queue register
	; C1TXQCONT = 0		8 data bytes, 1 message: this is the default
	; C1TXQCONU = 0x60 	unlimited retrans, pri 0
	; C1TXQCONH		nothing to do yet
	; C1TXQCONL = 0x80 	configured as TX
	; FIFO 0 (receive)
	movlw 18
	movwf C1FIFOCON1T, b ; 8 data bytes, 18 messages
	; C1FIFOCON1T = 0	
	; C1FIFOCON1U		nothing to do
	; C1FIFOCON1H		nothing to do yet
	; C1FIFOCON1L = 0	configured as RX

; get the device ID, use as the filter mask
	movlw	UPPER(DEVIDP)
	movwf	TBLPTRU, a
	movlw	HIGH DEVIDP
	movwf	TBLPTRH, a
	movlw	LOW DEVIDP + 1
	movwf	TBLPTRL, a
	tblrd*-;
	movf	TABLAT, a, w;
	movwf	BANKMASK(devidh), a
	tblrd*;
	movf	TABLAT, a, w;
	movwf	BANKMASK(devidl), a
	clrf	BANKMASK(tmp), a
	clrf	STATUS, a
	rlcf	WREG, a, w
	rlcf	BANKMASK(tmp), a, f
	rlcf	WREG, a, w
	rlcf	BANKMASK(tmp), a, f
	rlcf	WREG, a, w
	rlcf	BANKMASK(tmp), a, f
	movwf	C1FLTOBJ0L, b
	movf	BANKMASK(tmp), a, w
	movwf	C1FLTOBJ0H, b
	clrf	C1FLTOBJ0T, b
	movlw	0x40
	movwf	C1MASK0T, b
	clrf	C1MASK0U, b
	movlw	0x07
	movwf	C1MASK0H, b
	movlw	0xf8
	movwf	C1MASK0L, b
	; enable filter 0
	movlw	0x81
	movwf	C1FLTCON0L, b
	; setup for 250Kbs
	clrf	C1NBTCFGT, b; Tq = 1 / 10Mhz
	movlw	26
	movwf	C1NBTCFGU, b; Tseg1 = 27 Tq
	movlw	11
	movwf	C1NBTCFGH, b; Tseg2 = 12 Tq
	movlw	10
	movwf	C1NBTCFGL, b; Swj = 11 Tq
	;clrf 	C1TDCU, b ; disable TDCMOD
	; switch CAN mode 2
	movlw	0x06
	movwf	C1CONT, b

wnorm:
	movlw	0xe0
	andwf	C1CONU, w, b
	xorlw	0xc0
	bnz	wnorm

#ifdef DEBUG
	; print version string
	print bootstr;

	movf  BANKMASK(devidh), w, a
	rcall printhex
	movf  BANKMASK(devidl), w, a
	rcall printhex
	rcall crlf

	print txq
	movf	C1TXQUAH, b, w
	rcall printhex
	movf	C1TXQUAL, b, w
	rcall printhex
	rcall crlf

	print rxq
	movf	C1FIFOUA1H, b, w
	rcall printhex
	movf	C1FIFOUA1L, b, w
	rcall printhex
	rcall crlf
#endif

#ifdef TESTBATT
	; special for my test PAC1953 board
	banksel ANSELC
	clrf	ANSELC, b
	bcf	LATC, 2, a
	bcf	TRISC, 2, a
#endif

	banksel NVMADRU
	clrf	NVMADRU, b
	clrf	NVMADRH, b
	; send the HELO packet, 2 tries
	movlw	0x3
	movwf	BANKMASK(cmpt1), a
tryagain:
	decf	BANKMASK(cmpt1), f, a
	bnz	hello;
	movlw	0x04
	movwf	C1CONT, b ; back to config mode
exitconf:
	movlw	0xe0
	andwf	C1CONU, w, b
	xorlw	0x80
	bnz	exitconf
	goto 	UOFFSET

doend:
	printc	'g'
	rcall	newblk; write last block if needed
	printc	'o'
#ifdef DEBUG
	rcall crlf
	rcall crlf
#endif
	reset
hello:
	print hellostr
	banksel C1TXQCONH;
	bcf	C1TXQCONH, C1TXQCONH_TXREQ_POSN, b ; abort transmit, in case one is pending
	movlw	PKT_HELO
	rcall	sendpacket
	; C1TXQCONH already selected
#ifdef WAIT_CAN
b2:
#ifdef DEBUG
	movlw	HIGH C1BDIAG1T
	movwf	FSR0H, a
	movlw	LOW C1BDIAG1T
	movwf	FSR0L, a
	rcall printhex32
	movlw	' '
	rcall dotx
	rcall printhex32
	movlw	' '
	rcall dotx
	rcall printhex32
	movlw	' '
	rcall dotx
	movlw	HIGH C1INTT
	movwf	FSR0H, a
	movlw	LOW C1INTT
	movwf	FSR0L, a
	rcall printhex32
	rcall crlf
	banksel C1TXQCONH
#endif /* DEBUG */
	btfsc	TXREQ0
	bra 	b2
#endif /* WAIT_CAN */
waitaddr:
	rcall	waitrxtout1s
	bz	tryagain
#ifdef DEBUG
	movlw	'1'
	rcall printrxbuf
	rcall crlf
#endif
	movff	C1FIFOUA1H, FSR0H
	movff	C1FIFOUA1L, FSR0L
	; movlw CANRX_OSIDL CANRX_OSIDL is 0
	movf	INDF0, w, a 
	andlw	0x07
	xorlw	PKP_BLKADDR
	bnz	doend

	movlw	CANRX_ODLC
	movf	PLUSW0, w, a
	xorlw	0x5
	bnz	doend	; bad len, ignore
	printc 'b'
	movlw	0x6
	movwf	FSR1H, a
	movlw	0x80;
	movwf	FSR1L, a; receive 128 bytes: stop when fsr1 == 0x100;
	clrf	BANKMASK(crch), a;
	clrf	BANKMASK(crcl), a;
	movlw	CANRX_ODATA+2
	movf	PLUSW0, w, a
	movwf	BANKMASK(blkaddrl), a
	andlw	(XBLK - 1)
	bnz	doend; bad alignement, ignore
	printc 'c'
	movlw	CANRX_ODATA+3
	movf	PLUSW0, w, a
	movwf	BANKMASK(blkaddrh), a
	movlw	CANRX_ODATA+4
	movf	PLUSW0, w, a
	movwf	BANKMASK(blkaddru), a
	bnz	addrok
	movlw	HIGH UOFFSET
	cpfslt	BANKMASK(blkaddrh), a ; ignore if too low
	bra addrok;
	printc 'e'
	bra doend;
addrok:
	bsf	C1FIFOCON1H, C1FIFOCON1H_UINC_POSN, b

rxdata:
	printc 'f'
	rcall	waitrxtout1s
	bz	doend
#ifdef DEBUG
	movlw	'2'
	rcall printrxbuf
	rcall crlf
#endif
	movff	C1FIFOUA1H, FSR0H
	movff	C1FIFOUA1L, FSR0L
	; movlw CANRX_OSIDL CANRX_OSIDL is 0
	movf	INDF0, w, a 
	andlw	0x7
	xorlw	PKP_BLKDATA
	bnz	doend
	movlw	CANRX_ODLC
	movf	PLUSW0, w, a
	movwf	BANKMASK(tmp), a
	xorlw	0x8
	bnz	doend	; bad len, ignore
	movlw	CANRX_ODATA
	addwf	FSR0L, f, a; all fifo in the same page, now FSR0 points to data
rdloop:
	movf	POSTINC0, w, a
	movwf	POSTINC1, a
	addwf	BANKMASK(crcl), f, a
	movlw	0
	addwfc	BANKMASK(crch), f, a
	decfsz	BANKMASK(tmp), f, a
	bra rdloop
	bsf	C1FIFOCON1H, C1FIFOCON1H_UINC_POSN, b
	tstfsz	FSR1L, a
	bra	rxdata

rxeob:
	rcall	waitrxtout1s
	bz	doend
#ifdef DEBUG
	movlw	'3'
	rcall printrxbuf
	rcall crlf
#endif
	movff	C1FIFOUA1H, FSR0H
	movff	C1FIFOUA1L, FSR0L
	; movlw CANRX_OSIDL CANRX_OSIDL is 0
	movf	INDF0, w, a 
	andlw	0x07
	xorlw	PKP_BLKEOB
	bnz	doend
	movlw	CANRX_ODLC
	movf	PLUSW0, w, a
	xorlw	0x2
	bnz	doend	; bad len, ignore

	movlw	CANRX_ODATA+0
	movf	PLUSW0, w, a
	xorwf	BANKMASK(crcl), w, a
	bnz	badcrc
	movlw	CANRX_ODATA+1
	movf	PLUSW0, w, a
	xorwf	BANKMASK(crch), w, a
	bnz	badcrc
	bsf	C1FIFOCON1H, C1FIFOCON1H_UINC_POSN, b
#ifdef DEBUG
	print	pktstr
	movf	BANKMASK(blkaddru), w, a
	rcall	printhex
	movf	BANKMASK(blkaddrh), w, a
	rcall	printhex
	movf	BANKMASK(blkaddrl), w, a
	rcall	printhex
	rcall	crlf
#endif
	; write the block to flash
	movlw 0x06
	movwf FSR0H, a;
	movlw 0x80;
	movwf FSR0L, a; write 128 bytes: stop when fsr0 == 0x700;
	; check if we are in the same flash sector
	banksel NVMADRU
	movf	NVMADRU, b, w
	cpfseq	BANKMASK(blkaddru), a
	rcall newblk
	movf	NVMADRH, b, w
	cpfseq	BANKMASK(blkaddrh), a
	rcall newblk
	movff	blkaddrl, FSR1L
	movlw 	NVMRAMBANK
	movwf	FSR1H, a
wrerloop:
	movf	POSTINC0, w, a
	movwf	POSTINC1, a
	tstfsz	FSR0L, a
	bra wrerloop
	movlw	PKT_BLKACK
	rcall	sendpacket
	bra	waitaddr;
badcrc:
	bsf	C1FIFOCON1H, C1FIFOCON1H_UINC_POSN, b
	movlw	PKT_BLKNACK
	rcall	sendpacket
	bra	waitaddr;

newblk:
	banksel NVMADRU
#ifdef DEBUG
	printc 'n'
	movf	NVMADRU, b, w
	rcall printhex
	movf	NVMADRH, b, w
	rcall printhex
	printc ' '
#endif
	movf	NVMADRU, b, f
	bnz	dowrite
	movf	NVMADRH, b, f
	bz	nowrite
dowrite:
	printc 'e'
	;  write current block
	movlw 0x06 ; page erase
	movwf NVMCON1, b
	rcall unlocknvm
	printc 'w'
	movlw 0x05 ; write page
	movwf NVMCON1, b
	rcall unlocknvm
nowrite:
#ifdef DEBUG
	rcall crlf
#endif
	; point to and read next block (for partial writes)
	movff	blkaddrh, NVMADRH
	movff	blkaddru, NVMADRU
	clrf	NVMADRL, b
	movlw	0x2; read page
	movwf NVMCON1, b
	bra gonvm

unlocknvm:
	; assumes banksel is correct
	movlw 0x55 
	movwf NVMLOCK, b
	movlw 0xaa
	movwf NVMLOCK, b
gonvm:
	bsf NVMCON0, 0, b;  set go
	btfsc NVMCON0, 0, b;
	bra $ - 2;
	return;


	; send a control packet; code is in W
sendpacket:
	banksel C1TXQCONH;
	btfsc	TXREQ0
	bra 	sendpacket;
	banksel	CANTX_DATA
	movwf	CANTX_DATA, b
	movff	C1FLTOBJ0H, CANTX_SIDH
	movff	C1FLTOBJ0L, CANTX_SIDL
	clrf	CANTX_DLC, b
	incf	CANTX_DLC, f, b ; assume DLC=1
	clrf	CANTX_SIDL + 2, b
	clrf	CANTX_SIDL + 3, b
	clrf	CANTX_SIDL + 5, b
	clrf	CANTX_SIDL + 6, b
	clrf	CANTX_SIDL + 7, b
	movf	CANTX_DATA, f, b; test for 0
	bnz	nothelo
	movff	devidl, CANTX_DATA + 1
	movff	devidh, CANTX_DATA + 2
	incf	CANTX_DLC, f, b ; 
	incf	CANTX_DLC, f, b ; DLC=3
nothelo:
	banksel C1TXQCONH;
	movlw	0x3
	movwf	C1TXQCONH, b
	return

waitrxtout1s:
	movlw 5 * CLOCKHZ / 10; 1s timeout
waitrxtout:; wait for a frame, with timeout (w / 5) seconds
	movwf BANKMASK(cmpt2), a;
	; setup timer1
	banksel T1CON
	movlw 0x30;
	movwf T1CON, b; 1:8 prescale, 8bit mode, internal clock, timer stopped
	movlw 0x1
	movwf T1CLK, b; Fosc / 4
	movlw 0x0c;
	movwf TMR1H, b; period=62464. At 10Mhz clock, fout=5hz
	clrf TMR1L, b
	bsf TMR1ON; start timer
; entry point for waiting for a frame without timeout (assume timer1 stopped)
waitrx:
	bcf TMR1IF; clear overflow
waitrxloop:
	banksel C1FIFOSTA1L
	btfsc C1FIFOSTA1L, C1FIFOSTA1L_TFNRFNIF_POSN, b; did we receive a frame ? 
	bra rxret       ; yes.      
	btfss TMR1IF    ; did timer1 overflow ?
	bra waitrxloop  ; no       
	decfsz  BANKMASK(cmpt2), f, a   ; yes, decrease cmpt2
	bra    waitrx      ; not yet 0, loop
rxret:
	banksel T1CON
	bcf TMR1ON; stop timer;
	banksel C1FIFOSTA1L; back to CAN registers
	movf BANKMASK(cmpt2), f, a; bz after rcall to test for timeout.
	return;

#ifdef DEBUG
txstrcrlf:
	rcall txstr
crlf:
	movlw LOW crlfstr;
txstr:
	movwf TBLPTRL, a;
	clrf TBLPTRU, a;
	movlw	HIGH OFFSET
	movwf TBLPTRH, a;
txstrloop:
	tblrd*+;
	movf TABLAT, a, w;
	bz doreturn;
	rcall dotx;
	bra txstrloop;
printrxbuf:
	rcall dotx
	printc	' '
	movff   C1FIFOUA1H, FSR0H
	movff   C1FIFOUA1L, FSR0L
	movlw 	16
	movwf	BANKMASK(cmpt2), a
	movf	FSR0H, w, a
	rcall printhex
	movf	FSR0L, w, a
	rcall printhex
	printc ' '
printrxbufloop:
	movf	POSTINC0, a, w
	rcall printhex
	printc	' '
	decfsz	BANKMASK(cmpt2), a
	bra printrxbufloop
	return
printhex32:
	movf	FSR0H, w, a
	rcall printhex
	movf	FSR0L, w, a
	rcall printhex
	movlw ' '
	rcall dotx
	movf	POSTDEC0, w, a
	rcall printhex
	movf	POSTDEC0, w, a
	rcall printhex
	movf	POSTDEC0, w, a
	rcall printhex
	movf	POSTDEC0, w, a
printhex:
	movwf BANKMASK(tmp), a
	swapf BANKMASK(tmp), w, a
	rcall printhex1
	movf  BANKMASK(tmp), w, a
printhex1:
	andlw 0x0f;
	sublw 9;
	bc decimal;
	sublw '@';
	bra dotx;
decimal:
	sublw '9';
	; bra dotx

dotx:
	movff	BSR, bsrsave
	banksel UxFIFO
	btfsc UxFIFO, 4, b;
	bra $ - 2;
	movwf UxTXB, b;
	movff	bsrsave, BSR
doreturn:
	return;

#endif

	END
