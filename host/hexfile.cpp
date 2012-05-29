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

#include "hexfile.h"
#include <stdlib.h>

// Reference: http://en.wikipedia.org/wiki/Intel_HEX

HexFile::HexFile()
    : _programStart(0x0000)
    , _programEnd(0x07FF)
    , _configStart(0x2000)
    , _configEnd(0x2007)
    , _dataStart(0x2100)
    , _dataEnd(0x217F)
    , _reservedStart(0x0800)
    , _reservedEnd(0x07FF)
    , _programBits(14)
    , _dataBits(8)
    , _format(FORMAT_AUTO)
    , count(0)
{
}

HexFile::~HexFile()
{
}

static inline std::string fetchMap
    (const DeviceInfoMap &details, const std::string &key)
{
    DeviceInfoMap::const_iterator it = details.find(key);
    if (it != details.end())
        return (*it).second;
    else
        return std::string();
}

static inline std::string fetchMap
    (const DeviceInfoMap &details, const std::string &key,
     const std::string &defValue)
{
    DeviceInfoMap::const_iterator it = details.find(key);
    if (it != details.end())
        return (*it).second;
    else
        return defValue;
}

static bool parseHex(const std::string &str, HexFile::Address *value)
{
    bool haveHex = false;
    *value = 0;
    for (std::string::size_type index = 0; index < str.length(); ++index) {
        char ch = str[index];
        if (ch >= '0' && ch <= '9') {
            *value = (*value << 4) | (ch - '0');
            haveHex = true;
        } else if (ch >= 'A' && ch <= 'F') {
            *value = (*value << 4) | (ch - 'A' + 10);
            haveHex = true;
        } else if (ch >= 'a' && ch <= 'f') {
            *value = (*value << 4) | (ch - 'a' + 10);
            haveHex = true;
        } else if (ch != ' ' && ch != '\t') {
            return false;
        }
    }
    return haveHex;
}

static bool parseRange
    (const std::string &value, HexFile::Address *start,
     HexFile::Address *end)
{
    std::string::size_type index = value.find('-');
    if (index == std::string::npos)
        return false;
    if (!parseHex(value.substr(0, index), start))
        return false;
    return parseHex(value.substr(index + 1), end);
}

bool HexFile::setDeviceDetails(const DeviceInfoMap &details)
{
    std::string value;

    _deviceName = fetchMap(details, "DeviceName");

    value = fetchMap(details, "ProgramRange");
    if (!value.empty()) {
        if (!parseRange(value, &_programStart, &_programEnd))
            return false;
    } else {
        // Disable the program range - device doesn't have program memory.
        _programStart = 0x0001;
        _programEnd = 0x0000;
    }
    _programBits = atoi(fetchMap(details, "ProgramBits", "14").c_str());

    value = fetchMap(details, "ConfigRange");
    if (!value.empty()) {
        if (!parseRange(value, &_configStart, &_configEnd))
            return false;
    } else {
        // Disable the config range - device doesn't have config memory.
        _configStart = 0x2000;
        _configEnd = 0x1FFF;
    }

    value = fetchMap(details, "DataRange");
    if (!value.empty()) {
        if (!parseRange(value, &_dataStart, &_dataEnd))
            return false;
    } else {
        // Disable the data range - device doesn't have data memory.
        _dataStart = 0x2100;
        _dataEnd = 0x20FF;
    }
    _dataBits = atoi(fetchMap(details, "DataBits", "8").c_str());

    value = fetchMap(details, "ReservedRange");
    if (!value.empty()) {
        if (!parseRange(value, &_reservedStart, &_reservedEnd))
            return false;
    } else {
        // Disable the reserved range - device doesn't have reserved words.
        _reservedStart = _programEnd + 1;
        _reservedEnd = _programEnd;
    }

    return _programBits >= 1 && _dataBits >= 1;
}

HexFile::Word HexFile::word(Address address) const
{
    std::vector<HexFileBlock>::const_iterator it;
    for (it = blocks.begin(); it != blocks.end(); ++it) {
        if (address >= (*it).address &&
                address < ((*it).address + (*it).data.size())) {
            return (*it).data[(std::vector<HexFileBlock>::size_type)(address - (*it).address)];
        }
    }
    if (address >= _dataStart && address <= _dataEnd)
        return (Word)((1 << _dataBits) - 1);
    else
        return (Word)((1 << _programBits) - 1);
}

