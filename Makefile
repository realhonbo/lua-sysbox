# Copyright 2026 Honbo He <hehongbo918@gmail.com>

MAKEFLAGS += -r -R
CC        ?= gcc
STRIP     ?= strip

CFLAGS    := -Wall -Wno-unused-result -fPIC -D_GNU_SOURCE -ggdb -O2
CFLAGS    += -fno-omit-frame-pointer -I. $(if $(LUA_INCDIR),-I$(LUA_INCDIR)) $(EXTRA_CFLAGS)
CFLAGS    += -MMD -MP
OBJECTS    = libutil.o syscall.o
TARGETS    = libutil.so syscall.so

.PHONY: all clean install
all: $(TARGETS)

libutil.so: libutil.o
	$(CC) -shared -o $@ $^ $(LDFLAGS)
	$(STRIP) -s $@

syscall.so: syscall.o
	$(CC) -shared -o $@ $^ $(LDFLAGS)
	$(STRIP) -s $@

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

# Installation is handled by luarocks (see the rockspec's build.install).
install:
	@true

clean:
	rm -rf *.o *.d $(TARGETS)

-include $(OBJECTS:.o=.d)
