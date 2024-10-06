PREFIX := /usr/local
DESTDIR :=

BINS = changelog.bash init.bash build.bash

all: test

test:
	bats test/*.bats

install:
	$(foreach bin,$(BINS), install -Dm0755 $(bin) \
		"$(DESTDIR)$(PREFIX)/bin/$(bin)";)
	install -Dm0644 README.md \
		"$(DESTDIR)$(PREFIX)/share/doc/godeb/README.md"

uninstall:
	$(foreach bin,$(BINS), rm -rf "$(DESTDIR)$(PREFIX)/bin/$(bin)";)
	rm -rf "$(DESTDIR)$(PREFIX)/share/doc/godeb"

.PHONY: all install test uninstall
