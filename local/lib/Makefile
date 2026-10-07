CC ?= clang
CFLAGS ?= -O2 -dynamiclib -framework ApplicationServices

all: sunshine_input_fix.dylib

sunshine_input_fix.dylib: sunshine_input_fix.c
	$(CC) $(CFLAGS) -o $@ $<

install: sunshine_input_fix.dylib
	mkdir -p $(HOME)/.local/lib
	ln -sf $(CURDIR)/sunshine_input_fix.dylib $(HOME)/.local/lib/sunshine_input_fix.dylib

clean:
	rm -f sunshine_input_fix.dylib
