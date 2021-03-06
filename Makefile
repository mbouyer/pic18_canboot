all: utools

utools: canboot_host canboot_reset canboot_list

canboot_host: canboot_host.c canboot_defs.h nmea2000_class.h nmea2000_pgn.h
	cc -o canboot_host canboot_host.c

canboot_reset: canboot_reset.c canboot_defs.h nmea2000_class.h nmea2000_pgn.h
	cc -o canboot_reset canboot_reset.c

canboot_list: canboot_list.c canboot_defs.h nmea2000_pgn.h
	cc -o canboot_list canboot_list.c

canboot.bin: canboot.hex
	./hex2bin canboot.hex canboot.bin

canboot.hex: canboot.asm
	gpasm canboot.asm

clean:
	rm -f canboot_host canboot_reset canboot_list *.cod *.hex *.lst
