PREFIX = /usr

SHELL := sh

.PHONY: \
	install uninstall setup remove all backup \
	setup-shared remove-shared


install: setup
uninstall: remove
remove: remove-shared
setup-crypto: setup-shared
setup-secboot: setup-shared
setup: setup-shared
all: setup

setup-shared:
	install -d -m 755 $(PREFIX)/lib/dystopian
	install -m 640 lib/libadmintools-variables.sh $(PREFIX)/lib/dystopian/libadmintools-variables.sh
	install -m 640 lib/variables.sh $(PREFIX)/lib/dystopian/variables.sh
	install -m 640 lib/libhelper.sh $(PREFIX)/lib/dystopian/libhelper.sh
	install -m 640 lib/libssl.sh $(PREFIX)/lib/dystopian/libssl.sh
	install -m 640 lib/libgpg.sh $(PREFIX)/lib/dystopian/libgpg.sh
	install -m 640 lib/libcrypto-db.sh $(PREFIX)/lib/dystopian/libcrypto-db.sh
	install -m 640 lib/libsecboot.sh $(PREFIX)/lib/dystopian/libsecboot.sh
	install -m 640 lib/libsecboot-db.sh $(PREFIX)/lib/dystopian/libsecboot-db.sh
	install -m 640 lib/libhosts.sh $(PREFIX)/lib/dystopian/libhosts.sh
	install -m 640 lib/libhosts-db.sh $(PREFIX)/lib/dystopian/libhosts-db.sh
	install -m 640 lib/libaurtool.sh $(PREFIX)/lib/dystopian/libaurtool.sh
	install -m 640 lib/libaurtool-db.sh $(PREFIX)/lib/dystopian/libaurtool-db.sh
	install -d -m 755 $(PREFIX)/share/doc/dystopian-libs
	install -m 644 README.md $(PREFIX)/share/doc/dystopian-libs/README.md

remove-shared:
	rm -f $(PREFIX)/lib/dystopian/variables.sh
	rm -f $(PREFIX)/lib/dystopian/libadmintools-variables.sh
	rm -f $(PREFIX)/lib/dystopian/libhelper.sh
	rm -f $(PREFIX)/lib/dystopian/libssl.sh
	rm -f $(PREFIX)/lib/dystopian/libgpg.sh
	rm -f $(PREFIX)/lib/dystopian/libcrypto-db.sh
	rm -f $(PREFIX)/lib/dystopian/libsecboot.sh
	rm -f $(PREFIX)/lib/dystopian/libsecboot-db.sh
	rm -f $(PREFIX)/lib/dystopian/libaurtool.sh
	rm -f $(PREFIX)/lib/dystopian/libaurtool-db.sh
	rm -f $(PREFIX)/lib/dystopian/libhosts.sh
	rm -f $(PREFIX)/lib/dystopian/libhosts-db.sh
	rmdir $(PREFIX)/lib/dystopian || true
	rm -f $(PREFIX)/share/doc/dystopian-libs/README.md
	rmdir $(PREFIX)/share/doc/dystopian-libs || true
