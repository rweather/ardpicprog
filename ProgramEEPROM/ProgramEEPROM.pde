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

#include <avr/pgmspace.h>       // For PROGMEM

// Pin mappings for the PIC programming shield.
#define PIN_MCLR        A1      // MCLR - not used for EEPROM mode.
#define PIN_ACTIVITY    A5      // LED that indicates read/write activity
#define PIN_VDD         2       // Controls the power to the PIC
#define PIN_CLOCK       4       // Clock pin
#define PIN_DATA        7       // Data pin

#define MCLR_RESET      HIGH    // PIN_MCLR state to reset the PIC
#define MCLR_VPP        LOW     // PIN_MCLR state to apply 13v to MCLR/VPP pin
#define VDD_OFF         LOW     // PIN_VDD state to lower target VDD
#define VDD_ON          HIGH    // PIN_VDD state to raise target VDD

#define LOWER_VPP() { digitalWrite(PIN_MCLR, MCLR_RESET); }
#define RAISE_VPP() { digitalWrite(PIN_MCLR, MCLR_VPP); }
#define LOWER_VDD() { digitalWrite(PIN_VDD, VDD_OFF); }
#define RAISE_VDD() { digitalWrite(PIN_VDD, VDD_ON); }

// All delays are in microseconds.
#define DELAY_SETTLE    50      // Delay for lines to settle for power off/on

// States this application may be in.
#define STATE_IDLE      0       // Idle, device is held in the reset state
#define STATE_PROGRAM   1       // Active, reading and writing memory
int state = STATE_IDLE;

// Block select modes within the control byte.
#define BSEL_NONE           0
#define BSEL_8BIT_ADDR      1
#define BSEL_17BIT_ADDR     2
#define BSEL_17BIT_ADDR_ALT 3

const prog_char *eepromName;
unsigned long eepromSize;
unsigned long eepromEnd;
byte eepromI2CAddress;
byte eepromBlockSelectMode;
unsigned int eepromPageSize;

// Device names, forced out into PROGMEM.
const char s_24lc00[]   PROGMEM = "24lc00";
const char s_24lc01[]   PROGMEM = "24lc01";
const char s_24lc014[]  PROGMEM = "24lc014";
const char s_24lc02[]   PROGMEM = "24lc02";
const char s_24lc024[]  PROGMEM = "24lc024";
const char s_24lc025[]  PROGMEM = "24lc025";
const char s_24lc04[]   PROGMEM = "24lc04";
const char s_24lc08[]   PROGMEM = "24lc08";
const char s_24lc16[]   PROGMEM = "24lc16";
const char s_24lc32[]   PROGMEM = "24lc32";
const char s_24lc64[]   PROGMEM = "24lc64";
const char s_24lc128[]  PROGMEM = "24lc128";
const char s_24lc256[]  PROGMEM = "24lc256";
const char s_24lc512[]  PROGMEM = "24lc512";
const char s_24lc1025[] PROGMEM = "24lc1025";
const char s_24lc1026[] PROGMEM = "24lc1026";

