all: utools

utools: canboot_host canboot_reset canboot_list

canboot_host: canboot_host.c canboot_defs.h nmea2000_class.h nmea2000_pgn.h
	cc -o canboot_host canboot_host.c

canboot_reset: canboot_reset.c canboot_defs.h nmea2000_class.h nmea2000_pgn.h
	cc -o canboot_reset canboot_reset.c

canboot_list: canboot_list.c canboot_defs.h nmea2000_pgn.h nmea2000_class.h
	cc -o canboot_list canboot_list.c

canboot.bin: canboot.hex
	hex2bin 0x200 canboot.hex canboot.bin

canboot.hex: canboot.asm
	gpasm canboot.asm

#CB_DEBUG=-DDEBUG
#CB_END=700
CB_END=600
canboot_bigsec.hex: canboot_bigsec.S
	pic-as ${CB_DEBUG} -mcpu=18F27Q84 -mrom=300-${CB_END} -Wl,-presetVec=300h -Wl,-pivth=308h -Wl,-pivtl=318h -Wa,-a -Wl,-Map=canboot_bigsec.map canboot_bigsec.S

canboot_bigsec.bin: canboot_bigsec.hex
	hex2bin 0x300 canboot_bigsec.hex canboot_bigsec.bin

writeid_bigsec.hex: writeid_bigsec.S
	pic-as -DDEVID=${DEVID} -mcpu=18F27Q84 -mrom=300-3ff -Wl,-presetVec=300h -Wa,-a -Wl,-Map=writeid_bigsec.map writeid_bigsec.S

writeid_bigsec.bin: writeid_bigsec.hex
	hex2bin 0x300 writeid_bigsec.hex writeid_bigsec.bin

clean:
	rm -f canboot_host canboot_reset canboot_list *.cod *.hex *.lst
