# Makefile of the pomona-cs8409 DKMS package: builds hda/codecs/cirrus, prepared by pomona-cs8409-prepare.
# SPDX-License-Identifier: GPL-3.0-or-later
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/hda/codecs/cirrus modules

clean:
	rm -rf hda
