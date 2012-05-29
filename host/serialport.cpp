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

#include "serialport.h"
#include <string.h>
#include <stdio.h>

#define BINARY_TRANSFER_MAX 64

SerialPort::SerialPort()
    : buflen(0)
    , bufposn(0)
    , timeoutSecs(3)
{
    init();
}

SerialPort::~SerialPort()
{
    close();
}

static bool deviceNameMatch(const std::string &name1, const std::string &name2)
{
    if (name1.length() != name2.length())
        return false;
    for (std::string::size_type index = 0; index < name1.length(); ++index) {
        int ch1 = name1.at(index);
        int ch2 = name2.at(index);
        if (ch1 >= 'a' && ch1 <= 'z')
            ch1 = ch1 - 'a' + 'A';
        if (ch2 >= 'a' && ch2 <= 'z')
            ch2 = ch2 - 'a' + 'A';
        if (ch1 != ch2)
            return false;
    }
    return true;
}

// Initialize a specific device by issuing "DEVICE" and "SETDEVICE" commands.
// Returns an empty map if the device could not be initialized.
DeviceInfoMap SerialPort::initDevice(const std::string &deviceName)
{
    // Try the "DEVICE" command first to auto-detect the type of
    // device that is in the programming socket.
    if (!command("DEVICE")) {
        fprintf(stderr, "No device in the programmer or programming voltage is not available.\n");
        return DeviceInfoMap();
    }

    // Fetch the device details.  If we have a DeviceName and it matches,
    // then we are ready to go.  If the DeviceName does not match, then we
    // know the type of device in the socket, but it isn't what we wanted.
    // If the DeviceID is "0000" but we have a DeviceName, then the device
    // is an EEPROM that needs a manual override to change the default.
    DeviceInfoMap details = readDeviceInfo();
    DeviceInfoMap::const_iterator it = details.find("DeviceName");
    if (it != details.end()) {
        if (deviceName.empty() || deviceName == "auto")
            return details;     // Use auto-detected device in the socket.
        if (deviceNameMatch(deviceName, (*it).second))
            return details;
        it = details.find("DeviceID");
        if (it == details.end() || (*it).second != "0000") {
            fprintf(stderr, "Expecting %s but found %s in the programmer.\n",
                    deviceName.c_str(), (*it).second.c_str());
            return DeviceInfoMap();
        }
    }

    // If the DeviceID is not "0000", then the device in the socket reports
    // a device identifier, but it is not supported by the programmer.
    it = details.find("DeviceID");
    if (it != details.end() && (*it).second != "0000") {
        fprintf(stderr, "Unsupported device in programmer, ID = %s\n",
                (*it).second.c_str());
        return DeviceInfoMap();
    }

    // If the user wanted to auto-detect the device type, then fail now
    // because we don't know what we have in the socket.
    if (deviceName.empty() || deviceName == "auto") {
        fprintf(stderr, "Cannot autodetect: device in programmer does not have an identifier.\n");
        return DeviceInfoMap();
    }

    // Try using "SETDEVICE" to manually select the device.
    std::string cmd = "SETDEVICE ";
    cmd += deviceName;
    if (command(cmd))
        return readDeviceInfo();

    // The device is not supported.  Print a list of all supported devices.
    fprintf(stderr, "Device %s is not supported by the programmer.\n",
            deviceName.c_str());
    if (command("DEVICES")) {
        std::string devices = readMultiLineResponse();
        fprintf(stderr, "Supported devices:\n%s", devices.c_str());
        fprintf(stderr, "* = autodetected\n");
    }
    return DeviceInfoMap();
}

// Sends a command to the sketch.  Returns true if the response is "OK".
// Returns false if the response is "ERROR" or a timeout occurred.
bool SerialPort::command(const std::string &cmd)
{
    std::string line = cmd;
    line += '\n';
    write(line.c_str(), line.length());
    std::string response = readLine();
    while (response == "PENDING") {
        // Long-running operation: sketch has asked for a longer timeout.
        response = readLine();
    }
    return response == "OK";
}

// Returns a list of the available devices.
std::string SerialPort::devices()
{
    if (!command("DEVICES"))
        return std::string();
    else
        return readMultiLineResponse();
}