void HexFile::setWord(Address address, Word word)
{
    std::vector<HexFileBlock>::iterator it;
    std::vector<HexFileBlock>::size_type index;
    for (it = blocks.begin(), index = 0; it != blocks.end(); ++it, ++index) {
        HexFileBlock &block = *it;
        if (address < block.address) {
            if (address == (block.address - 1)) {
                // Prepend to the existing block.
                block.address--;
                block.data.insert(block.data.begin(), word);
            } else {
                // Create a new block before this one.
                HexFileBlock newBlock;
                newBlock.address = address;
                newBlock.data.push_back(word);
                blocks.insert(it, newBlock);
            }
            return;
        } else if (address < ((*it).address + (*it).data.size())) {
            // Update a word in an existing block.
            block.data[(std::vector<HexFileBlock>::size_type)(address - block.address)] = word;
            return;
        } else if (address == ((*it).address + (*it).data.size())) {
            // Can we extend the current block without hitting the next block?
            if (index < (blocks.size() - 1)) {
                HexFileBlock &next = blocks[index + 1];
                if (address < next.address) {
                    block.data.push_back(word);
                    return;
                }
            } else {
                block.data.push_back(word);
                return;
            }
        }
    }
    HexFileBlock block;
    block.address = address;
    block.data.push_back(word);
    blocks.push_back(block);
}

bool HexFile::isAllOnes(Address address) const
{
    Word allOnes;
    if (address >= _dataStart && address <= _dataEnd)
        allOnes = (Word)((1 << _dataBits) - 1);
    else
        allOnes = (Word)((1 << _programBits) - 1);
    return word(address) == allOnes;
}

bool HexFile::canForceCalibration() const
{
    if (_reservedStart > _reservedEnd)
        return true;    // No reserved words, so force is trivially ok.
    for (HexFile::Address address = _reservedStart;
                address <= _reservedEnd; ++address) {
        if (!isAllOnes(address))
            return true;
    }
    return false;
}

bool HexFile::read(SerialPort *port)
{
    blocks.clear();
    if (_programStart <= _programEnd) {
        printf("Reading program memory,\n");
        if (!readBlock(port, _programStart, _programEnd))
            return false;
    } else {
        printf("Skipped reading program memory,\n");
    }
    if (_dataStart <= _dataEnd) {
        printf("reading data memory,\n");
        if (!readBlock(port, _dataStart, _dataEnd))
            return false;
    } else {
        printf("skipped reading data memory,\n");
    }
    if (_configStart <= _configEnd) {
        printf("reading id words and fuses,\n");  // Done in one hit.
        if (!readBlock(port, _configStart, _configEnd))
            return false;
    } else {
        printf("skipped reading id words and fuses,\n");
    }
    printf("done.\n");
    return true;
}

bool HexFile::readBlock(SerialPort *port, Address start, Address end)
{
    HexFileBlock block;
    block.address = start;
    block.data.resize(std::vector<unsigned short>::size_type(end - start + 1));
    if (!port->readData(start, end, &(block.data.at(0))))
        return false;
    std::vector<HexFileBlock>::iterator it;
    for (it = blocks.begin(); it != blocks.end(); ++it) {
        if (start <= (*it).address) {
            blocks.insert(it, block);
            return true;
        }
    }
    blocks.push_back(block);
    return true;
}

bool HexFile::write(SerialPort *port, bool forceCalibration)
{
    // Write the contents of program memory.
    count = 0;
    if (_programStart <= _programEnd) {
        printf("Burning program memory,");
        fflush(stdout);
        if (forceCalibration || _reservedStart > _reservedEnd) {
            // Calibration forced or no reserved words to worry about.
            if (!writeBlock(port, _programStart, _programEnd, forceCalibration))
                return false;
        } else {
            // Assumes: reserved words are always at the end of program memory.
            if (!writeBlock(port, _programStart, _reservedStart - 1, forceCalibration))
                return false;
        }
        reportCount();
    } else {
        printf("Skipped burning program memory,\n");
    }

    // Write data memory before config memory in case the configuration
    // word turns on data protection and thus hinders data verification.
    if (_dataStart <= _dataEnd) {
        printf("burning data memory,");
        fflush(stdout);
        if (!writeBlock(port, _dataStart, _dataEnd, forceCalibration))
            return false;
        reportCount();
    } else {
        printf("skipped burning data memory,\n");
    }

    // Write the contents of config memory.
    if (_configStart <= _configEnd) {
        printf("burning id words and fuses,");
        fflush(stdout);
        if (!writeBlock(port, _configStart, _configEnd, forceCalibration))
            return false;
        reportCount();
    } else {
        printf("skipped burning id words and fuses,");
    }

    printf("done.\n");
    return true;
}

