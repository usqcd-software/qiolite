include ../make.inc
include make.objs

CINC = -I../include -I.
QIOH = ../include/qio.h

libs: liblime.a libqio.a
#libs: liblime.a libqio.so

libqio.a: $(OBJS)
	ld -r $^ -o libtmp.o
	objcopy --localize-hidden libtmp.o libqio.o
	rm -f libtmp.o
	rm -f $@
	ar rcs $@ libqio.o
	rm -f libqio.o

libqio.so: $(OBJS)
	ld -shared -o $@ $^

liblime.a:
	touch $@

$(OBJS): %.o: % $(QIOH)
	$(CC) $(CFLAGS) $(CINC) $(CWARN) -c -o $@ $<

clean:
	rm -f $(OBJS)

realclean: clean
	rm -f liblime.a libqio.a

distclean: realclean
	rm -f $(OBJS:.c.o=.c)
