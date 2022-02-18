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
bsrsave:
	DS 1	;
cmpt2:
	DS 1	;

WRBLKMSK EQU (WRBLK - 1)

DEVIDP	EQU 0x200000

UxBRGL  EQU     U1BRGL
UxCON0  EQU     U1CON0
UxCON1  EQU     U1CON1
UxCON2  EQU     U1CON2
UxRXB   EQU     U1RXB
UxTXB   EQU     U1TXB
UxFIFO  EQU     U1FIFO

print	macro str
	movlw LOW str
	rcall txstr
	endm

printcr	macro str
	movlw LOW str
	rcall txstrcrlf
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

PSECT code
;strings has to be low in memory, because we set TBLPTRU and TBLPTRH to a
; fixed value
wrstart:
	IRPC char,write id
	    DB 'char'
	ENDM
	DB 0
wrdone:
	IRPC char,write done
	    DB 'char'
	ENDM
	DB 0
#define UPPER(x) (((x) >> 16) & 0xff)

ALIGN 2
start:
	clrf INTCON0, a;
; assume oscillator and serial ports are already set up

	movlw HIGH DEVID
	movwf   BANKMASK(devidh), a
	movlw LOW DEVID
	movwf   BANKMASK(devidl), a

	printcr wrstart
	movf BANKMASK(devidh), a, w
	rcall printhex
	movf BANKMASK(devidl), a, w
	rcall printhex
	rcall crlf
	banksel NVMADRU
	movlw UPPER(DEVIDP)
	movwf NVMADRU, b
	movlw HIGH DEVIDP
	movwf NVMADRH, b
	movlw LOW DEVIDP
	movwf NVMADRL, b
	movlw 0x02 ; page read
	movwf NVMCON1, b
	rcall gonvm
	movf NVMCON1, b, w
	rcall printhex
	movlw 0x06 ; page erase
	movwf NVMCON1, b
	rcall unlocknvm
	movf NVMCON1, b, w
	rcall printhex
	movff devidl, NVMDATL
	movff devidh, NVMDATH
	movlw 0x3; data write
	movwf NVMCON1, b
	rcall unlocknvm
	movf NVMCON1, b, w
	rcall printhex
	clrf NVMCON1, b
	printcr wrdone
	reset

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

txstrcrlf:
	rcall txstr
crlf:
	movlw LOW crlfstr;
txstr:
	movwf TBLPTRL, a;
	clrf TBLPTRU, a;
	movlw	HIGH wrstart
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


	END
