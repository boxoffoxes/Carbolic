CC=clang
OPT=-O2
PASSES=

all : zcat

% : %.c busybox.def.h internal.h
	$(CC) $(OPT) -o $@ $<


clean :
	rm zcat
