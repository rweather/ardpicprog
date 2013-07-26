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

#define __PROG_TYPES_COMPAT__
#include <avr/pgmspace.h>       // For PROGMEM

// Pin mappings for the PIC programming shield.
#define PIN_MCLR        A1      // 0: MCLR is VPP voltage, 1: Reset PIC
#define PIN_ACTIVITY    A5      // LED that indicates read/write activity
#define PIN_VDD         2       // Controls the power to the PIC
#define PIN_CLOCK       4       // Clock pin
#define PIN_DATA        7       // Data pin

#define MCLR_RESET      HIGH    // PIN_MCLR state to reset the PIC
#define MCLR_VPP        LOW     // PIN_MCLR state to apply 13v to MCLR/VPP pin

// All delays are in microseconds.
#define DELAY_SETTLE    50      // Delay for lines to settle for reset
#define DELAY_TPPDP     5       // Hold time after raising MCLR
#define DELAY_THLD0     5       // Hold time after raising VDD
#define DELAY_TSET1     1       // Data in setup time before lowering clock
#define DELAY_THLD1     1       // Data in hold time after lowering clock
#define DELAY_TDLY2     1       // Delay between commands or data
#define DELAY_TDLY3     1       // Delay until data bit read will be valid
#define DELAY_TPROG     4000    // Time for a program memory write to complete
#define DELAY_TDPROG    6000    // Time for a data memory write to complete
#define DELAY_TERA      6000    // Time for a word erase to complete
#define DELAY_TPROG5    1000    // Time for program write on FLASH5 systems
#define DELAY_TFULLERA  50000   // Time for a full chip erase
#define DELAY_TFULL84   20000   // Intermediate wait for PIC16F84/PIC16F84A

// Commands that may be sent to the device.
#define CMD_LOAD_CONFIG         0x00    // Load (write) to config memory
#define CMD_LOAD_PROGRAM_MEMORY 0x02    // Load to program memory
#define CMD_LOAD_DATA_MEMORY    0x03    // Load to data memory
#define CMD_INCREMENT_ADDRESS   0x06    // Increment the PC
#define CMD_READ_PROGRAM_MEMORY 0x04    // Read from program memory
#define CMD_READ_DATA_MEMORY    0x05    // Read from data memory
#define CMD_BEGIN_PROGRAM       0x08    // Begin programming with erase cycle
#define CMD_BEGIN_PROGRAM_ONLY  0x18    // Begin programming only cycle
#define CMD_END_PROGRAM_ONLY    0x17    // End programming only cycle
#define CMD_BULK_ERASE_PROGRAM  0x09    // Bulk erase program memory
#define CMD_BULK_ERASE_DATA     0x0B    // Bulk erase data memory
#define CMD_CHIP_ERASE          0x1F    // Erase the entire chip

// States this application may be in.
#define STATE_IDLE      0       // Idle, device is held in the reset state
#define STATE_PROGRAM   1       // Active, reading and writing program memory
#define STATE_CONFIG    2       // Active, reading and writing config memory
int state = STATE_IDLE;

// Flash types.  Uses a similar naming system to picprog.
#define EEPROM          0
#define FLASH           1
#define FLASH4          4
#define FLASH5          5

unsigned long pc = 0;           // Current program counter.

// Flat address ranges for the various memory spaces.  Defaults to the values
// for the PIC16F628A.  "DEVICE" command updates to the correct values later.
unsigned long programEnd    = 0x07FF;
unsigned long configStart   = 0x2000;
unsigned long configEnd     = 0x2007;
unsigned long dataStart     = 0x2100;
unsigned long dataEnd       = 0x217F;
unsigned long reservedStart = 0x0800;
unsigned long reservedEnd   = 0x07FF;
unsigned int  configSave    = 0x0000;
byte progFlashType          = FLASH4;
byte dataFlashType          = EEPROM;

// Device names, forced out into PROGMEM.
const char s_pic12f629[]  PROGMEM = "pic12f629";
const char s_pic12f675[]  PROGMEM = "pic12f675";
const char s_pic16f630[]  PROGMEM = "pic16f630";
const char s_pic16f676[]  PROGMEM = "pic16f676";
const char s_pic16f84[]   PROGMEM = "pic16f84";
const char s_pic16f84a[]  PROGMEM = "pic16f84a";
const char s_pic16f87[]   PROGMEM = "pic16f87";
const char s_pic16f88[]   PROGMEM = "pic16f88";
const char s_pic16f627[]  PROGMEM = "pic16f627";
const char s_pic16f627a[] PROGMEM = "pic16f627a";
const char s_pic16f628[]  PROGMEM = "pic16f628";
const char s_pic16f628a[] PROGMEM = "pic16f628a";
const char s_pic16f648a[] PROGMEM = "pic16f648a";
const char s_pic16f882[]  PROGMEM = "pic16f882";
const char s_pic16f883[]  PROGMEM = "pic16f883";
const char s_pic16f884[]  PROGMEM = "pic16f884";
const char s_pic16f886[]  PROGMEM = "pic16f886";
const char s_pic16f887[]  PROGMEM = "pic16f887";