// List of devices that are currently supported and their properties.
// Note: most of these are based on published information and have not
// been tested by the author.  Patches welcome to improve the list.
struct deviceInfo
{
    const prog_char *name;      // User-readable name of the device.
    prog_uint32_t size;         // Size of program memory (bytes).
    prog_uint16_t pageSize;     // Size of a page for bulk transfers.
    prog_uint8_t address;       // Address on the I2C bus.
    prog_uint8_t blockSelect;   // Block select mode.

};
struct deviceInfo const devices[] PROGMEM = {
    // http://ww1.microchip.com/downloads/en/DeviceDoc/21178H.pdf
    {s_24lc00, 16UL, 1, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21711J.pdf
    {s_24lc01, 128UL, 8, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21809G.pdf
    {s_24lc014, 128UL, 16, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21709J.pdf
    {s_24lc02, 256UL, 8, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21210N.pdf
    {s_24lc024, 256UL, 16, 0xA0, BSEL_8BIT_ADDR},
    {s_24lc025, 256UL, 16, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21708K.pdf
    {s_24lc04, 512UL, 16, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21710K.pdf
    {s_24lc08, 1024UL, 16, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21703K.pdf
    {s_24lc16, 2048UL, 16, 0xA0, BSEL_8BIT_ADDR},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21713M.pdf
    {s_24lc32, 4096UL, 32, 0xA0, BSEL_NONE},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21189S.pdf
    {s_24lc64, 8192UL, 32, 0xA0, BSEL_NONE},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21191s.pdf
    {s_24lc128, 16384UL, 64, 0xA0, BSEL_NONE},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21203R.pdf
    {s_24lc256, 32768UL, 64, 0xA0, BSEL_NONE},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21754M.pdf
    {s_24lc512, 65536UL, 128, 0xA0, BSEL_NONE},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/21941K.pdf
    {s_24lc1025, 131072UL, 128, 0xA0, BSEL_17BIT_ADDR_ALT},

    // http://ww1.microchip.com/downloads/en/DeviceDoc/22270C.pdf
    {s_24lc1026, 131072UL, 128, 0xA0, BSEL_17BIT_ADDR},

    {0, 0, 0, 0, 0}
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

    // Initialize the defaults for the 24LC256.
    setDefaultDeviceInfo();

    // Hold the chip in the powered down/reset state until we are ready for it.
    pinMode(PIN_MCLR, OUTPUT);
    pinMode(PIN_VDD, OUTPUT);
    LOWER_VPP();
    LOWER_VDD();

    // Initially set the CLOCK and DATA lines to be outputs in the high state.
    pinMode(PIN_CLOCK, OUTPUT);
    pinMode(PIN_DATA, OUTPUT);
    digitalWrite(PIN_CLOCK, HIGH);
    digitalWrite(PIN_DATA, HIGH);

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

// Set the defaults for the 24LC256.
void setDefaultDeviceInfo()
{
    eepromName = s_24lc256;
    eepromSize = 32768UL;
    eepromEnd = (eepromSize / 2) - 1;
    eepromI2CAddress = 0xA0;
    eepromBlockSelectMode = BSEL_NONE;
    eepromPageSize = 64;
}

// Print the device information.
void printDeviceInfo()
{
    Serial.print("DeviceName: ");
    printProgString(eepromName);
    Serial.println();
    Serial.print("DataRange: 0000-");
    printHex8(eepromEnd);
    Serial.println();
    Serial.println("DataBits: 16");
}

// Initialize device properties from the "devices" list.
// Note: "dev" is in PROGMEM.
void initDevice(const struct deviceInfo *dev)
{
    eepromName = (const prog_char *)pgm_read_word(&(dev->name));
    eepromSize = pgm_read_dword(&(dev->size));
    eepromEnd = (eepromSize / 2) - 1;
    eepromI2CAddress = pgm_read_byte(&(dev->address));
    eepromBlockSelectMode = pgm_read_byte(&(dev->blockSelect));
    eepromPageSize = pgm_read_word(&(dev->pageSize));
}

// DEVICE command.
void cmdDevice(const char *args)
{
    // Start with the chip powered off.
    exitProgramMode();

    // Probe the I2C bus to see if we have a working EEPROM.
    setDefaultDeviceInfo();
    if (!probeDevice()) {
        Serial.println("ERROR");
        return;
    }

    Serial.println("OK");

    Serial.println("DeviceID: 0000");

    printDeviceInfo();

    Serial.println(".");
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
        unsigned long size = pgm_read_dword(&(devices[index].size));
        if (size == 32768UL)    // 24LC256 is the default
            Serial.print('*');
        ++index;
    }
    Serial.println();
    Serial.println(".");
}

// SETDEVICE command.
void cmdSetDevice(const char *args)
{
    // Start with the chip powered off.
    exitProgramMode();

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
            initDevice(&(devices[index]));
            if (!probeDevice()) {
                // No device on the bus.
                setDefaultDeviceInfo();
                Serial.println("ERROR");
                exitProgramMode();
                return;
            }
            Serial.println("OK");
            printDeviceInfo();
            Serial.println(".");
            return;
        }
        ++index;
    }
    setDefaultDeviceInfo();
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
    if (*start <= eepromEnd) {
        if (*end > eepromEnd)
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
    if (!startRead(start)) {
        // No device on the bus.
        Serial.println("ERROR");
        return;
    }
    Serial.println("OK");
    int count = 0;
    bool activity = true;
    while (start <= end) {
        unsigned int word = readWord(start == end);
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
    if (!startRead(start)) {
        // No device on the bus.
        Serial.println("ERROR");
        return;
    }
    Serial.println("OK");
    int count = 0;
    bool activity = true;
    size_t offset = 0;
    while (start <= end) {
        unsigned int word = readWord(start == end);
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

// WRITE command.
void cmdWrite(const char *args)
{
    unsigned long addr;
    unsigned long limit;
    unsigned long value;
    int size;
    size = parseHex(args, &addr);
    if (!size) {
        Serial.println("ERROR");
        return;
    }
    args += size;
    if (addr <= eepromEnd) {
        limit = eepromEnd;
    } else {
        // Address is not within one of the valid ranges.
        Serial.println("ERROR");
        return;
    }
    startWrite(addr);
    int count = 0;
    for (;;) {
        while (*args == ' ' || *args == '\t')
            ++args;
        if (*args == '\0')
            break;
        if (*args == '-') {
            stopWrite();
            Serial.println("ERROR");
            return;
        }
        size = parseHex(args, &value);
        if (!size) {
            stopWrite();
            Serial.println("ERROR");
            return;
        }
        args += size;
        if (addr > limit) {
            // We've reached the limit of this memory area, so fail.
            stopWrite();
            Serial.println("ERROR");
            return;
        }
        if (!writeWord((unsigned int)value)) {
            // The actual write to the device failed.
            stopWrite();
            Serial.println("ERROR");
            return;
        }
        ++addr;
        ++count;
    }
    stopWrite();
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
    size = parseHex(args, &addr);
    if (!size) {
        Serial.println("ERROR");
        return;
    }
    args += size;
    if (addr <= eepromEnd) {
        limit = eepromEnd;
    } else {
        // Address is not within one of the valid ranges.
        Serial.println("ERROR");
        return;
    }
    startWrite(addr);
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
                stopWrite();
                Serial.println("ERROR");
                return;
            }
            unsigned int value =
                (((unsigned int)buffer[posn]) & 0xFF) |
                ((((unsigned int)buffer[posn + 1]) & 0xFF) << 8);
            if (!writeWord((unsigned int)value)) {
                // The actual write to the device failed.
                stopWrite();
                Serial.println("ERROR");
                return;
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
    stopWrite();
    Serial.println("OK");
}

// ERASE command.
void cmdErase(const char *args)
{
    if (eraseAll())
        Serial.println("OK");
    else
        Serial.println("ERROR");
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

// Enter programming mode.
void enterProgramMode()
{
    // Bail out if already in programming mode.
    if (state != STATE_IDLE)
        return;

    // Lower VDD, which will power off the chip just in case.
    LOWER_VDD();

    // Make sure that CLOCK and DATA are high.
    pinMode(PIN_CLOCK, OUTPUT);
    pinMode(PIN_DATA, OUTPUT);
    digitalWrite(PIN_CLOCK, HIGH);
    digitalWrite(PIN_DATA, HIGH);

    // Wait for the lines to settle.
    delayMicroseconds(DELAY_SETTLE);

    // Raise VDD.
    RAISE_VDD();
    delayMicroseconds(DELAY_SETTLE);

    // Now in program mode, address not set yet.
    state = STATE_PROGRAM;
}

// Exit programming mode and reset the device.
void exitProgramMode()
{
    // Nothing to do if already out of programming mode.
    if (state == STATE_IDLE)
        return;

    // Lower VDD.
    LOWER_VDD();

    // Return the CLOCK and DATA lines to the pulled-high state.
    pinMode(PIN_CLOCK, OUTPUT);
    pinMode(PIN_DATA, OUTPUT);
    digitalWrite(PIN_CLOCK, HIGH);
    digitalWrite(PIN_DATA, HIGH);

    // Now in the idle state with the chip powered off.
    state = STATE_IDLE;
}

// Details of the I2C protocol here: http://en.wikipedia.org/wiki/I2C
// Assumptions: only one master, no arbitration, and no clock stretching.

#define i2cDelay()  delayMicroseconds(5)

bool started = false;

void i2cStart()
{
    pinMode(PIN_DATA, OUTPUT);
    if (started) {
        // Already started, so send a restart condition.
        digitalWrite(PIN_DATA, HIGH);
        digitalWrite(PIN_CLOCK, HIGH);
        i2cDelay();
    }
    digitalWrite(PIN_DATA, LOW);
    i2cDelay();
    digitalWrite(PIN_CLOCK, LOW);
    i2cDelay();
    started = true;
}

void i2cStop()
{
    pinMode(PIN_DATA, OUTPUT);
    digitalWrite(PIN_DATA, LOW);
    digitalWrite(PIN_CLOCK, HIGH);
    i2cDelay();
    digitalWrite(PIN_DATA, HIGH);
    i2cDelay();
    started = false;
}

inline void i2cWriteBit(bool bit)
{
    pinMode(PIN_DATA, OUTPUT);
    if (bit)
        digitalWrite(PIN_DATA, HIGH);
    else
        digitalWrite(PIN_DATA, LOW);
    i2cDelay();
    digitalWrite(PIN_CLOCK, HIGH);
    i2cDelay();
    digitalWrite(PIN_CLOCK, LOW);
    i2cDelay();
}

inline bool i2cReadBit()
{
    pinMode(PIN_DATA, INPUT);
    digitalWrite(PIN_DATA, HIGH);
    digitalWrite(PIN_CLOCK, HIGH);
    bool bit = digitalRead(PIN_DATA);
    i2cDelay();
    digitalWrite(PIN_CLOCK, LOW);
    i2cDelay();
    return bit;
}

#define I2C_ACK     false
#define I2C_NACK    true

bool i2cWrite(byte value)
{
    byte mask = 0x80;
    while (mask != 0) {
        i2cWriteBit((value & mask) != 0);
        mask >>= 1;
    }
    return i2cReadBit();
}

byte i2cRead(bool nack)
{
    byte value = 0;
    for (byte bit = 0; bit < 8; ++bit)
        value = (value << 1) | i2cReadBit();
    i2cWriteBit(nack);
    return value;
}

#define I2C_READ    0x01
#define I2C_WRITE   0x00

bool writeAddress(unsigned long byteAddr)
{
    byte ctrl;
    switch (eepromBlockSelectMode) {
    case BSEL_NONE:
        if (i2cWrite(eepromI2CAddress | I2C_WRITE) == I2C_NACK)
            return false;
        i2cWrite((byte)(byteAddr >> 8));
        i2cWrite((byte)byteAddr);
        break;
    case BSEL_8BIT_ADDR:
        ctrl = eepromI2CAddress | ((byte)(byteAddr >> 7) & 0x0E) | I2C_WRITE;
        if (i2cWrite(ctrl) == I2C_NACK)
            return false;
        i2cWrite((byte)byteAddr);
        break;
    case BSEL_17BIT_ADDR:
        ctrl = eepromI2CAddress | ((byte)(byteAddr >> 15) & 0x02) | I2C_WRITE;
        if (i2cWrite(ctrl) == I2C_NACK)
            return false;
        i2cWrite((byte)(byteAddr >> 8));
        i2cWrite((byte)byteAddr);
        break;
    case BSEL_17BIT_ADDR_ALT:
        ctrl = eepromI2CAddress | ((byte)(byteAddr >> 13) & 0x08) | I2C_WRITE;
        if (i2cWrite(ctrl) == I2C_NACK)
            return false;
        i2cWrite((byte)(byteAddr >> 8));
        i2cWrite((byte)byteAddr);
        break;
    }
    return true;
}

// Start a bulk read operation.
bool startRead(unsigned long addr)
{
    enterProgramMode();
    i2cStart();
    if (!writeAddress(addr * 2))
        return false;
    i2cStart();
    return i2cWrite(eepromI2CAddress | I2C_READ) == I2C_ACK;
}

// Read the next 16-bit word from the EEPROM during a bulk read operation.
// If "last" is true then stop the bulk read operation after reading the word.
unsigned int readWord(bool last)
{
    unsigned int value = i2cRead(I2C_ACK);
    value |= ((unsigned int)(i2cRead(last))) << 8;
    if (last)
        i2cStop();
    return value;
}

unsigned long writeByteAddr;
bool writeAddrNeeded;

// Start a bulk write operation.
void startWrite(unsigned long addr)
{
    enterProgramMode();
    writeByteAddr = addr * 2;
    writeAddrNeeded = true;
}

// Write a 16-bit word during a bulk write operation.
bool writeWord(unsigned int word)
{
    if (writeAddrNeeded) {
        i2cStart();
        if (!writeAddress(writeByteAddr)) {
            i2cStop();
            return false;
        }
        writeAddrNeeded = false;
    }
    i2cWrite((byte)word);
    if (eepromPageSize == 1) {
        // 24LC00 needs a flush after every byte that is written.
        i2cStop();
        for (;;) {
            // Poll until we get an acknowledgement from the EEPROM.
            i2cStart();
            if (i2cWrite(eepromI2CAddress | I2C_WRITE) == I2C_ACK)
                break;
        }
        i2cStop();
        i2cStart();
        if (!writeAddress(writeByteAddr + 1)) {
            i2cStop();
            return false;
        }
    }
    i2cWrite((byte)(word >> 8));
    writeByteAddr += 2;
    if ((writeByteAddr % eepromPageSize) == 0) {
        // Overflow into the next page, so need to flush and send a new address.
        i2cStop();
        for (;;) {
            // Poll until we get an acknowledgement from the EEPROM.
            i2cStart();
            if (i2cWrite(eepromI2CAddress | I2C_WRITE) == I2C_ACK)
                break;
        }
        i2cStop();
        writeAddrNeeded = true;
    }
    return true;
}

// Stop a bulk write operation.
void stopWrite()
{
    if (!writeAddrNeeded) {
        // Flush the final page write operation.
        i2cStop();
        for (;;) {
            // Poll until we get an acknowledgement from the EEPROM.
            i2cStart();
            if (i2cWrite(eepromI2CAddress | I2C_WRITE) == I2C_ACK)
                break;
        }
        i2cStop();
    }
}

// Erases all bytes within the EEPROM by setting them to 0xFF.
bool eraseAll()
{
    enterProgramMode();

    // Fill the bytes a page at a time.
    unsigned long startTime = millis();
    unsigned long currentTime;
    unsigned long addr = 0;
    bool activity = true;
    while (addr < eepromSize) {
        i2cStart();
        if (!writeAddress(addr))
            return false;   // No device on the bus.
        for (unsigned int count = 0; count < eepromPageSize; ++count)
            i2cWrite(0xFF);
        i2cStop();
        for (;;) {
            // Poll until we get an acknowledgement from the EEPROM.
            i2cStart();
            if (i2cWrite(eepromI2CAddress | I2C_WRITE) == I2C_ACK)
                break;
        }
        i2cStop();
        addr += eepromPageSize;
        if ((addr % 512) == 0) {
            activity = !activity;
            if (activity)
                digitalWrite(PIN_ACTIVITY, HIGH);
            else
                digitalWrite(PIN_ACTIVITY, LOW);
        }
        currentTime = millis();
        if ((currentTime - startTime) >= 2000) {
            // Erase has been running for too long, so ask the host to wait.
            Serial.println("PENDING");
            startTime = currentTime;
        }
    }
    return true;
}

// Probe the device to see if it is present on the bus.  We do this by
// doing a "Current Address Read" and checking for the presence of ACK bits.
bool probeDevice()
{
    enterProgramMode();
    i2cStart();
    if (i2cWrite(eepromI2CAddress | I2C_READ) == I2C_NACK)
        return false;
    i2cRead(I2C_NACK);
    i2cStop();
    return true;
}
