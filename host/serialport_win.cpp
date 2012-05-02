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

void SerialPort::init()
{
    handle = INVALID_HANDLE_VALUE;
    ::memset(&timeouts, 0, sizeof(timeouts));
    lastTimeoutSecs = -1;
}

bool SerialPort::open(const std::string &deviceName, int speed)
{
    close();
    lastTimeoutSecs = -1;

    // Open the COM port.
    std::string dev(deviceName);
    if (dev.find("/dev/") == 0)
        dev = dev.substr(5);    // Just in case cygwin-style name is specified.
    handle = ::CreateFile(dev.c_str(), GENERIC_READ | GENERIC_WRITE,
                          0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        DWORD error = ::GetLastError();
        if (error == ERROR_FILE_NOT_FOUND)
            fprintf(stderr, "%s: No such file or directory\n", deviceName.c_str());
        else
            fprintf(stderr, "%s: Cannot open serial port\n", deviceName.c_str());
        return false;
    }

    // Set the serial parameters.
    DCB dcb;
    if (!::GetCommState(handle, &dcb)) {
        fprintf(stderr, "%s: Not a serial port\n", deviceName.c_str());
        ::CloseHandle(handle);
        handle = INVALID_HANDLE_VALUE;
        return false;
    }
    dcb.BaudRate = speed;
    dcb.ByteSize = 8;
    dcb.StopBits = ONESTOPBIT;
    dcb.Parity = NOPARITY;
    dcb.fDtrControl = DTR_CONTROL_ENABLE;
    if (!::SetCommState(handle, &dcb)) {
        fprintf(stderr, "%s: Could not set serial parameters\n", deviceName.c_str());
        ::CloseHandle(handle);
        handle = INVALID_HANDLE_VALUE;
        return false;
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
    ::CloseHandle(handle);
    handle = INVALID_HANDLE_VALUE;
    fprintf(stderr, "%s: did not find a compatible PIC programmer\n",
            deviceName.c_str());
    return false;
}

void SerialPort::close()
{
    if (handle != INVALID_HANDLE_VALUE) {
        // Force the programming socket to be powered off.
        command("PWROFF");

        // Close the handle to the serial port.
        ::CloseHandle(handle);
        handle = INVALID_HANDLE_VALUE;
    }
}

bool SerialPort::fillBuffer()
{
    DWORD errors;
    COMSTAT status;
    DWORD size, bytesRead;
    buflen = 0;
    bufposn = 0;
    ::ClearCommError(handle, &errors, &status);
    if (status.cbInQue > 0) {
        // There is data ready to be received, so fetch it immediately.
        size = sizeof(buffer);
        if (size > status.cbInQue)
            size = status.cbInQue;
        if (::ReadFile(handle, buffer, size, &bytesRead, NULL) && bytesRead != 0) {
            buflen = (int)bytesRead;
            return true;
        }
    } else {
        // Set the desired timeout and then read.
        if (lastTimeoutSecs != timeoutSecs) {
            timeouts.ReadIntervalTimeout = MAXDWORD;
            timeouts.ReadTotalTimeoutConstant = timeoutSecs * 1000;
            timeouts.ReadTotalTimeoutMultiplier = MAXDWORD;
            ::SetCommTimeouts(handle, &timeouts);
            lastTimeoutSecs = timeoutSecs;
        }
        if (::ReadFile(handle, buffer, sizeof(buffer), &bytesRead, NULL) && bytesRead != 0) {
            buflen = (int)bytesRead;
            return true;
        }
    }
    return false;
}

void SerialPort::write(const char *data, size_t len)
{
    DWORD written;
    if (!::WriteFile(handle, data, len, &written, NULL)) {
        DWORD errors;
        COMSTAT status;
        ::ClearCommError(handle, &errors, &status);
    }
}
