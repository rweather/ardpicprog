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
#include "hexfile.h"

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

    /* These options are specific to ardpicprog - not present in picprog */
    {"list-devices", no_argument, 0, 'l'},
    {"speed", required_argument, 0, 'S'},

    {0, 0, 0, 0}
};

bool opt_quiet = false;
std::string opt_device;
std::string opt_port;
std::string opt_input;
std::string opt_output;
std::string opt_cc_output;
int opt_format = FORMAT_AUTO;
bool opt_skip_ones = false;
bool opt_erase = false;
bool opt_burn = false;
bool opt_force_calibration = false;
bool opt_list_devices = false;
int opt_speed = 9600;

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
#define EXIT_CODE_UNKNOWN_DEVICE    76

static void usage(const char *argv0);
static void header();

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
            // Set the hexfile format: IHX8M, IHX16, or IHX32.
            opt_format = opt - '0';
            break;
        case 'b':
            // Burn the PIC.
            opt_burn = true;
            break;
        case 'c':
            // Set the name of the cc output hexfile.
            opt_cc_output = optarg;
            break;
        case 'C':
            // Display copying message.
            // TODO
            return EXIT_CODE_OK;
        case 'd':
            // Set the type of PIC device to program.
            opt_device = optarg;
            break;
        case 'e':
            // Erase the PIC.
            opt_erase = true;
            break;
        case 'f':
            // Force reprogramming of the OSCCAL word from the hex file
            // rather than by automatic preservation.
            opt_force_calibration = true;
            break;
        case 'i':
            // Set the name of the input hexfile.
            opt_input = optarg;
            break;
        case 'l':
            // List all devices that are supported by the programmer.
            opt_list_devices = true;
            break;
        case 'o':
            // Set the name of the output hexfile.
            opt_output = optarg;
            break;
        case 'p':
            // Set the serial port to use to access the programmer.
            opt_port = optarg;
            break;
        case 'q':
            // Enable quiet mode.
            opt_quiet = true;
            break;
        case 's':
            // Skip memory locations that are all-ones when reading.
            opt_skip_ones = true;
            break;
        case 'S':
            // Set the speed for the serial connection.
            opt_speed = atoi(optarg);
            break;
        case 'w':
            // Display warranty message.
            // TODO
            return EXIT_CODE_OK;
        case 'N':
            // Option that is ignored for backwards compatibility.
            break;
        default:
            // Display the help message and exit.
            if (!opt_quiet)
                header();
            usage(argv[0]);
            return EXIT_CODE_USAGE;
        }
    }

    // Print the header.
    if (!opt_quiet)
        header();

    // Bail out if we don't at least have -i, -o, --erase, or --list-devices.
    if (opt_input.empty() && opt_output.empty() && !opt_erase && !opt_list_devices) {
        usage(argv[0]);
        return EXIT_CODE_USAGE;
    }

    // Cannot use -c without -i.
    if (!opt_cc_output.empty() && opt_input.empty()) {
        fprintf(stderr, "Cannot use --cc-hexfile without also specifying --input-hexfile\n");
        usage(argv[0]);
        return EXIT_CODE_USAGE;
    }

    // If we have -i, but no -c or --burn, then report an error.
    if (!opt_input.empty() && opt_cc_output.empty() && !opt_burn) {
        fprintf(stderr, "Cannot use --input-hexfile without also specifying --cc-hexfile or --burn\n");
        usage(argv[0]);
        return EXIT_CODE_USAGE;
    }

    // Cannot use --burn without -i.
    if (opt_burn && opt_input.empty()) {
        fprintf(stderr, "Cannot use --burn without also specifying --input-hexfile\n");
        usage(argv[0]);
        return EXIT_CODE_USAGE;
    }

    // Will need --burn if doing --force-calibration.
    if (opt_force_calibration && !opt_burn) {
        fprintf(stderr, "Cannot use --force-calibration without also specifying --burn\n");
        usage(argv[0]);
        return EXIT_CODE_USAGE;
    }

    // Try to open the serial port and initialize the programmer.
    SerialPort port;
    if (!port.open(opt_port, opt_speed))
        return EXIT_CODE_IO_ERROR;

    // Does the user want to list the available devices?
    if (opt_list_devices) {
        printf("Supported devices:\n%s", port.devices().c_str());
        printf("* = autodetected\n");
        return EXIT_CODE_OK;
    }

    // Initialize the device.
    DeviceInfoMap details = port.initDevice(opt_device);
    if (details.empty())
        return EXIT_CODE_UNKNOWN_DEVICE;

    // Copy the device details into the hex file object.
    HexFile hexFile;
    if (!hexFile.setDeviceDetails(details)) {
        fprintf(stderr, "Device details from programmer are malformed.\n");
        return EXIT_CODE_UNKNOWN_DEVICE;
    }
    hexFile.setFormat(opt_format);

    // Dump the type of device and how much memory it has.
    printf("Device %s, program memory: %ld, data memory: %ld.\n",
           hexFile.deviceName().c_str(),
           hexFile.programEnd() - hexFile.programStart() + 1,
           hexFile.dataEnd() - hexFile.dataStart() + 1);

    // Read the input file.
    if (!opt_input.empty()) {
        FILE *file = fopen(opt_input.c_str(), "r");
        if (!file) {
            perror(opt_input.c_str());
            return EXIT_CODE_OPEN_INPUT;
        }
        if (!hexFile.load(file)) {
            fprintf(stderr, "%s: syntax error, not in hex format\n",
                    opt_input.c_str());
            fclose(file);
            return EXIT_CODE_DATA_ERROR;
        }
        fclose(file);
    }

    // Copy the input to the CC output file.
    if (!opt_cc_output.empty()) {
        if (!hexFile.saveCC(opt_cc_output, opt_skip_ones))
            return EXIT_CODE_OPEN_INPUT;
    }

    // Erase the device if necessary.  If --force-calibration is specified
    // and we have an input that includes calibration information, then use
    // the "NOPRESERVE" option when erasing.
    if (opt_erase) {
        if (opt_force_calibration) {
            if (hexFile.canForceCalibration()) {
                if (!port.command("ERASE NOPRESERVE")) {
                    fprintf(stderr, "Erase of device failed\n");
                    return EXIT_CODE_IO_ERROR;
                }
            } else {
                fprintf(stderr, "Input does not have calibration data.  Will not erase device.\n");
                return EXIT_CODE_IO_ERROR;
            }
        } else if (!port.command("ERASE")) {
            fprintf(stderr, "Erase of device failed\n");
            return EXIT_CODE_IO_ERROR;
        }
        printf("Erased and removed code protection.\n");
    }

    // Burn the input file into the device if requested.
    if (opt_burn) {
        if (!hexFile.write(&port, opt_force_calibration)) {
            fprintf(stderr, "Write to device failed\n");
            return EXIT_CODE_IO_ERROR;
        }
    }

    // If we have an output file, then read the contents of the PIC into it.
    if (!opt_output.empty()) {
        if (!hexFile.read(&port)) {
            fprintf(stderr, "Read from device failed\n");
            return EXIT_CODE_IO_ERROR;
        }
        if (!hexFile.save(opt_output, opt_skip_ones))
            return EXIT_CODE_IO_ERROR;
    }

    // Done.
    return EXIT_CODE_OK;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "Usage: %s --quiet -q --warranty --copying --help -h\n", argv0);
    fprintf(stderr, "    --device pictype -d pictype --pic-serial-port device -p device\n");
    fprintf(stderr, "    --input-hexfile path -i path --output-hexfile path -o path\n");
    fprintf(stderr, "    --ihx8m --ihx16 --ihx32 --cc-hexfile path -c path --skip-ones\n");
    fprintf(stderr, "    --erase --burn --force-calibration --list-devices --speed speed\n");
}

static void header()
{
    fprintf(stderr, "Argpicprog version %s, Copyright (c) 2012 Southern Storm Pty Ltd.\n", ARDPICPROG_VERSION);
    fprintf(stderr, "Ardpicprog comes with ABSOLUTELY NO WARRANTY; for details\n");
    fprintf(stderr, "type `ardpicprog --warranty'.  This is free software,\n");
    fprintf(stderr, "and you are welcome to redistribute it under certain conditions;\n");
    fprintf(stderr, "type `ardpicprog --copying' for details.\n");
    fprintf(stderr, "\n");
}