// List of devices that are currently supported and their properties.
// Note: most of these are based on published information and have not
// been tested by the author.  Patches welcome to improve the list.
struct deviceInfo
{
    const prog_char *name;      // User-readable name of the device.
    prog_int16_t deviceId;      // Device ID for the PIC (-1 if no id).
    prog_uint32_t programSize;  // Size of program memory (words).
    prog_uint32_t configStart;  // Flat address start of configuration memory.
    prog_uint32_t dataStart;    // Flat address start of EEPROM data memory.
    prog_uint16_t configSize;   // Number of configuration words.
    prog_uint16_t dataSize;     // Size of EEPROM data memory (bytes).
    prog_uint16_t reservedWords;// Reserved program words (e.g. for OSCCAL).
    prog_uint16_t configSave;   // Bits in config word to be saved.
    prog_uint8_t progFlashType; // Type of flash for program memory.
    prog_uint8_t dataFlashType; // Type of flash for data memory.

};
struct deviceInfo const devices[] PROGMEM = {
    // http://ww1.microchip.com/downloads/en/DeviceDoc/41191D.pdf
    {s_pic12f629,  0x0F80, 1024, 0x2000, 0x2100, 8, 128, 1, 0x3000, FLASH4, EEPROM},
    {s_pic12f675,  0x0FC0, 1024, 0x2000, 0x2100, 8, 128, 1, 0x3000, FLASH4, EEPROM},
    {s_pic16f630,  0x10C0, 1024, 0x2000, 0x2100, 8, 128, 1, 0x3000, FLASH4, EEPROM},
    {s_pic16f676,  0x10E0, 1024, 0x2000, 0x2100, 8, 128, 1, 0x3000, FLASH4, EEPROM},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/30262e.pdf
    {s_pic16f84,   -1,     1024, 0x2000, 0x2100, 8,  64, 0, 0, FLASH,  EEPROM},
    {s_pic16f84a,  0x0560, 1024, 0x2000, 0x2100, 8,  64, 0, 0, FLASH,  EEPROM},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/39607c.pdf
    {s_pic16f87,   0x0720, 4096, 0x2000, 0x2100, 9, 256, 0, 0, FLASH5, EEPROM},
    {s_pic16f88,   0x0760, 4096, 0x2000, 0x2100, 9, 256, 0, 0, FLASH5, EEPROM},

    // 627/628:  http://ww1.microchip.com/downloads/en/DeviceDoc/30034d.pdf
    // A series: http://ww1.microchip.com/downloads/en/DeviceDoc/41196g.pdf
    {s_pic16f627,  0x07A0, 1024, 0x2000, 0x2100, 8, 128, 0, 0, FLASH,  EEPROM},
    {s_pic16f627a, 0x1040, 1024, 0x2000, 0x2100, 8, 128, 0, 0, FLASH4, EEPROM},
    {s_pic16f628,  0x07C0, 2048, 0x2000, 0x2100, 8, 128, 0, 0, FLASH,  EEPROM},
    {s_pic16f628a, 0x1060, 2048, 0x2000, 0x2100, 8, 128, 0, 0, FLASH4, EEPROM},
    {s_pic16f648a, 0x1100, 4096, 0x2000, 0x2100, 8, 256, 0, 0, FLASH4, EEPROM},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/41287D.pdf
    {s_pic16f882,  0x2000, 2048, 0x2000, 0x2100, 9, 128, 0, 0, FLASH4, EEPROM},
    {s_pic16f883,  0x2020, 4096, 0x2000, 0x2100, 9, 256, 0, 0, FLASH4, EEPROM},
    {s_pic16f884,  0x2040, 4096, 0x2000, 0x2100, 9, 256, 0, 0, FLASH4, EEPROM},
    {s_pic16f886,  0x2060, 8192, 0x2000, 0x2100, 9, 256, 0, 0, FLASH4, EEPROM},
    {s_pic16f887,  0x2080, 8192, 0x2000, 0x2100, 9, 256, 0, 0, FLASH4, EEPROM},