bool HexFile::writeBlock(SerialPort *port, Address start, Address end, bool forceCalibration)
{
    std::vector<HexFileBlock>::const_iterator it;
    for (it = blocks.begin(); it != blocks.end(); ++it) {
        Address blockStart = (*it).address;
        Address blockEnd = blockStart + (*it).data.size() - 1;
        if (start <= blockEnd && end >= blockStart) {
            const unsigned short *data = &((*it).data.at(0));
            Address overlapStart;
            Address overlapEnd;
            if (start > blockStart) {
                data += std::vector<unsigned short>::size_type
                    (start - blockStart);
                overlapStart = start;
            } else {
                overlapStart = blockStart;
            }
            if (end < blockEnd)
                overlapEnd = end;
            else
                overlapEnd = blockEnd;
            if (!port->writeData(overlapStart, overlapEnd, data, forceCalibration))
                return false;
            count += overlapEnd - overlapStart + 1;
        }
    }
    return true;
}

void HexFile::reportCount()
{
    if (count == 1)
        printf(" 1 location,\n");
    else
        printf(" %lu locations,\n", count);
    count = 0;
}

// Read a big-endian word value from a buffer.
static inline HexFile::Word readBigWord
    (const std::vector<char> &buf, std::vector<char>::size_type index)
{
    return ((buf[index] & 0xFF) << 8) | (buf[index + 1] & 0xFF);
}

// Read a little-endian word value from a buffer.
static inline HexFile::Word readLittleWord
    (const std::vector<char> &buf, std::vector<char>::size_type index)
{
    return ((buf[index + 1] & 0xFF) << 8) | (buf[index] & 0xFF);
}

bool HexFile::load(FILE *file)
{
    bool startLine = true;
    std::vector<char> line;
    int ch, digit;
    int nibble = -1;
    bool ok = false;
    int checksum;
    Address baseAddress = 0;
    std::vector<char>::size_type index;
    while ((ch = getc(file)) != EOF) {
        if (ch == ' ' || ch == '\t')
            continue;
        if (ch == '\r' || ch == '\n') {
            if (nibble != -1) {
                // Half a byte at the end of the line.
                break;
            }
            if (!startLine) {
                if (line.size() < 5) {
                    // Not enough bytes to form a valid line.
                    break;
                }
                if ((line[0] & 0xFF) != (int)(line.size() - 5)) {
                    // Size value is incorrect.
                    break;
                }
                checksum = 0;
                for (index = 0; index < (line.size() - 1); ++index)
                    checksum += (line[index] & 0xFF);
                checksum = (((checksum & 0xFF) ^ 0xFF) + 1) & 0xFF;
                if (checksum != (line[line.size() - 1] & 0xFF)) {
                    // Checksum for this line is incorrect.
                    break;
                }
                if (line[3] == 0x00) {
                    // Data record.
                    if ((line[0] & 0x01) != 0)
                        break;      // Line length must be even.
                    Address address = baseAddress + readBigWord(line, 1);
                    if (address & 0x0001)
                        break;      // Address must also be even.
                    address >>= 1;  // Convert byte address into word address.
                    for (index = 0; index < (line.size() - 5); index += 2) {
                        Word word = readLittleWord(line, index + 4);
                        setWord(address + index / 2, word);
                    }
                } else if (line[3] == 0x01) {
                    // Stop processing at the End Of File Record.
                    if (line[0] != 0x00)
                        break;      // Invalid end of file record.
                    ok = true;
                    break;
                } else if (line[3] == 0x02) {
                    // Extended Segment Address Record.
                    if (line[0] != 0x02)
                        break;      // Invalid address record.
                    baseAddress = ((Address)readBigWord(line, 4)) << 4;
                } else if (line[3] == 0x04) {
                    // Extended Linear Address Record.
                    if (line[0] != 0x02)
                        break;      // Invalid address record.
                    baseAddress = ((Address)readBigWord(line, 4)) << 16;
                } else if (line[3] != 0x03 && line[3] != 0x05) {
                    // Invalid record type.
                    break;
                }
            }
            line.clear();
            startLine = true;
            continue;
        }
        if (ch == ':') {
            if (!startLine) {
                // ':' did not appear at the start of a line.
                break;
            } else {
                startLine = false;
                continue;
            }
        } else if (ch >= '0' && ch <= '9') {
            digit = ch - '0';
        } else if (ch >= 'A' && ch <= 'F') {
            digit = ch - 'A' + 10;
        } else if (ch >= 'a' && ch <= 'f') {
            digit = ch - 'a' + 10;
        } else {
            // Invalid character in hex file.
            break;
        }
        if (startLine) {
            // Hex digit at the start of a line.
            break;
        }
        if (nibble == -1) {
            nibble = digit;
        } else {
            line.push_back((char)((nibble << 4) | digit));
            nibble = -1;
        }
    }
    return ok;
}

