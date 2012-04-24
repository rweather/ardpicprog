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
#include <termios.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

#ifndef O_NONBLOCK
#define O_NONBLOCK O_NDELAY
#endif

#define BINARY_TRANSFER_MAX 64

SerialPort::SerialPort()
    : fd(-1)
    , buflen(0)
    , bufposn(0)
    , timeoutSecs(3)
{
    ::memset(&prevParams, 0, sizeof(prevParams));
}

SerialPort::~SerialPort()
{
    close();
}

bool SerialPort::open(const std::string &deviceName, int speed)
{
    close();
    fd = ::open(deviceName.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK, 0);
    if (fd < 0) {
        perror(deviceName.c_str());
        return false;
    }
    struct termios params;
    if (::tcgetattr(fd, &params) < 0) {
        perror(deviceName.c_str());
        ::close(fd);
        fd = -1;
        return false;
    }
    ::memcpy(&prevParams, &params, sizeof(params));
    speed_t speedval;
    switch (speed) {
    case 9600:      speedval = B9600; break;
    case 19200:     speedval = B19200; break;
    case 38400:     speedval = B38400; break;
#ifdef B57600
    case 57600:     speedval = B57600; break;
#endif
#ifdef B115200
    case 115200:    speedval = B115200; break;
#endif
#ifdef B230400
    case 230400:    speedval = B230400; break;
#endif
    default:
        fprintf(stderr, "%s: invalid speed %d\n", deviceName.c_str(), speed);
        ::close(fd);
        fd = -1;
        return false;
    }
    params.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP |
                        INLCR | IGNCR | ICRNL | IXON);
    params.c_oflag &= ~OPOST;
    params.c_cflag &= ~(CSIZE | PARENB | HUPCL);
    params.c_cflag |= CS8;
    params.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    params.c_cc[VMIN] = 0;
    params.c_cc[VTIME] = 0;
    cfsetispeed(&params, speedval);
    cfsetospeed(&params, speedval);
    if (::tcsetattr(fd, TCSANOW, &params) < 0) {
        perror(deviceName.c_str());
        ::close(fd);
        fd = -1;
        return false;
    }
    ::ioctl(fd, TIOCCBRK, 0);
    int lines = 0;
    if (::ioctl(fd, TIOCMGET, &lines) >= 0) {
        lines |= TIOCM_DTR | TIOCM_RTS;
        ::ioctl(fd, TIOCMSET, &lines);
    }

    // At this point, the Arduino may auto-reset so we have to wait for
    // it to come back up again.  Poll the "PROGRAM_PIC_VERSION" command
    // once a second until we get a response.  Give up after 5 seconds.
    int retry = 5;
    int saveTimeout = timeoutSecs;
    timeoutSecs = 1;
    while (retry > 0) {
        write("PROGRAM_PIC_VERSION\n", 20);
        std::string response = readLine();
        if (!response.empty()) {
            if (response.find("ProgramPIC 1.") == 0) {
                // We've found a version 1 sketch, which we can talk to.
                break;
            } else if (response.find("ProgramPIC ") == 0) {
                // Version 2 or higher sketch - cannot talk to this.
                retry = 0;
                break;
            }
        }
        --retry;
    }
    timeoutSecs = saveTimeout;
    if (retry > 0)
        return true;
    ::tcsetattr(fd, TCSANOW, &prevParams);
    ::close(fd);
    fd = -1;
    fprintf(stderr, "%s: did not find a compatible PIC programmer\n",
            deviceName.c_str());
    return false;
}

