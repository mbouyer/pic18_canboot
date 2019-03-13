; 
;  Redistribution and use in source and binary forms, with or without
;  modification, are permitted provided that the following conditions
;  are met:
;  1. Redistributions of source code must retain the above copyright
;     notice, this list of conditions and the following disclaimer.
;  2. Redistributions in binary form must reproduce the above copyright
;     notice, this list of conditions and the following disclaimer in the
;     documentation and/or other materials provided with the distribution.
;  3. All advertising materials mentioning features or use of this software
;     must display the following acknowledgement:
;       This product includes software developed by Manuel Bouyer.
;  4. The name of the author may not be used to endorse or promote products
;     derived from this software without specific prior written permission.
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
	devidh	: 1	;
	devidl	: 1	;
	tmp	: 1	;
	cmpt1	: 1	;
	cmpt2	: 1	;
	ENDC                    ; end of vars

; flash-related defines
OFFSET	EQU 0x400
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

print	macro str
	movlw LOW str
	rcall txstr
	endm

printcr	macro str
	movlw LOW str
	rcall txstrcrlf
	endm

	ORG OFFSET
	nop;
	bra start
crlfstr DA "\r\n\0"; ! only 4 bytes available
	ORG OFFSET + 0x0008 ; interrupt vector;
	reset
	ORG OFFSET + 0x0018;
	reset

;strings has to be low in memory, because we set TBLPTRU and TBLPTRH to a
; fixed value
bootstr DA "write id\0"
endstr	DA "write done\0";

start
	clrf INTCON, a;
; assume oscillator and serial ports are already set up

	movlw HIGH DEVID
	movwf	devidh
	movlw LOW DEVID
	movwf	devidl

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

	; ID to flash

	movlw	UPPER DEVIDP
	movwf	TBLPTRU
	movlw	HIGH DEVIDP
	movwf	TBLPTRH
	movlw	LOW DEVIDP
	movwf	TBLPTRL
	movlw b'10010100'
	movwf EECON1; point to flash, access flash, enable write, enable erase
	rcall dowrite
	movff devidl, TABLAT;
	tblwt*+;
	movff devidh, TABLAT;
	tblwt*;
	movlw b'10000100'
	movwf EECON1; point to flash, access flash, enable write
	rcall dowrite

doend:
	printcr endstr
	rcall crlf
	reset

dowrite
	movlw 0x55;
	movwf EECON2;
	movlw 0xAA;
	movwf EECON2;
	bsf EECON1, WR; start write;
	nop
	return;

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

	END
