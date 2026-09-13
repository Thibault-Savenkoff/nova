# gdk-pixbuf loader for .nova: make && sudo make install
CFLAGS ?= -O2
LOADERS := $(shell pkg-config --variable=gdk_pixbuf_moduledir gdk-pixbuf-2.0)
libpixbufloader-nova.so: io-nova.c ../../libnova/novadec.c
	$(CC) $(CFLAGS) -std=c99 -Wall -fPIC -shared -I../../libnova $^ -o $@ $(shell pkg-config --cflags --libs gdk-pixbuf-2.0) -lpthread
install: libpixbufloader-nova.so
	install -m 644 libpixbufloader-nova.so $(LOADERS)/
	install -m 644 nova.thumbnailer /usr/share/thumbnailers/
	gdk-pixbuf-query-loaders-64 --update-cache || gdk-pixbuf-query-loaders --update-cache
