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

/* The command-line options are deliberately designed to be compatible
 * with picprog: http://hyvatti.iki.fi/~jaakko/pic/picprog.html */
static struct option long_options[] = {
    {"quiet", no_argument, 0, 'q'},
    {"warranty", no_argument, 0, 'w'},
    {"copying", no_argument, 0, 'C'},
    {"copyright", no_argument, 0, 'C'},
    {"help", no_argument, 0, 'h'},
    {"device", required_argument, 0, 'd'},
    {"pic-serial-port", required_argument, 0, 'p'},
    {"pic", required_argument, 0, 'p'},
    {"input-hexfile", required_argument, 0, 'i'},
    {"input", required_argument, 0, 'i'},
    {"output-hexfile", required_argument, 0, 'o'},
    {"output", required_argument, 0, 'o'},
    {"cc-hexfile", required_argument, 0, 'c'},
    {"ihx8m", no_argument, 0, '0'},
    {"ihx16", no_argument, 0, '1'},
    {"ihx32", no_argument, 0, '2'},
    {"skip-ones", no_argument, 0, 's'},
    {"erase", no_argument, 0, 'e'},
    {"burn", no_argument, 0, 'b'},
    {"force-calibration", no_argument, 0, 'f'},
    {"reboot", no_argument, 0, 'N'},    /* Ignored - backwards compat */
    {"nordtsc", no_argument, 0, 'N'},   /* Ignored - backwards compat */
    {"rdtsc", no_argument, 0, 'N'},     /* Ignored - backwards compat */
    {"slow", no_argument, 0, 'N'},      /* Ignored - backwards compat */
    {"k8048", no_argument, 0, 'N'},     /* Ignored - backwards compat */
    {"jdm", no_argument, 0, 'N'},       /* Ignored - backwards compat */
    {0, 0, 0, 0}
};

#define FORMAT_AUTO         -1
#define FORMAT_IHX8M        0
#define FORMAT_IHX16        1
#define FORMAT_IHX32        2

int opt_quiet = 0;
char *opt_device = 0;
char *opt_port = 0;
char *opt_input = 0;
char *opt_output = 0;
char *opt_cc_output = 0;
int opt_format = FORMAT_AUTO;
int opt_skip_ones = 0;
int opt_erase = 0;
int opt_burn = 0;
int opt_force_calibration = 0;

static void usage(const char *argv0);

int main(int argc, char *argv[])
{
    int opt;
    opt_device = getenv("PIC_DEVICE");
    opt_port = getenv("PIC_PORT");
    while ((opt = getopt_long(argc, argv, "qhd:p:i:o:c:",
                              long_options, 0)) != -1) {
        switch (opt) {
        case 'q':
            /* Enable quiet mode */
            break;
        case 'w':
            /* Display warranty message */
            break;
        case 'C':
            /* Display copying message */
            break;
        case 'd':
            /* Set the type of PIC device to program */
            opt_device = optarg;
            break;
        case 'p':
            /* Set the serial port to use to access the programmer */
            opt_port = optarg;
            break;
        case 'i':
            /* Set the name of the input hexfile */
            opt_input = optarg;
            break;
        case 'o':
            /* Set the name of the output hexfile */
            opt_output = optarg;
            break;
        case 'c':
            /* Set the name of the cc output hexfile */
            opt_cc_output = optarg;
            break;
        case '0': case '1': case '2':
            /* Set the hexfile format: IHX8M, IHX16, or IHX32 */
            opt_format = opt - '0';
            break;
        case 's':
            /* Skip memory locations that are all-ones when reading */
            opt_skip_ones = 1;
            break;
        case 'e':
            /* Erase the PIC */
            opt_erase = 1;
            break;
        case 'b':
            /* Burn the PIC */
            opt_burn = 1;
            break;
        case 'f':
            /* Force reprogramming of the OSCCAL word when erasing the PIC */
            opt_force_calibration = 1;
            break;
        case 'N':
            /* Option that is ignored for backwards compatibility */
            break;
        default:
            /* Display the help message and exit */
            usage(argv[0]);
            break;
        }
    }

    /* Bail out if we don't at least have -i or -o, plus -p */
    if ((!opt_input && !opt_output) || !opt_port)
        usage(argv[0]);

    return 0;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "Usage: %s --quiet -q --warranty --copying --help -h\n", argv0);
    fprintf(stderr, "    --device pictype -d pictype --pic-serial-port device -p device\n");
    fprintf(stderr, "    --input-hexfile path -i path --output-hexfile path -o path\n");
    fprintf(stderr, "    --ihx8m --ihx16 --ihx32 --cc-hexfile path -c path\n");
    fprintf(stderr, "    --skip-ones --erase --burn --force-calibration --reboot\n");
    exit(64);
}
