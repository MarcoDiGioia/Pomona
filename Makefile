CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
PKGS    := libusb-1.0
BUILD   ?= build

LOCALE  ?= locale
LANGS   := $(shell cat po/LINGUAS)

.PHONY: all build mo test lint clean deb

all: build mo

# compiled translations: $(LOCALE)/<lang>/LC_MESSAGES/pomona.mo
mo:
	@for l in $(LANGS); do mkdir -p $(LOCALE)/$$l/LC_MESSAGES && python3 -I tools/msgfmt.py po/$$l.po $(LOCALE)/$$l/LC_MESSAGES/pomona.mo; done

build: $(BUILD)/pomona-t1-boot

$(BUILD)/pomona-t1-boot: src/pomona-t1-boot.c
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o $@ $< $$(pkg-config --cflags --libs $(PKGS))

test:
	bash tests/run.sh

lint:
	bash -n bin/pomona lib/pomona.sh lib/wifi.sh lib/audio.sh data/audio/dkms/pomona-cs8409-prepare install.sh uninstall.sh tools/prepare-public.sh tools/sync-wiki.sh tests/*.sh
	python3 -I -m py_compile libexec/pomona-touchbard gui/pomona-gui tools/wiki.py && bash -n libexec/pomona-admin
	@command -v shellcheck >/dev/null && shellcheck -x bin/pomona lib/pomona.sh lib/wifi.sh lib/audio.sh data/audio/dkms/pomona-cs8409-prepare install.sh uninstall.sh || echo "shellcheck not installed, skipped"

deb:
	bash packaging/deb/build-deb.sh

clean:
	rm -rf $(BUILD) $(LOCALE)
