
Arduino-based PIC programmer
============================

This distribution contains an Arduino-based solution for programming
PIC microcontrollers from Microchip Technology Inc, such as the
PIC16F628A and friends.  The solution has three parts:

* Circuit that is built on one or more prototyping shields to interface
  to the PIC and provide the 13V programming voltage.
* Sketch called ProgramPIC that is loaded into an Arduino to directly
  interface with the PIC during programming.  The sketch implements a
  simple serial protocol for interfacing with the host.
* Host program called ardpicprog; a drop-in replacement for
  [picprog](http://hyvatti.iki.fi/~jaakko/pic/picprog.html) that
  implements the serial protocol and controls the PIC programming
  process on the computer side.

See the [documentation](http://rweather.github.io/ardpicprog/)
for more information on the project.

## Obtaining ardpicprog

The sources for Plang are available from the project
[git repository](https://github.com/rweather/ardpicprog).  Then read the
[installation instructions](http://rweather.github.io/ardpicprog/installation.html).

## Contact

For more information on Ardpicprog, to report bugs, or to suggest
improvements, please contact the author Rhys Weatherley via
[email](mailto:rhys.weatherley@gmail.com).  Patches to support new
device types are very welcome.
