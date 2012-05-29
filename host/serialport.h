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

#ifndef SERIALPORT_H
#define SERIALPORT_H

#include <string>
#include <map>
#include <stddef.h>
#ifdef _WIN32
#define	SERIAL_WIN32	1
#include <windows.h>
#else
#define	SERIAL_POSIX	1
#include <termios.h>
#endif

typedef std::map<std::string, std::string> DeviceInfoMap;

class SerialPort
{
public:
    SerialPort();
    ~SerialPort();

    bool open(const std::string &deviceName, int speed = 9600);
    void close();

    DeviceInfoMap initDevice(const std::string &deviceName);

    bool command(const std::string &cmd);

    std::string devices();

    bool readData(unsigned long start, unsigned long end, unsigned short *data);
    bool writeData(unsigned long start, unsigned long end, const unsigned short *data, bool force);

    int timeout() const { return timeoutSecs; }
    void setTimeout(int timeout) { timeoutSecs = timeout; }

private:
#ifdef SERIAL_POSIX
    int fd;
    struct termios prevParams;
#endif
#ifdef SERIAL_WIN32
    HANDLE handle;
    COMMTIMEOUTS timeouts;
    int lastTimeoutSecs;
#endif
    char buffer[1024];
    int buflen;
    int bufposn;
    int timeoutSecs;

    void init();

    bool read(char *data, size_t len);
    int readChar();
    std::string readLine(bool *timedOut = 0);
    std::string readMultiLineResponse();
    DeviceInfoMap readDeviceInfo();

    bool fillBuffer();
    void write(const char *data, size_t len);
    bool writePacket(const char *packet, size_t len);
};

#endif
