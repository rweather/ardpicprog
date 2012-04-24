/*
 * Copyright (C) 2012 Southern Storm Software, Pty Ltd.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <getopt.h>
#include <string>
#include "serialport.h"

/* The command-line options are deliberately designed to be compatible
 * with picprog: http://hyvatti.iki.fi/~jaakko/pic/picprog.html */
static struct option long_options[] = {
    {"burn", no_argument, 0, 'b'},
    {"cc-hexfile", required_argument, 0, 'c'},
    {"copying", no_argument, 0, 'C'},
    {"device", required_argument, 0, 'd'},
    {"erase", no_argument, 0, 'e'},
    {"force-calibration", no_argument, 0, 'f'},
    {"help", no_argument, 0, 'h'},
    {"ihx8m", no_argument, 0, '0'},
    {"ihx16", no_argument, 0, '1'},
    {"ihx32", no_argument, 0, '2'},
    {"input-hexfile", required_argument, 0, 'i'},
    {"output-hexfile", required_argument, 0, 'o'},
    {"pic-serial-port", required_argument, 0, 'p'},
    {"quiet", no_argument, 0, 'q'},
    {"skip-ones", no_argument, 0, 's'},
    {"warranty", no_argument, 0, 'w'},

    /* The following are ignored - backwards compatibility with picprog */
    {"jdm", no_argument, 0, 'N'},
    {"k8048", no_argument, 0, 'N'},
    {"nordtsc", no_argument, 0, 'N'},
    {"rdtsc", no_argument, 0, 'N'},
    {"reboot", no_argument, 0, 'N'},
    {"slow", no_argument, 0, 'N'},

    /* This option is specific to ardpicprog - not present in picprog */
    {"list-devices", no_argument, 0, 'l'},

    {0, 0, 0, 0}
};

#define FORMAT_AUTO         -1
#define FORMAT_IHX8M        0
#define FORMAT_IHX16        1
#define FORMAT_IHX32        2

int opt_quiet = 0;
std::string opt_device;
std::string opt_port;
std::string opt_input;
std::string opt_output;
std::string opt_cc_output;
int opt_format = FORMAT_AUTO;
int opt_skip_ones = 0;
int opt_erase = 0;
int opt_burn = 0;
int opt_force_calibration = 0;
int opt_list_devices = 0;

#ifndef DEFAULT_PIC_PORT
#define DEFAULT_PIC_PORT    "/dev/ttyACM0"
#endif

// Exit codes for compatibility with picprog.
#define EXIT_CODE_OK                0
#define EXIT_CODE_USAGE             64
#define EXIT_CODE_DATA_ERROR        65
#define EXIT_CODE_OPEN_INPUT        66
#define EXIT_CODE_INTERRUPTED       69
#define EXIT_CODE_IO_ERROR          74
#define EXIT_CODE_UNKNWON_DEVICE    76

static void usage(const char *argv0);

int main(int argc, char *argv[])
{
    int opt;
    char *env = getenv("PIC_DEVICE");
    if (env && *env != '\0')
        opt_device = env;
    env = getenv("PIC_PORT");
    if (env && *env != '\0')
        opt_port = env;
    if (opt_port.empty())
        opt_port = DEFAULT_PIC_PORT;
    while ((opt = getopt_long(argc, argv, "c:d:hi:o:p:q",
                              long_options, 0)) != -1) {
        switch (opt) {
        case '0': case '1': case '2':
            /* Set the hexfile format: IHX8M, IHX16, or IHX32 */
            opt_format = opt - '0';
            break;
        case 'b':
            /* Burn the PIC */
            opt_burn = 1;
            break;
        case 'c':
            /* Set the name of the cc output hexfile */
            opt_cc_output = optarg;
            break;
        case 'C':
            /* Display copying message */
            /* TODO */
            return EXIT_CODE_OK;
        case 'd':
            /* Set the type of PIC device to program */
            opt_device = optarg;
            break;
        case 'e':
            /* Erase the PIC */
            opt_erase = 1;
            break;
        case 'f':
            /* Force reprogramming of the OSCCAL word from the hex file
             * rather than by automatic preservation */
            opt_force_calibration = 1;
            break;
        case 'i':
            /* Set the name of the input hexfile */
            opt_input = optarg;
            break;
        case 'l':
            /* List all devices that are supported by the programmer */
            opt_list_devices = 1;
            break;
        case 'o':
            /* Set the name of the output hexfile */
            opt_output = optarg;
            break;
        case 'p':
            /* Set the serial port to use to access the programmer */
            opt_port = optarg;
            break;
        case 'q':
            /* Enable quiet mode */
            opt_quiet = 1;
            break;
        case 's':
            /* Skip memory locations that are all-ones when reading */
            opt_skip_ones = 1;
            break;
        case 'w':
            /* Display warranty message */
            /* TODO */
            return EXIT_CODE_OK;
        case 'N':
            /* Option that is ignored for backwards compatibility */
            break;
        default:
            /* Display the help message and exit */
            usage(argv[0]);
            break;
        }
    }

    /* Bail out if we don't at least have -i, -o, or --list-devices */
    if (opt_input.empty() && opt_output.empty() && !opt_list_devices)
        usage(argv[0]);

    /* Try to open the serial port and initialize the programmer */
    SerialPort port;
    if (!port.open(opt_port))
        return EXIT_CODE_IO_ERROR;

    /* Does the user want to list the available devices? */
    if (opt_list_devices) {
        printf("Supported devices:\n%s", port.devices().c_str());
        printf("* = autodetected\n");
        return EXIT_CODE_OK;
    }

    return EXIT_CODE_OK;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "Usage: %s --quiet -q --warranty --copying --help -h\n", argv0);
    fprintf(stderr, "    --device pictype -d pictype --pic-serial-port device -p device\n");
    fprintf(stderr, "    --input-hexfile path -i path --output-hexfile path -o path\n");
    fprintf(stderr, "    --ihx8m --ihx16 --ihx32 --cc-hexfile path -c path\n");
    fprintf(stderr, "    --skip-ones --erase --burn --force-calibration --reboot\n");
    fprintf(stderr, "    --list-devices\n");
    exit(EXIT_CODE_USAGE);
}
