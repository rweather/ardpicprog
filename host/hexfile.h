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

#ifndef HEXFILE_H
#define HEXFILE_H

#include "serialport.h"
#include <vector>
#include <string>
#include <stdio.h>

#define FORMAT_AUTO         -1
#define FORMAT_IHX8M        0
#define FORMAT_IHX16        1
#define FORMAT_IHX32        2

class HexFile
{
public:
    HexFile();
    ~HexFile();

    typedef unsigned long Address;
    typedef unsigned short Word;

    bool setDeviceDetails(const DeviceInfoMap &details);

    std::string deviceName() { return _deviceName; }
    void setDeviceName(const std::string &name) { _deviceName = name; }

    int format() const { return _format; }
    void setFormat(int format) { _format = format; }

    Address programStart() const { return _programStart; }
    void setProgramStart(Address address) { _programStart = address; }

    Address programEnd() const { return _programEnd; }
    void setProgramEnd(Address address) { _programEnd = address; }

    Address configStart() const { return _configStart; }
    void setConfigStart(Address address) { _configStart = address; }

    Address configEnd() const { return _configEnd; }
    void setConfigEnd(Address address) { _configEnd = address; }

    Address dataStart() const { return _dataStart; }
    void setDataStart(Address address) { _dataStart = address; }

    Address dataEnd() const { return _dataEnd; }
    void setDataEnd(Address address) { _dataEnd = address; }

    Address reservedStart() const { return _reservedStart; }
    void setReservedStart(Address address) { _reservedStart = address; }

    Address reservedEnd() const { return _reservedEnd; }
    void setReservedEnd(Address address) { _reservedEnd = address; }

    int programBits() const { return _programBits; }
    void setProgramBits(int bits) { _programBits = bits; }

    int dataBits() const { return _dataBits; }
    void setDataBits(int bits) { _dataBits = bits; }

    Address programSizeWords() const { return _programEnd - _programStart + 1; }
    Address dataSizeBytes() const
    {
        return (_dataEnd - _dataStart + 1) * dataBits() / 8;
    }

    Word word(Address address) const;
    void setWord(Address address, Word word);

    bool isAllOnes(Address address) const;
    bool canForceCalibration() const;

    bool read(SerialPort *port);
    bool write(SerialPort *port, bool forceCalibration);

    bool load(FILE *file);

    bool save(const std::string &filename, bool skipOnes) const;
    bool saveCC(const std::string &filename, bool skipOnes) const;

private:
    struct HexFileBlock
    {
        Address address;
        std::vector<Word> data;
    };

    std::string _deviceName;
    Address _programStart;
    Address _programEnd;
    Address _configStart;
    Address _configEnd;
    Address _dataStart;
    Address _dataEnd;
    Address _reservedStart;
    Address _reservedEnd;
    int _programBits;
    int _dataBits;
    int _format;
    std::vector<HexFileBlock> blocks;
    Address count;

    bool readBlock(SerialPort *port, Address start, Address end);
    bool writeBlock(SerialPort *port, Address start, Address end, bool forceCalibration);

    void saveRange(FILE *file, Address start, Address end, bool skipOnes) const;
    void saveRange(FILE *file, Address start, Address end) const;
    static void writeLine(FILE *file, const char *buffer, int len);
    void reportCount();
};

#endif
