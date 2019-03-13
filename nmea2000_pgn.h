/* $Id: nmea2000_pgn.h,v 1.2 2017/07/21 20:37:59 bouyer Exp $ */
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

#define NMEA2000_PRIORITY_HIGH		0
#define NMEA2000_PRIORITY_SECURITY	1
#define NMEA2000_PRIORITY_CONTROL	3
#define NMEA2000_PRIORITY_REQUEST	6
#define NMEA2000_PRIORITY_INFO		6
#define NMEA2000_PRIORITY_ACK		6
#define NMEA2000_PRIORITY_LOW		7

#define NMEA2000_ADDR_GLOBAL	255
#define NMEA2000_ADDR_NULL	254
#define NMEA2000_ADDR_MAX	251

#define NMEA2000_DATA_LENGTH 8

/* for NMEA2000 fast-packet frames */
#define FASTPACKET_IDX_MASK 0x1f
#define FASTPACKET_ID_MASK  0xe0

/* request for a PGN */
#define ISO_REQUEST 59904UL
struct iso_request_data {
        unsigned long pgn;
};

#define ISO_ADDRESS_CLAIM 60928UL
struct iso_address_claim_data {
	unsigned char name[NMEA2000_DATA_LENGTH];
};

/* capteur-related PGNs */
#define NEMA2000_ATTITUDE 127257UL
struct nmea2000_attitude_data {
	unsigned char sid;
	int yaw;	// rad * 10000
	int pitch;	// rad * 10000
	int roll;	// rad * 10000
};

#define NEMA2000_RATEOFTURN 127251UL
struct nmea2000_rateofturn_data {
	unsigned char sid;
	long rate;	// rad/s * 1000 * 10000
};

/* GPS-related PGNs */

#define NMEA2000_LATLONG 129025UL
struct nmea2000_latlong_data {
	long latitude; /* deg * 10000000 */
	long longitude; /* deg * 10000000 */
};
	
#define NMEA2000_COGSOG 129026UL
struct nmea2000_cogsog_data {
	unsigned char sid;
	unsigned char cogref	: 2;
	unsigned char res	: 6;
	unsigned int  cog; /* rad * 10000 */
	unsigned int  sog; /* m/s * 100 */
	unsigned char res2[2];
};

#define NMEA2000_XTE 129283UL
struct nmea2000_xte_data {
	unsigned char sid;
	unsigned char mode	: 4;
	unsigned char res	: 2;
	unsigned char navterm	: 2;
	long          xte; /* m * 100, negative = Steer Right */
};

#define NMEA2000_NAVDATA 129284UL
struct nmea2000_navdata_data {
	unsigned char sid;
	unsigned long dist_to_wp; /* m * 100 */
	char          ref	: 2; /* 0 = true; 1 = magn */
	char          cross     : 2;
	char          arrival   : 2;
	char          type      : 2;
	unsigned long eta_time;	/* seconds since 00:00 * 10000 */
	unsigned int  eta_date; /* days since Jan 1, 1970 */
	unsigned int  bearing_o2d; /* rad * 10000 */
	unsigned int  bearing_p2d; /* rad * 10000 */
	unsigned long o_wp_n; /* origin WP number */
	unsigned long d_wp_n; /* dest. WP number */
	unsigned long d_wp_lat; /* deg * 10000000 */
	unsigned long d_wp_lon; /* deg * 10000000 */
	int           wp_closing_speed; /* m/s * 100 */
};

#define NMEA2000_DATETIME 129033UL
struct nmea2000_datetime_data {
	unsigned int  date; /* days since Jan 1, 1970 */
	unsigned long time; /* seconds since 00:00 * 10000 */
	int      local_offset; /* minutes */
};




/*
 * start a recalibration process. The capteur has to be rotating slowly
 * (not more than 5 deg/s) around z.
 * no data
 */
#define PRIVATE_CALIBRATE_COMPASS 25600UL

/*
 * transmit compass offset 
 */
#define PRIVATE_COMPASS_OFFSET 25856UL
struct private_compass_offset_data {
	int offset; // rad * 10000
};

/* command-related PGNs */

/*
 * priodic transmit of command status
 */
#define PRIVATE_COMMAND_STATUS 61846UL
struct private_command_status {
	int heading; /* heading to follow, rad * 10000 */
	union command_errors {
		struct err_bits {
			char	no_capteur_data : 1;
			char	no_rudder_data  : 1;
			char    output_overload : 1;
			char    output_error : 1;
		} bits;
		unsigned char byte;
	} command_errors;
	unsigned char auto_mode;
#define AUTO_OFF        0x0000
#define AUTO_STANDBY    0x0001
#define AUTO_HEAD       0x0002
	char rudder; /* rudder angle report, in % */
	char params_slot; 
};

/*
 * direct command of acuator
 */
#define PRIVATE_COMMAND_ACUATOR 38400UL
struct private_command_acuator {
	char	move; /* how much to move */
};
/*
 * ask command to go on or off auto mode
 */
#define PRIVATE_COMMAND_ENGAGE 38656UL
struct private_command_engage {
	int heading; /* heading to follow, rad * 1000 */
	unsigned char auto_mode; /* see private_command_status */
	unsigned char params_slot; /* which slot parameters to use */
};
/*
 * ack error to command
 */
#define PRIVATE_COMMAND_ERRACK 38912UL
struct private_command_errack {
	union command_errors ack_errors;
};

/*
 * transmit a command parameter factors slot.
 * used both to retrieve it from command, or to write a new one to command.
 */
#define PRIVATE_COMMAND_FACTORS 39168UL
struct private_command_factors {
	char slot;
	int  factors[3];
#define FACTOR_ERR 0
#define FACTOR_DIF 1
#define FACTOR_INT 2
};
/*
 * request a command parameter factors slot.
 */
#define PRIVATE_COMMAND_FACTORS_REQUEST 39424UL
struct private_command_factors_request {
	char slot;
};

/* general, private PGNs */
#define PRIVATE_REMOTE_CONTROL 39680UL
struct private_remote_control {
	char control_type;
	char control_subtype;
	char control_data[6]; /* actually variable type-dependant lenght */
};
#define CONTROL_MOB	0x00
#define CONTROL_MOB_MARK	0x00
#define CONTROL_MOB_SIZE 2
#define CONTROL_LIGHT	0x01
#define CONTROL_LIGHT_OFF	0x00
#define CONTROL_LIGHT_ON	0x01
#define CONTROL_LIGHT_VAL	0x02
#define CONTROL_LIGHT_SIZE     2
#define CONTROL_LIGHT_VAL_SIZE 3
#define CONTROL_RESET	0x02
#define CONTROL_RESET_SIZE 0x01