bool HexFile::save(const std::string &filename, bool skipOnes) const
{
    FILE *file = fopen(filename.c_str(), "w");
    if (!file) {
        perror(filename.c_str());
        return false;
    }
    saveRange(file, _programStart, _programEnd, skipOnes);
    if (_configStart <= _configEnd) {
        if ((_configEnd - _configStart + 1) >= 8) {
            saveRange(file, _configStart, _configStart + 5, skipOnes);
            // Don't bother saving the device ID word at _configStart + 6.
            saveRange(file, _configStart + 7, _configEnd, skipOnes);
        } else {
            saveRange(file, _configStart, _configEnd, skipOnes);
        }
    }
    saveRange(file, _dataStart, _dataEnd, skipOnes);
    fputs(":00000001FF\n", file);
    fclose(file);
    return true;
}

bool HexFile::saveCC(const std::string &filename, bool skipOnes) const
{
    FILE *file = fopen(filename.c_str(), "w");
    if (!file) {
        perror(filename.c_str());
        return false;
    }
    std::vector<HexFileBlock>::const_iterator it;
    for (it = blocks.begin(); it != blocks.end(); ++it) {
        Address start = (*it).address;
        Address end = start + (*it).data.size() - 1;
        saveRange(file, start, end, skipOnes);
    }
    fputs(":00000001FF\n", file);
    fclose(file);
    return true;
}

void HexFile::saveRange(FILE *file, Address start, Address end, bool skipOnes) const
{
    if (skipOnes) {
        while (start <= end) {
            while (start <= end && isAllOnes(start))
                ++start;
            if (start > end)
                break;
            Address limit = start + 1;
            while (limit <= end && !isAllOnes(limit))
                ++limit;
            saveRange(file, start, limit - 1);
            start = limit;
        }
    } else {
        saveRange(file, start, end);
    }
}

void HexFile::saveRange(FILE *file, Address start, Address end) const
{
    Address current = start;
    Address currentSegment = ~((Address)0);
    bool needsSegments = (_programEnd >= 0x10000 ||
                          _configEnd >= 0x10000 ||
                          _dataEnd >= 0x10000);
    int format;
    if (_format == FORMAT_AUTO && _programBits == 16)
        format = FORMAT_IHX32;
    else
        format = _format;
    if (format == FORMAT_IHX8M)
        needsSegments = false;
    char buffer[64];
    while (current <= end) {
        Address byteAddress = current * 2;
        Address segment = byteAddress >> 16;
        if (needsSegments && segment != currentSegment) {
            if (segment < 16 && _format != FORMAT_IHX32) {
                // Over 64K boundary: output an Extended Segment Address Record.
                currentSegment = segment;
                segment <<= 12;
                buffer[0] = (char)0x02;
                buffer[1] = (char)0x00;
                buffer[2] = (char)0x00;
                buffer[3] = (char)0x02;
                buffer[4] = (char)(segment >> 8);
                buffer[5] = (char)segment;
                writeLine(file, buffer, 6);
            } else {
                // Over 1M boundary: output an Extended Linear Address Record.
                currentSegment = segment;
                buffer[0] = (char)0x02;
                buffer[1] = (char)0x00;
                buffer[2] = (char)0x00;
                buffer[3] = (char)0x04;
                buffer[4] = (char)(segment >> 8);
                buffer[5] = (char)segment;
                writeLine(file, buffer, 6);
            }
        }
        if ((current + 7) <= end)
            buffer[0] = (char)0x10;
        else
            buffer[0] = (char)((end - current + 1) * 2);
        buffer[1] = (char)(byteAddress >> 8);
        buffer[2] = (char)byteAddress;
        buffer[3] = (char)0x00;
        int len = 4;
        while (current <= end && len < (4 + 16)) {
            Word value = word(current);
            buffer[len++] = (char)value;
            buffer[len++] = (char)(value >> 8);
            ++current;
        }
        writeLine(file, buffer, len);
    }
}

void HexFile::writeLine(FILE *file, const char *buffer, int len)
{
    static const char hexchars[] = "0123456789ABCDEF";
    int checksum = 0;
    int index;
    for (index = 0; index < len; ++index)
        checksum += (buffer[index] & 0xFF);
    checksum = (((checksum & 0xFF) ^ 0xFF) + 1) & 0xFF;
    putc(':', file);
    for (index = 0; index < len; ++index) {
        int value = buffer[index];
        putc(hexchars[(value >> 4) & 0x0F], file);
        putc(hexchars[value & 0x0F], file);
    }
    putc(hexchars[(checksum >> 4) & 0x0F], file);
    putc(hexchars[checksum & 0x0F], file);
    putc('\n', file);
}