    {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
};

// Buffer for command-line character input and READBIN data packets.
#define BINARY_TRANSFER_MAX 64
#define BUFFER_MAX (BINARY_TRANSFER_MAX + 1)
char buffer[BUFFER_MAX];
int buflen = 0;

unsigned long lastActive = 0;

void setup()
{
    // Need a serial link to the host.
    Serial.begin(9600);

    // Hold the PIC in the powered down/reset state until we are ready for it.
    pinMode(PIN_MCLR, OUTPUT);
    pinMode(PIN_VDD, OUTPUT);
    digitalWrite(PIN_MCLR, MCLR_RESET);
    digitalWrite(PIN_VDD, LOW);

    // Clock and data are floating until the first PIC command.
    pinMode(PIN_CLOCK, INPUT);
    pinMode(PIN_DATA, INPUT);

    // Turn off the activity LED initially.
    pinMode(PIN_ACTIVITY, OUTPUT);
    digitalWrite(PIN_ACTIVITY, LOW);
}

void loop()
{
    if (Serial.available()) {
        // Process serial input for commands from the host.
        int ch = Serial.read();
        if (ch == 0x0A || ch == 0x0D) {
            // End of the current command.  Blank lines are ignored.
            if (buflen > 0) {
                buffer[buflen] = '\0';
                buflen = 0;
                digitalWrite(PIN_ACTIVITY, HIGH);   // Turn on activity LED.
                processCommand(buffer);
                digitalWrite(PIN_ACTIVITY, LOW);    // Turn off activity LED.
            }
        } else if (ch == 0x08) {
            // Backspace over the last character.
            if (buflen > 0)
                --buflen;
        } else if (buflen < (BUFFER_MAX - 1)) {
            // Add the character to the buffer after forcing to upper case.
            if (ch >= 'a' && ch <= 'z')
                buffer[buflen++] = ch - 'a' + 'A';
            else
                buffer[buflen++] = ch;
        }
        lastActive = millis();
    } else if (state != STATE_IDLE) {
        // Power off the programming socket if no activity for 2 seconds.
        // Normally the host will issue the "PWROFF" command, but if we are
        // operating in interactive mode or the host has crashed, then this
        // timeout will ensure that the system eventually enters safe mode.
        if ((millis() - lastActive) >= 2000)
            exitProgramMode();
    }
}

void printHex1(unsigned int value)
{
    if (value >= 10)
        Serial.print((char)('A' + value - 10));
    else
        Serial.print((char)('0' + value));
}

void printHex4(unsigned int word)
{
    printHex1((word >> 12) & 0x0F);
    printHex1((word >> 8) & 0x0F);
    printHex1((word >> 4) & 0x0F);
    printHex1(word & 0x0F);
}

void printHex8(unsigned long word)
{
    unsigned int upper = (unsigned int)(word >> 16);
    if (upper)
        printHex4(upper);
    printHex4((unsigned int)word);
}

void printProgString(const prog_char *str)
{
    for (;;) {
        char ch = (char)(pgm_read_byte(str));
        if (ch == '\0')
            break;
        Serial.print(ch);
        ++str;
    }
}

// PROGRAM_PIC_VERSION command.
void cmdVersion(const char *args)
{
    Serial.println("ProgramPIC 1.0");
}

// Initialize device properties from the "devices" list and
// print them to the serial port.  Note: "dev" is in PROGMEM.
void initDevice(const struct deviceInfo *dev)
{
    // Update the global device details.
    programEnd = pgm_read_dword(&(dev->programSize)) - 1;
    configStart = pgm_read_dword(&(dev->configStart));
    configEnd = configStart + pgm_read_word(&(dev->configSize)) - 1;
    dataStart = pgm_read_dword(&(dev->dataStart));
    dataEnd = dataStart + pgm_read_word(&(dev->dataSize)) - 1;
    reservedStart = programEnd - pgm_read_word(&(dev->reservedWords)) + 1;
    reservedEnd = programEnd;
    configSave = pgm_read_word(&(dev->configSave));
    progFlashType = pgm_read_byte(&(dev->progFlashType));
    dataFlashType = pgm_read_byte(&(dev->dataFlashType));

    // Print the extra device information.
    Serial.print("DeviceName: ");
    printProgString((const prog_char *)(pgm_read_word(&(dev->name))));
    Serial.println();
    Serial.print("ProgramRange: 0000-");
    printHex8(programEnd);
    Serial.println();
    Serial.print("ConfigRange: ");
    printHex8(configStart);
    Serial.print('-');
    printHex8(configEnd);
    Serial.println();
    if (configSave != 0) {
        Serial.print("ConfigSave: ");
        printHex4(configSave);
        Serial.println();
    }
    Serial.print("DataRange: ");
    printHex8(dataStart);
    Serial.print('-');
    printHex8(dataEnd);
    Serial.println();
    if (reservedStart <= reservedEnd) {
        Serial.print("ReservedRange: ");
        printHex8(reservedStart);
        Serial.print('-');
        printHex8(reservedEnd);
        Serial.println();
    }
}

// Offsets of interesting config locations that contain device information.
#define DEV_USERID0         0
#define DEV_USERID1         1
#define DEV_USERID2         2
#define DEV_USERID3         3
#define DEV_ID              6
#define DEV_CONFIG_WORD     7

// DEVICE command.
void cmdDevice(const char *args)
{
    // Make sure the device is reset before we start.
    exitProgramMode();

    // Read identifiers and configuration words from config memory.
    unsigned int userid0 = readConfigWord(DEV_USERID0);
    unsigned int userid1 = readConfigWord(DEV_USERID1);
    unsigned int userid2 = readConfigWord(DEV_USERID2);
    unsigned int userid3 = readConfigWord(DEV_USERID3);
    unsigned int deviceId = readConfigWord(DEV_ID);
    unsigned int configWord = readConfigWord(DEV_CONFIG_WORD);

    // If the device ID is all-zeroes or all-ones, then it could mean
    // one of the following:
    //
    // 1. There is no PIC in the programming socket.
    // 2. The VPP programming voltage is not available.
    // 3. Code protection is enabled and the PIC is unreadable.
    // 4. The PIC is an older model with no device identifier.
    //
    // Case 4 is the interesting one.  We look for any word in configuration
    // memory or the first 16 words of program memory that is non-zero.
    // If we find a non-zero word, we assume that we have a PIC but we
    // cannot detect what type it is.
    if (deviceId == 0 || deviceId == 0x3FFF) {
        unsigned int word = userid0 | userid1 | userid2 | userid3 | configWord;
        unsigned int addr = 0;
        while (!word && addr < 16) {
            word |= readWord(addr);
            ++addr;
        }
        if (!word) {
            Serial.println("ERROR");
            exitProgramMode();
            return;
        }
        deviceId = 0;
    }

    Serial.println("OK");

    Serial.print("DeviceID: ");
    printHex4(deviceId);
    Serial.println();

    // Find the device in the built-in list if we have details for it.
    int index = 0;
    for (;;) {
        const prog_char *name = (const prog_char *)
            (pgm_read_word(&(devices[index].name)));
        if (!name) {
            index = -1;
            break;
        }
        int id = pgm_read_word(&(devices[index].deviceId));
        if (id == (deviceId & 0xFFE0))
            break;
        ++index;
    }
    if (index >= 0) {
        initDevice(&(devices[index]));
    } else {
        // Reset the global parameters to their defaults.  A separate
        // "SETDEVICE" command will be needed to set the correct values.
        programEnd    = 0x07FF;
        configStart   = 0x2000;
        configEnd     = 0x2007;
        dataStart     = 0x2100;
        dataEnd       = 0x217F;
        reservedStart = 0x0800;
        reservedEnd   = 0x07FF;
        configSave    = 0x0000;
        progFlashType = FLASH4;
        dataFlashType = EEPROM;
    }

    Serial.print("ConfigWord: ");
    printHex4(configWord);
    Serial.println();

    Serial.println(".");

    // Don't need programming mode once the details have been read.
    exitProgramMode();
}

// DEVICES command.
void cmdDevices(const char *args)
{
    Serial.println("OK");
    int index = 0;
    for (;;) {
        const prog_char *name = (const prog_char *)
            (pgm_read_word(&(devices[index].name)));
        if (!name)
            break;
        if (index > 0) {
            Serial.print(',');
            if ((index % 6) == 0)
                Serial.println();
            else
                Serial.print(' ');
        }
        printProgString(name);
        int id = (int)(pgm_read_word(&(devices[index].deviceId)));
        if (id != -1)
            Serial.print('*');
        ++index;
    }
    Serial.println();
    Serial.println(".");
}

// SETDEVICE command.
void cmdSetDevice(const char *args)
{
    // Extract the name of the device from the command arguments.
    int len = 0;
    for (;;) {
        char ch = args[len];
        if (ch == '\0' || ch == ' ' || ch == '\t')
            break;
        ++len;
    }

    // Look for the name in the devices list.
    int index = 0;
    for (;;) {
        const prog_char *name = (const prog_char *)
            (pgm_read_word(&(devices[index].name)));
        if (!name)
            break;
        if (matchString(name, args, len)) {
            Serial.println("OK");
            initDevice(&(devices[index]));
            Serial.println(".");
            exitProgramMode(); // Force a reset upon the next command.
            return;
        }
        ++index;
    }
    Serial.println("ERROR");
}

int parseHex(const char *args, unsigned long *value)
{
    int size = 0;
    *value = 0;
    for (;;) {
        char ch = *args;
        if (ch >= '0' && ch <= '9')
            *value = (*value << 4) | (ch - '0');
        else if (ch >= 'A' && ch <= 'F')
            *value = (*value << 4) | (ch - 'A' + 10);
        else if (ch >= 'a' && ch <= 'f')
            *value = (*value << 4) | (ch - 'a' + 10);
        else
            break;
        ++size;
        ++args;
    }
    if (*args != '\0' && *args != '-' && *args != ' ' && *args != '\t')
        return 0;
    return size;
}

// Parse a range of addresses of the form START or START-END.
bool parseRange(const char *args, unsigned long *start, unsigned long *end)
{
    int size = parseHex(args, start);
    if (!size)
        return false;
    args += size;
    while (*args == ' ' || *args == '\t')
        ++args;
    if (*args != '-') {
        *end = *start;
        return true;
    }
    ++args;
    while (*args == ' ' || *args == '\t')
        ++args;
    if (!parseHex(args, end))
        return false;
    return *end >= *start;
}

bool parseCheckedRange(const char *args, unsigned long *start, unsigned long *end)
{
    // Parse the basic values and make sure that start <= end.
    if (!parseRange(args, start, end))
        return false;

    // Check that both start and end are within the same memory area
    // and within the bounds of that memory area.
    if (*start <= programEnd) {
        if (*end > programEnd)
            return false;
    } else if (*start >= configStart && *start <= configEnd) {
        if (*end < configStart || *end > configEnd)
            return false;
    } else if (*start >= dataStart && *start <= dataEnd) {
        if (*end < dataStart || *end > dataEnd)
            return false;
    } else {
        return false;
    }
    return true;
}

// READ command.
void cmdRead(const char *args)
{
    unsigned long start;
    unsigned long end;
    if (!parseCheckedRange(args, &start, &end)) {
        Serial.println("ERROR");
        return;
    }
    Serial.println("OK");
    int count = 0;
    bool activity = true;
    while (start <= end) {
        unsigned int word = readWord(start);
        if (count > 0) {
            if ((count % 8) == 0)
                Serial.println();
            else
                Serial.print(' ');
        }
        printHex4(word);
        ++start;
        ++count;
        if ((count % 32) == 0) {
            // Toggle the activity LED to make it blink during long reads.
            activity = !activity;
            if (activity)
                digitalWrite(PIN_ACTIVITY, HIGH);
            else
                digitalWrite(PIN_ACTIVITY, LOW);
        }
    }
    Serial.println();
    Serial.println(".");
}

// READBIN command.
void cmdReadBinary(const char *args)
{
    unsigned long start;
    unsigned long end;
    if (!parseCheckedRange(args, &start, &end)) {
        Serial.println("ERROR");
        return;
    }
    Serial.println("OK");
    int count = 0;
    bool activity = true;
    size_t offset = 0;
    while (start <= end) {
        unsigned int word = readWord(start);
        buffer[++offset] = (char)word;
        buffer[++offset] = (char)(word >> 8);
        if (offset >= BINARY_TRANSFER_MAX) {
            // Buffer is full - flush it to the host.
            buffer[0] = (char)offset;
            Serial.write((const uint8_t *)buffer, offset + 1);
            offset = 0;
        }
        ++start;
        ++count;
        if ((count % 64) == 0) {
            // Toggle the activity LED to make it blink during long reads.
            activity = !activity;
            if (activity)
                digitalWrite(PIN_ACTIVITY, HIGH);
            else
                digitalWrite(PIN_ACTIVITY, LOW);
        }
    }
    if (offset > 0) {
        // Flush the final packet before the terminator.
        buffer[0] = (char)offset;
        Serial.write((const uint8_t *)buffer, offset + 1);
    }
    // Write the terminator (a zero-length packet).
    Serial.write((uint8_t)0x00);
}

const char s_force[] PROGMEM = "FORCE";

// WRITE command.
void cmdWrite(const char *args)
{
    unsigned long addr;
    unsigned long limit;
    unsigned long value;
    int size;

    // Was the "FORCE" option given?
    int len = 0;
    while (args[len] != '\0' && args[len] != ' ' && args[len] != '\t')
        ++len;
    bool force = matchString(s_force, args, len);
    if (force) {
        args += len;
        while (*args == ' ' || *args == '\t')
            ++args;
    }

    size = parseHex(args, &addr);
    if (!size) {
        Serial.println("ERROR");
        return;
    }
    args += size;
    if (addr <= programEnd) {
        limit = programEnd;
    } else if (addr >= configStart && addr <= configEnd) {
        limit = configEnd;
    } else if (addr >= dataStart && addr <= dataEnd) {
        limit = dataEnd;
    } else {
        // Address is not within one of the valid ranges.
        Serial.println("ERROR");
        return;
    }
    int count = 0;
    for (;;) {
        while (*args == ' ' || *args == '\t')
            ++args;
        if (*args == '\0')
            break;
        if (*args == '-') {
            Serial.println("ERROR");
            return;
        }
        size = parseHex(args, &value);
        if (!size) {
            Serial.println("ERROR");
            return;
        }
        args += size;
        if (addr > limit) {
            // We've reached the limit of this memory area, so fail.
            Serial.println("ERROR");
            return;
        }
        if (!force) {
            if (!writeWord(addr, (unsigned int)value)) {
                // The actual write to the device failed.
                Serial.println("ERROR");
                return;
            }
        } else {
            if (!writeWordForced(addr, (unsigned int)value)) {
                // The actual write to the device failed.
                Serial.println("ERROR");
                return;
            }
        }
        ++addr;
        ++count;
    }
    if (!count) {
        // Missing word argument.
        Serial.println("ERROR");
    } else {
        Serial.println("OK");
    }
}

// Blocking serial read for use by WRITEBIN.
int readBlocking()
{
    while (!Serial.available())
        ;   // Do nothing.
    return Serial.read();
}

// WRITEBIN command.
void cmdWriteBinary(const char *args)
{
    unsigned long addr;
    unsigned long limit;
    int size;

    // Was the "FORCE" option given?
    int len = 0;
    while (args[len] != '\0' && args[len] != ' ' && args[len] != '\t')
        ++len;
    bool force = matchString(s_force, args, len);
    if (force) {
        args += len;
        while (*args == ' ' || *args == '\t')
            ++args;
    }

    size = parseHex(args, &addr);
    if (!size) {
        Serial.println("ERROR");
        return;
    }
    args += size;
    if (addr <= programEnd) {
        limit = programEnd;
    } else if (addr >= configStart && addr <= configEnd) {
        limit = configEnd;
    } else if (addr >= dataStart && addr <= dataEnd) {
        limit = dataEnd;
    } else {
        // Address is not within one of the valid ranges.
        Serial.println("ERROR");
        return;
    }
    Serial.println("OK");
    int count = 0;
    bool activity = true;
    for (;;) {
        // Read in the next binary packet.
        int len = readBlocking();
        while (len == 0x0A && count == 0) {
            // Skip 0x0A bytes before the first packet as they are
            // probably part of a CRLF pair rather than a packet length.
            len = readBlocking();
        }

        // Stop if we have a zero packet length - end of upload.
        if (!len)
            break;

        // Read the contents of the packet from the serial input stream.
        int offset = 0;
        while (offset < len) {
            if (offset < BINARY_TRANSFER_MAX) {
                buffer[offset++] = (char)readBlocking();
            } else {
                readBlocking();     // Packet is too big - discard extra bytes.
                ++offset;
            }
        }

        // Write the words to memory.
        for (int posn = 0; posn < (len - 1); posn += 2) {
            if (addr > limit) {
                // We've reached the limit of this memory area, so fail.
                Serial.println("ERROR");
                return;
            }
            unsigned int value =
                (((unsigned int)buffer[posn]) & 0xFF) |
                ((((unsigned int)buffer[posn + 1]) & 0xFF) << 8);
            if (!force) {
                if (!writeWord(addr, (unsigned int)value)) {
                    // The actual write to the device failed.
                    Serial.println("ERROR");
                    return;
                }
            } else {
                if (!writeWordForced(addr, (unsigned int)value)) {
                    // The actual write to the device failed.
                    Serial.println("ERROR");
                    return;
                }
            }
            ++addr;
            ++count;
            if ((count % 24) == 0) {
                // Toggle the activity LED to make it blink during long writes.
                activity = !activity;
                if (activity)
                    digitalWrite(PIN_ACTIVITY, HIGH);
                else
                    digitalWrite(PIN_ACTIVITY, LOW);
            }
        }

        // All words in this packet have been written successfully.
        Serial.println("OK");
    }
    Serial.println("OK");
}

const char s_noPreserve[] PROGMEM = "NOPRESERVE";

// ERASE command.
void cmdErase(const char *args)
{
    // Was the "NOPRESERVE" option given?
    int len = 0;
    while (args[len] != '\0' && args[len] != ' ' && args[len] != '\t')
        ++len;
    bool preserve = !matchString(s_noPreserve, args, len);

    // Preserve reserved words if necessary.
    unsigned int *reserved = 0;
    unsigned int configWord = 0x3FFF;
    if (preserve && reservedStart <= reservedEnd) {
        size_t size = ((size_t)(reservedEnd - reservedStart + 1))
            * sizeof(unsigned int);
        reserved = (unsigned int *)malloc(size);
        if (reserved) {
            unsigned long addr = reservedStart;
            int offset = 0;
            while (addr <= reservedEnd) {
                reserved[offset] = readWord(addr);
                ++addr;
                ++offset;
            }
        } else {
            // If we cannot preserve the reserved words, then abort now.
            Serial.println("ERROR");
            return;
        }
    }
    if (configSave != 0 && preserve) {
        // Some of the bits in the configuration word must also be saved.
        configWord &= ~configSave;
        configWord |= readWord(configStart + DEV_CONFIG_WORD) & configSave;
    }

    // Perform the memory type specific erase sequence.
    switch (progFlashType) {
    case FLASH4:
        setErasePC();
        sendSimpleCommand(CMD_BULK_ERASE_PROGRAM);
        delayMicroseconds(DELAY_TERA);
        sendSimpleCommand(CMD_BULK_ERASE_DATA);
        break;
    case FLASH5:
        setErasePC();
        sendSimpleCommand(CMD_CHIP_ERASE);
        break;
    default:
        // Details for disabling code protection and erasing all memory
        // for PIC16F84/PIC16F84A comes from this doc, section 4.1:
        // http://ww1.microchip.com/downloads/en/DeviceDoc/30262e.pdf
        setErasePC();
        for (int count = 0; count < 7; ++count)
            sendSimpleCommand(CMD_INCREMENT_ADDRESS); // Advance to 0x2007
        sendSimpleCommand(0x01);    // Command 1
        sendSimpleCommand(0x07);    // Command 7
        sendSimpleCommand(CMD_BEGIN_PROGRAM);
        delayMicroseconds(DELAY_TFULL84);
        sendSimpleCommand(0x01);    // Command 1
        sendSimpleCommand(0x07);    // Command 7

        // Some FLASH devices need the data memory to be erased separately.
        sendWriteCommand(CMD_LOAD_DATA_MEMORY, 0x3FFF);
        sendSimpleCommand(CMD_BULK_ERASE_DATA);
        sendSimpleCommand(CMD_BEGIN_PROGRAM);
        break;
    }

    // Wait until the chip is fully erased.
    delayMicroseconds(DELAY_TFULLERA);

    // Force the device to reset after it has been erased.
    exitProgramMode();
    enterProgramMode();

    // Write the reserved words back to program memory.
    if (reserved) {
        unsigned long addr = reservedStart;
        int offset = 0;
        bool ok = true;
        while (addr <= reservedEnd) {
            if (!writeWord(addr, reserved[offset]))
                ok = false;
            ++addr;
            ++offset;
        }
        free(reserved);
        if (!ok) {
            // Reserved words did not read back correctly.
            Serial.println("ERROR");
            return;
        }
    }

    // Forcibly write 0x3FFF over the configuration words as erase
    // sometimes won't reset the words (e.g. PIC16F628A).  If the
    // write fails, then leave the words as-is - don't report the failure.
    for (unsigned long configAddr = configStart + DEV_CONFIG_WORD;
            configAddr <= configEnd; ++configAddr)
        writeWordForced(configAddr, configWord);

    // Done.
    Serial.println("OK");
}

// PWROFF command.
void cmdPowerOff(const char *args)
{
    exitProgramMode();
    Serial.println("OK");
}

// List of all commands that are understood by the programmer.
typedef void (*commandFunc)(const char *args);
typedef struct
{
    const prog_char *name;
    commandFunc func;
    const prog_char *desc;
    const prog_char *args;
} command_t;
const char s_cmdRead[] PROGMEM = "READ";
const char s_cmdReadDesc[] PROGMEM =
    "Reads program and data words from device memory (text)";
const char s_cmdReadArgs[] PROGMEM = "STARTADDR[-ENDADDR]";
const char s_cmdReadBinary[] PROGMEM = "READBIN";
const char s_cmdReadBinaryDesc[] PROGMEM =
    "Reads program and data words from device memory (binary)";
const char s_cmdWrite[] PROGMEM = "WRITE";
const char s_cmdWriteDesc[] PROGMEM =
    "Writes program and data words to device memory (text)";
const char s_cmdWriteArgs[] PROGMEM = "STARTADDR WORD [WORD ...]";
const char s_cmdWriteBinary[] PROGMEM = "WRITEBIN";
const char s_cmdWriteBinaryDesc[] PROGMEM =
    "Writes program and data words to device memory (binary)";
const char s_cmdWriteBinaryArgs[] PROGMEM = "STARTADDR";
const char s_cmdErase[] PROGMEM = "ERASE";
const char s_cmdEraseDesc[] PROGMEM =
    "Erases the contents of program, configuration, and data memory";
const char s_cmdDevice[] PROGMEM = "DEVICE";
const char s_cmdDeviceDesc[] PROGMEM =
    "Probes the device and returns information about it";
const char s_cmdDevices[] PROGMEM = "DEVICES";
const char s_cmdDevicesDesc[] PROGMEM =
    "Returns a list of all supported device types";
const char s_cmdSetDevice[] PROGMEM = "SETDEVICE";
const char s_cmdSetDeviceDesc[] PROGMEM =
    "Sets a specific device type manually";
const char s_cmdSetDeviceArgs[] PROGMEM = "DEVTYPE";
const char s_cmdPowerOff[] PROGMEM = "PWROFF";
const char s_cmdPowerOffDesc[] PROGMEM =
    "Powers off the device in the programming socket";
const char s_cmdVersion[] PROGMEM = "PROGRAM_PIC_VERSION";
const char s_cmdVersionDesc[] PROGMEM =
    "Prints the version of ProgramPIC";
const char s_cmdHelp[] PROGMEM = "HELP";
const char s_cmdHelpDesc[] PROGMEM =
    "Prints this help message";
const command_t commands[] PROGMEM = {
    {s_cmdRead, cmdRead, s_cmdReadDesc, s_cmdReadArgs},
    {s_cmdReadBinary, cmdReadBinary, s_cmdReadBinaryDesc, s_cmdReadArgs},
    {s_cmdWrite, cmdWrite, s_cmdWriteDesc, s_cmdWriteArgs},
    {s_cmdWriteBinary, cmdWriteBinary, s_cmdWriteBinaryDesc, s_cmdWriteBinaryArgs},
    {s_cmdErase, cmdErase, s_cmdEraseDesc, 0},
    {s_cmdDevice, cmdDevice, s_cmdDeviceDesc, 0},
    {s_cmdDevices, cmdDevices, s_cmdDevicesDesc, 0},
    {s_cmdSetDevice, cmdSetDevice, s_cmdSetDeviceDesc, s_cmdSetDeviceArgs},
    {s_cmdPowerOff, cmdPowerOff, s_cmdPowerOffDesc, 0},
    {s_cmdVersion, cmdVersion, s_cmdVersionDesc, 0},
    {s_cmdHelp, cmdHelp, s_cmdHelpDesc, 0},
    {0, 0}
};

// "HELP" command.
void cmdHelp(const char *args)
{
    Serial.println("OK");
    int index = 0;
    for (;;) {
        const prog_char *name = (const prog_char *)
            (pgm_read_word(&(commands[index].name)));
        if (!name)
            break;
        const prog_char *desc = (const prog_char *)
            (pgm_read_word(&(commands[index].desc)));
        const prog_char *args = (const prog_char *)
            (pgm_read_word(&(commands[index].args)));
        printProgString(name);
        if (args) {
            Serial.print(' ');
            printProgString(args);
        }
        Serial.println();
        Serial.print("    ");
        printProgString(desc);
        Serial.println();
        ++index;
    }
    Serial.println(".");
}

// Match a data-space string where the name comes from PROGMEM.
bool matchString(const prog_char *name, const char *str, int len)
{
    for (;;) {
        char ch1 = (char)(pgm_read_byte(name));
        if (ch1 == '\0')
            return len == 0;
        else if (len == 0)
            break;
        if (ch1 >= 'a' && ch1 <= 'z')
            ch1 = ch1 - 'a' + 'A';
        char ch2 = *str;
        if (ch2 >= 'a' && ch2 <= 'z')
            ch2 = ch2 - 'a' + 'A';
        if (ch1 != ch2)
            break;
        ++name;
        ++str;
        --len;
    }
    return false;
}

// Process commands from the host.
void processCommand(const char *buf)
{
    // Skip white space at the start of the command.
    while (*buf == ' ' || *buf == '\t')
        ++buf;
    if (*buf == '\0')
        return;     // Ignore blank lines.

    // Extract the command portion of the line.
    const char *cmd = buf;
    int len = 0;
    for (;;) {
        char ch = *buf;
        if (ch == '\0' || ch == ' ' || ch == '\t')
            break;
        ++buf;
        ++len;
    }

    // Skip white space after the command name and before the arguments.
    while (*buf == ' ' || *buf == '\t')
        ++buf;

    // Find the command and execute it.
    int index = 0;
    for (;;) {
        const prog_char *name = (const prog_char *)
            (pgm_read_word(&(commands[index].name)));
        if (!name)
            break;
        if (matchString(name, cmd, len)) {
            commandFunc func =
                (commandFunc)(pgm_read_word(&(commands[index].func)));
            (*func)(buf);
            return;
        }
        ++index;
    }

    // Unknown command.
    Serial.println("NOTSUPPORTED");
}

// Enter high voltage programming mode.
void enterProgramMode()
{
    // Bail out if already in programming mode.
    if (state != STATE_IDLE)
        return;

    // Lower MCLR, VDD, DATA, and CLOCK initially.  This will put the
    // PIC into the powered-off, reset state just in case.
    digitalWrite(PIN_MCLR, MCLR_RESET);
    digitalWrite(PIN_VDD, LOW);
    digitalWrite(PIN_DATA, LOW);
    digitalWrite(PIN_CLOCK, LOW);

    // Wait for the lines to settle.
    delayMicroseconds(DELAY_SETTLE);

    // Switch DATA and CLOCK into outputs.
    pinMode(PIN_DATA, OUTPUT);
    pinMode(PIN_CLOCK, OUTPUT);

    // Raise MCLR, then VDD.
    digitalWrite(PIN_MCLR, MCLR_VPP);
    delayMicroseconds(DELAY_TPPDP);
    digitalWrite(PIN_VDD, HIGH);
    delayMicroseconds(DELAY_THLD0);

    // Now in program mode, starting at the first word of program memory.
    state = STATE_PROGRAM;
    pc = 0;
}

// Exit programming mode and reset the device.
void exitProgramMode()
{
    // Nothing to do if already out of programming mode.
    if (state == STATE_IDLE)
        return;

    // Lower MCLR, VDD, DATA, and CLOCK.
    digitalWrite(PIN_MCLR, MCLR_RESET);
    digitalWrite(PIN_VDD, LOW);
    digitalWrite(PIN_DATA, LOW);
    digitalWrite(PIN_CLOCK, LOW);

    // Float the DATA and CLOCK pins.
    pinMode(PIN_DATA, INPUT);
    pinMode(PIN_CLOCK, INPUT);

    // Now in the idle state with the PIC powered off.
    state = STATE_IDLE;
    pc = 0;
}

// Send a command to the PIC.
void sendCommand(byte cmd)
{
    for (byte bit = 0; bit < 6; ++bit) {
        digitalWrite(PIN_CLOCK, HIGH);
        if (cmd & 1)
            digitalWrite(PIN_DATA, HIGH);
        else
            digitalWrite(PIN_DATA, LOW);
        delayMicroseconds(DELAY_TSET1);
        digitalWrite(PIN_CLOCK, LOW);
        delayMicroseconds(DELAY_THLD1);
        cmd >>= 1;
    }
}

// Send a command to the PIC that has no arguments.
void sendSimpleCommand(byte cmd)
{
    sendCommand(cmd);
    delayMicroseconds(DELAY_TDLY2);
}

// Send a command to the PIC that writes a data argument.
void sendWriteCommand(byte cmd, unsigned int data)
{
    sendCommand(cmd);
    delayMicroseconds(DELAY_TDLY2);
    for (byte bit = 0; bit < 16; ++bit) {
        digitalWrite(PIN_CLOCK, HIGH);
        if (data & 1)
            digitalWrite(PIN_DATA, HIGH);
        else
            digitalWrite(PIN_DATA, LOW);
        delayMicroseconds(DELAY_TSET1);
        digitalWrite(PIN_CLOCK, LOW);
        delayMicroseconds(DELAY_THLD1);
        data >>= 1;
    }
    delayMicroseconds(DELAY_TDLY2);
}

// Send a command to the PIC that reads back a data value.
unsigned int sendReadCommand(byte cmd)
{
    unsigned int data = 0;
    sendCommand(cmd);
    digitalWrite(PIN_DATA, LOW);
    pinMode(PIN_DATA, INPUT);
    delayMicroseconds(DELAY_TDLY2);
    for (byte bit = 0; bit < 16; ++bit) {
        data >>= 1;
        digitalWrite(PIN_CLOCK, HIGH);
        delayMicroseconds(DELAY_TDLY3);
        if (digitalRead(PIN_DATA))
            data |= 0x8000;
        digitalWrite(PIN_CLOCK, LOW);
        delayMicroseconds(DELAY_THLD1);
    }
    pinMode(PIN_DATA, OUTPUT);
    delayMicroseconds(DELAY_TDLY2);
    return data;
}

// Set the program counter to a specific "flat" address.
void setPC(unsigned long addr)
{
    if (addr >= dataStart && addr <= dataEnd) {
        // Data memory.
        addr -= dataStart;
        if (state != STATE_PROGRAM || addr < pc) {
            // Device is off, currently looking at configuration memory,
            // or the address is further back.  Reset the device.
            exitProgramMode();
            enterProgramMode();
        }
    } else if (addr >= configStart && addr <= configEnd) {
        // Configuration memory.
        addr -= configStart;
        if (state == STATE_IDLE) {
            // Enter programming mode and switch to config memory.
            enterProgramMode();
            sendWriteCommand(CMD_LOAD_CONFIG, 0);
            state = STATE_CONFIG;
        } else if (state == STATE_PROGRAM) {
            // Switch from program memory to config memory.
            sendWriteCommand(CMD_LOAD_CONFIG, 0);
            state = STATE_CONFIG;
            pc = 0;
        } else if (addr < pc) {
            // Need to go backwards in config memory, so reset the device.
            exitProgramMode();
            enterProgramMode();
            sendWriteCommand(CMD_LOAD_CONFIG, 0);
            state = STATE_CONFIG;
        }
    } else {
        // Program memory.
        if (state != STATE_PROGRAM || addr < pc) {
            // Device is off, currently looking at configuration memory,
            // or the address is further back.  Reset the device.
            exitProgramMode();
            enterProgramMode();
        }
    }
    while (pc < addr) {
        sendSimpleCommand(CMD_INCREMENT_ADDRESS);
        ++pc;
    }
}

// Sets the PC for "erase mode", which is activated by loading the
// data value 0x3FFF into location 0 of configuration memory.
void setErasePC()
{
    // Forcibly reset the device so we know what state it is in.
    exitProgramMode();
    enterProgramMode();

    // Load 0x3FFF for the configuration.
    sendWriteCommand(CMD_LOAD_CONFIG, 0x3FFF);
    state = STATE_CONFIG;
}

// Read a word from memory (program, config, or data depending upon addr).
// The start and stop bits will be stripped from the raw value from the PIC.
unsigned int readWord(unsigned long addr)
{
    setPC(addr);
    if (addr >= dataStart && addr <= dataEnd)
        return (sendReadCommand(CMD_READ_DATA_MEMORY) >> 1) & 0x00FF;
    else
        return (sendReadCommand(CMD_READ_PROGRAM_MEMORY) >> 1) & 0x3FFF;
}

// Read a word from config memory using relative, non-flat, addressing.
// Used by the "DEVICE" command to fetch information about devices whose
// flat address ranges are presently unknown.
unsigned int readConfigWord(unsigned long addr)
{
    if (state == STATE_IDLE) {
        // Enter programming mode and switch to config memory.
        enterProgramMode();
        sendWriteCommand(CMD_LOAD_CONFIG, 0);
        state = STATE_CONFIG;
    } else if (state == STATE_PROGRAM) {
        // Switch from program memory to config memory.
        sendWriteCommand(CMD_LOAD_CONFIG, 0);
        state = STATE_CONFIG;
        pc = 0;
    } else if (addr < pc) {
        // Need to go backwards in config memory, so reset the device.
        exitProgramMode();
        enterProgramMode();
        sendWriteCommand(CMD_LOAD_CONFIG, 0);
        state = STATE_CONFIG;
    }
    while (pc < addr) {
        sendSimpleCommand(CMD_INCREMENT_ADDRESS);
        ++pc;
    }
    return (sendReadCommand(CMD_READ_PROGRAM_MEMORY) >> 1) & 0x3FFF;
}

// Begin a programming cycle, depending upon the type of flash being written.
void beginProgramCycle(unsigned long addr, bool isData)
{
    switch (isData ? dataFlashType : progFlashType) {
    case FLASH:
    case EEPROM:
        sendSimpleCommand(CMD_BEGIN_PROGRAM);
        delayMicroseconds(DELAY_TDPROG + DELAY_TERA);
        break;
    case FLASH4:
        sendSimpleCommand(CMD_BEGIN_PROGRAM);
        delayMicroseconds(DELAY_TPROG);
        break;
    case FLASH5:
        sendSimpleCommand(CMD_BEGIN_PROGRAM_ONLY);
        delayMicroseconds(DELAY_TPROG5);
        sendSimpleCommand(CMD_END_PROGRAM_ONLY);
        break;
    }
}

// Write a word to memory (program, config, or data depending upon addr).
// Returns true if the write succeeded, false if read-back failed to match.
bool writeWord(unsigned long addr, unsigned int word)
{
    unsigned int readBack;
    setPC(addr);
    if (addr >= dataStart && addr <= dataEnd) {
        word &= 0x00FF;
        sendWriteCommand(CMD_LOAD_DATA_MEMORY, word << 1);
        beginProgramCycle(addr, true);
        readBack = sendReadCommand(CMD_READ_DATA_MEMORY);
        readBack = (readBack >> 1) & 0x00FF;
    } else if (!configSave || addr != (configStart + DEV_CONFIG_WORD)) {
        word &= 0x3FFF;
        sendWriteCommand(CMD_LOAD_PROGRAM_MEMORY, word << 1);
        beginProgramCycle(addr, false);
        readBack = sendReadCommand(CMD_READ_PROGRAM_MEMORY);
        readBack = (readBack >> 1) & 0x3FFF;
    } else {
        // The configuration word has calibration bits within it that
        // must be preserved when we write to it.  Read the current value
        // and preserve the necessary bits.
        readBack = (sendReadCommand(CMD_READ_PROGRAM_MEMORY) >> 1) & 0x3FFF;
        word = (readBack & configSave) | (word & 0x3FFF & ~configSave);
        sendWriteCommand(CMD_LOAD_PROGRAM_MEMORY, word << 1);
        beginProgramCycle(addr, false);
        readBack = sendReadCommand(CMD_READ_PROGRAM_MEMORY);
        readBack = (readBack >> 1) & 0x3FFF;
    }
    return readBack == word;
}

// Force a word to be written even if it normally would protect config bits.
bool writeWordForced(unsigned long addr, unsigned int word)
{
    unsigned int readBack;
    setPC(addr);
    if (addr >= dataStart && addr <= dataEnd) {
        word &= 0x00FF;
        sendWriteCommand(CMD_LOAD_DATA_MEMORY, word << 1);
        beginProgramCycle(addr, true);
        readBack = sendReadCommand(CMD_READ_DATA_MEMORY);
        readBack = (readBack >> 1) & 0x00FF;
    } else {
        word &= 0x3FFF;
        sendWriteCommand(CMD_LOAD_PROGRAM_MEMORY, word << 1);
        beginProgramCycle(addr, false);
        readBack = sendReadCommand(CMD_READ_PROGRAM_MEMORY);
        readBack = (readBack >> 1) & 0x3FFF;
    }
    return readBack == word;
}
