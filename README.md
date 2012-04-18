
Arduino-based PIC programmer
============================

This distribution contains an Arduino-based solution for programming
PIC microcontrollers from Microchip Technology Inc, such as the
PIC16F628A and friends.  The solution has three parts:

* Circuit that is built on one or more prototyping shields to interface
  to the PIC and provide the 13V programming voltage.
* Sketch called ProgramPIC that is loaded into an Arduino to directly
  interface with the PIC during programming.
* Host program called ardpicprog that is a drop-in replacement for
  [picprog](http://hyvatti.iki.fi/~jaakko/pic/picprog.html) that
  controls the PIC programming process on the computer side.

Note: ardpicprog is not compatible with JDM-style PIC programmers.
Those programmers use RS-232 control signals such as DTR and CTS to
interface to the host computer.  The Arduino uses a simple serial
interface over USB with no access to the RS-232 control signals from
the host.  Because of this, ardpicprog uses a completely different
interface between the host and the programmer that runs over a regular
serial data link.  The host side was deliberately made compatible with
the picprog tool to make it easier to replace picprog with ardpicprog
in existing build scripts.

## Obtaining ardpicprog

The sources for Plang are available from the project
[git repository](https://github.com/rweather/ardpicprog).

## Building ardpicprog

TBD