// Reads a large block of data using "READBIN".
bool SerialPort::readData(unsigned long start, unsigned long end, unsigned short *data)
{
    char buffer[256];
    sprintf(buffer, "READBIN %04lX-%04lX", start, end);
    if (!command(buffer))
        return false;
    while (start <= end) {
        int pktlen = readChar();
        if (pktlen < 0)
            return false;
        else if (!pktlen)
            break;
        if (!read(buffer, (size_t)pktlen))
            return false;
        int numWords = pktlen / 2;
        if (((unsigned long)numWords) > (end - start + 1))
            numWords = (int)(end - start + 1);
        for (int index = 0; index < numWords; ++index) {
            data[index] = (buffer[index * 2] & 0xFF) |
                          ((buffer[index * 2 + 1] & 0xFF) << 8);
        }
        data += numWords;
        start += numWords;
    }
    return start > end;
}

// Writes a large block of data using a "WRITEBIN" or "WRITE" command.
bool SerialPort::writeData(unsigned long start, unsigned long end, const unsigned short *data, bool force)
{
    char buffer[BINARY_TRANSFER_MAX + 1];
    unsigned long len = (end - start + 1) * 2;
    unsigned int index;
    unsigned short word;
    if (len == 10) {
        // Cannot use "WRITEBIN" for exactly 10 bytes, so use "WRITE" instead.
        sprintf(buffer, "WRITE %s%04lX %04X %04X %04X %04X %04X",
                force ? "FORCE " : "",
                start, data[0], data[1], data[2], data[3], data[4]);
        return command(buffer);
    }
    sprintf(buffer, "WRITEBIN %s%04lX", force ? "FORCE " : "", start);
    if (!command(buffer))
        return false;
    while (len >= BINARY_TRANSFER_MAX) {
        buffer[0] = (char)BINARY_TRANSFER_MAX;
        for (index = 0; index < BINARY_TRANSFER_MAX; index += 2) {
            word = data[index / 2];
            buffer[index + 1] = (char)word;
            buffer[index + 2] = (char)(word >> 8);
        }
        if (!writePacket(buffer, BINARY_TRANSFER_MAX + 1))
            return false;
        data += BINARY_TRANSFER_MAX / 2;
        len -= BINARY_TRANSFER_MAX;
    }
    if (len > 0) {
        buffer[0] = (char)len;
        for (index = 0; index < len; index += 2) {
            word = data[index / 2];
            buffer[index + 1] = (char)word;
            buffer[index + 2] = (char)(word >> 8);
        }
        if (!writePacket(buffer, len + 1))
            return false;
    }
    buffer[0] = (char)0x00; // Terminating packet.
    return writePacket(buffer, 1);
}

bool SerialPort::read(char *data, size_t len)
{
    while (len > 0) {
        int ch = readChar();
        if (ch == -1)
            return false;
        *data++ = (char)ch;
        --len;
    }
    return true;
}

int SerialPort::readChar()
{
    if (bufposn >= buflen) {
        if (!fillBuffer())
            return -1;
    }
    return buffer[bufposn++] & 0xFF;
}

std::string SerialPort::readLine(bool *timedOut)
{
    std::string line;
    int ch;
    if (timedOut)
        *timedOut = false;
    while ((ch = readChar()) != -1) {
        if (ch == 0x0A)
            return line;
        else if (ch != 0x0D && ch != 0x00)
            line += (char)ch;
    }
    if (line.empty() && timedOut)
        *timedOut = true;
    return line;
}

// Reads a multi-line response, terminated by ".", from the sketch.
std::string SerialPort::readMultiLineResponse()
{
    std::string response;
    std::string line;
    bool timedOut;
    for (;;) {
        line = readLine(&timedOut);
        if (timedOut || line == ".")
            break;
        response += line;
        response += '\n';
    }
    return response;
}

static std::string trim(const std::string &str)
{
    std::string::size_type first = 0;
    std::string::size_type last = str.size();
    while (first < last) {
        char ch = str[first];
        if (ch != ' ' && ch != '\t')
            break;
        ++first;
    }
    while (first < last) {
        char ch = str[last - 1];
        if (ch != ' ' && ch != '\t')
            break;
        --last;
    }
    return str.substr(first, last - first);
}

// Reads device information from a multi-line response and returns it as a map.
DeviceInfoMap SerialPort::readDeviceInfo()
{
    DeviceInfoMap response;
    std::string line;
    bool timedOut;
    for (;;) {
        line = readLine(&timedOut);
        if (timedOut || line == ".")
            break;
        std::string::size_type index = line.find(':');
        if (index != std::string::npos) {
            response[trim(line.substr(0, index))]
                = trim(line.substr(index + 1));
        }
    }
    return response;
}

bool SerialPort::writePacket(const char *packet, size_t len)
{
    write(packet, len);
    std::string response = readLine();
    return response == "OK";
}
