
all:
	(cd host; make all)

win:
	(cd host; make -f Makefile.win)

clean:
	(cd host; make clean)
