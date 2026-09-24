# gdk-pixbuf loader for .yaif: make && sudo make install
CFLAGS ?= -O2
LOADERS := $(shell pkg-config --variable=gdk_pixbuf_moduledir gdk-pixbuf-2.0)
libpixbufloader-yaif.so: io-yaif.c ../../libyaif/yaifdec.c
	$(CC) $(CFLAGS) -std=c99 -Wall -fPIC -shared -I../../libyaif $^ -o $@ $(shell pkg-config --cflags --libs gdk-pixbuf-2.0) -lpthread
install: libpixbufloader-yaif.so
	install -m 644 libpixbufloader-yaif.so $(LOADERS)/
	install -m 644 yaif.thumbnailer /usr/share/thumbnailers/
	gdk-pixbuf-query-loaders-64 --update-cache || gdk-pixbuf-query-loaders --update-cache
