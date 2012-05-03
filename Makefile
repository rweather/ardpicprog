
all:
	(cd host; make all)

win:
	(cd host; make -f Makefile.win)

install:
	(cd host; make install)

uninstall:
	(cd host; make uninstall)

clean:
	(cd host; make clean)
