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

#define PIN_MCLR        A1      // 0: MCLR is VPP voltage, 1: Reset PIC
#define PIN_ACTIVITY    A5      // LED that indicates read/write activity
#define PIN_VDD         2       // Controls the power to the PIC
#define PIN_CLOCK       4       // Clock pin
#define PIN_DATA        7       // Data pin

#define STATE_IDLE      0       // Idle, device is held in the reset state
#define STATE_READY     1       // Ready for a command

int state = STATE_IDLE;

void setup()
{
    /* Hold the PIC in the powered down/reset state until we are ready for it */
    pinMode(PIN_MCLR, OUTPUT);
    pinMode(PIN_VDD, OUTPUT);
    digitalWrite(PIN_MCLR, HIGH);
    digitalWrite(PIN_VDD, LOW);

    /* Clock and data are floating until the first PIC command */
    pinMode(PIN_CLOCK, INPUT);
    pinMode(PIN_DATA, INPUT);

    /* Turn off the activity LED initially */
    pinMode(PIN_ACTIVITY, OUTPUT);
    digitalWrite(PIN_ACTIVITY, LOW);
}

void loop()
{
}
