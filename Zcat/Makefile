OPT=-O2

all : zcat

% : %.c busybox.def.h internal.h
	gcc $(OPT) -o $@ $<


clean :
	rm zcat