void SerialPort::close()
{
    if (fd != -1) {
        // Force the programming socket to be powered off.
        command("PWROFF");

        // Restore the original serial parameters and close.
        prevParams.c_cflag &= ~HUPCL;   // Avoid hangup-on-close if possible.
        ::tcsetattr(fd, TCSANOW, &prevParams);
        ::close(fd);
        fd = -1;
    }
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
    if (!command("DEVICE"))
        return DeviceInfoMap();

    // Fetch the device details.  If we have a DeviceName and it matches,
    // then we are ready to go.  If the DeviceName does not match, then we
    // know the type of device in the socket, but it isn't what we wanted.
    DeviceInfoMap details = readDeviceInfo();
    DeviceInfoMap::const_iterator it = details.find("DeviceName");
    if (it != details.end()) {
        if (deviceName.empty() || deviceName == "auto")
            return details;     // Use auto-detected device in the socket.
        if (deviceNameMatch(deviceName, (*it).second))
            return details;
        fprintf(stderr, "Expecting %s but found %s in the programmer.\n",
                deviceName.c_str(), (*it).second.c_str());
        return DeviceInfoMap();
    }

    // If the DeviceID is not "0000", then the device in the socket reports
    // a device identifier, but it is not supported by the programmer.
    it = details.find("DeviceID");
    if (it != details.end() && (*it).second == "0000") {
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
    if (fd == -1)
        return false;
    std::string line = cmd;
    line += '\n';
    write(line.c_str(), line.length());
    std::string response = readLine();
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

static unsigned int readWord(const void *data, int offset)
{
    const char *d = ((const char *)data) + offset;
    return (d[0] & 0xFF) | ((d[1] & 0xFF) << 8);
}

// Reads a large block of data using "READBIN".  The "data" buffer must
// be at least "len" bytes in length.
bool SerialPort::readData(unsigned long addr, void *data, size_t len)
{
    char buffer[64];
    sprintf(buffer, "READBIN %04lX-%04lX", addr, addr + len - 1);
    if (!command(buffer))
        return false;
    for (;;) {
        int pktlen = readChar();
        if (pktlen < 0)
            return false;
        else if (!pktlen)
            break;
        if (((size_t)pktlen) <= len) {
            // Read the next packet.
            if (!read((char *)data, (size_t)pktlen))
                return false;
            data = (void *)(((char *)data) + pktlen);
            len -= (size_t)pktlen;
        } else if (len > 0) {
            // Spurious data on the end of the transfer.  Shouldn't happen.
            if (!read((char *)data, len))
                return false;
            len = 0;
        }
    }
    return true;
}

// Writes a large block of data using a "WRITEBIN" or "WRITE" command.
bool SerialPort::writeData(unsigned long addr, const void *data, size_t len)
{
    char buffer[65];
    if (len == 0x0A) {
        // Cannot use "WRITEBIN" for exactly 10 bytes, so use "WRITE" instead.
        sprintf(buffer, "WRITE %04lX %04X %04X %04X %04X %04X",
                addr, readWord(data, 0), readWord(data, 2),
                readWord(data, 4), readWord(data, 6), readWord(data, 8));
        return command(buffer);
    }
    sprintf(buffer, "WRITEBIN %04lX", addr);
    if (!command(buffer))
        return false;
    while (len >= BINARY_TRANSFER_MAX) {
        buffer[0] = (char)BINARY_TRANSFER_MAX;
        ::memcpy(buffer + 1, data, BINARY_TRANSFER_MAX);
        if (!writePacket(buffer, BINARY_TRANSFER_MAX + 1))
            return false;
        data = (const void *)(((const char *)data) + BINARY_TRANSFER_MAX);
        len -= BINARY_TRANSFER_MAX;
    }
    if (len > 0) {
        buffer[0] = (char)len;
        ::memcpy(buffer + 1, data, len);
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

bool SerialPort::fillBuffer()
{
    ssize_t len;
    fd_set readSet;
    struct timeval timeout;
    for (;;) {
        len = ::read(fd, buffer, sizeof(buffer));
        if (len > 0) {
            buflen = (int)len;
            bufposn = 0;
            return true;
        } else if (len < 0) {
            if (errno == EINTR)
                continue;
            else if (errno != EAGAIN)
                break;
        }
        FD_ZERO(&readSet);
        FD_SET(fd, &readSet);
        timeout.tv_sec = timeoutSecs;
        timeout.tv_usec = 0;
        if (::select(fd + 1, &readSet, (fd_set *)0, (fd_set *)0, &timeout) <= 0)
            break;
    }
    buflen = 0;
    bufposn = 0;
    return false;
}

void SerialPort::write(const char *data, size_t len)
{
    while (len > 0) {
        ssize_t written = ::write(fd, data, len);
        if (written < 0) {
            if (errno != EINTR && errno != EAGAIN)
                break;
        } else if (!written) {
            break;
        } else {
            data += written;
            len -= written;
        }
    }
}

bool SerialPort::writePacket(const char *packet, size_t len)
{
    write(packet, len);
    std::string response = readLine();
    return response == "OK";
}
