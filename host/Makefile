
TARGET = ardpicprog

SOURCES = main.cpp serialport.cpp
OBJECTS = main.o serialport.o

CXXFLAGS = -g

LDFLAGS += -g -lstdc++

all:	$(TARGET)

$(TARGET):	$(OBJECTS)
	$(CXX) -o $(TARGET) $(OBJECTS) $(LDFLAGS)

clean:
	rm -f $(TARGET) $(OBJECTS)

main.o: serialport.h
serialport.o: serialport.h
