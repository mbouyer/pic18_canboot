# pic18_canboot
pic18 canbus boot loader and utilities

This is a boot loader for pic18, allowing a pic18 to download its
firmware from a CAN bus. This was developed for the canbus_autopilot.
Each device has its own device id stored in eeprom, which is used by
the boot loader to identify itself to the programmer.
This is derived from a xmodem boot loader, which explains the 128-byte block
size :)

Along with the bootloader itself, there are 3 unix utilities:
* canboot_list, which can list J1939 devices present on the bus
* canboot_reset, which sends a reset command to a specific device address
* canboot_host, which waits for the target's bootloader to identify itself,
  and sends the hex file to be flashed.
