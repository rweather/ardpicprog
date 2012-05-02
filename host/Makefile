
TARGET = ardpicprog
VERSION = 0.1.1

SOURCES = hexfile.cpp main.cpp serialport.cpp serialport_posix.cpp
OBJECTS = hexfile.o main.o serialport.o serialport_posix.o

CXXFLAGS = -g -Wall -DARDPICPROG_VERSION=\"$(VERSION)\"

LDFLAGS += -g -lstdc++

all:	$(TARGET)

$(TARGET):	$(OBJECTS)
	$(CXX) -o $(TARGET) $(OBJECTS) $(LDFLAGS)

clean:
	rm -f $(TARGET) $(TARGET).exe $(OBJECTS)

hexfile.o: hexfile.h serialport.h
main.o: serialport.h hexfile.h
serialport.o: serialport.h
serialport_posix.o: serialport.h
