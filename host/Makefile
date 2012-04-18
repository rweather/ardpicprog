
TARGET = ardpicprog

SOURCES = main.c
OBJECTS = main.o

all:	$(TARGET)

$(TARGET):	$(OBJECTS)
	$(CC) $(LDFLAGS) -o $(TARGET) $(OBJECTS)

clean:
	rm -f $(TARGET) $(OBJECTS)
