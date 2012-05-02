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

void SerialPort::init()
{
    fd = -1;
    ::memset(&prevParams, 0, sizeof(prevParams));
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
