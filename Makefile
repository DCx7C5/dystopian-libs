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
	install -d -m 755 $(PREFIX)/lib/dystopian-libs
	install -m 640 lib/libadmintools-variables.sh $(PREFIX)/lib/dystopian-libs/libadmintools-variables.sh
	install -m 640 lib/libtools-variables.sh $(PREFIX)/lib/dystopian-libs/libtools-variables.sh
	install -m 640 lib/libhelper.sh $(PREFIX)/lib/dystopian-libs/libhelper.sh
	install -m 640 lib/libssl.sh $(PREFIX)/lib/dystopian-libs/libssl.sh
	install -m 640 lib/libgpg.sh $(PREFIX)/lib/dystopian-libs/libgpg.sh
	install -m 640 lib/libcrypto-db.sh $(PREFIX)/lib/dystopian-libs/libcrypto-db.sh
	install -m 640 lib/libsecboot.sh $(PREFIX)/lib/dystopian-libs/libsecboot.sh
	install -m 640 lib/libsecboot-db.sh $(PREFIX)/lib/dystopian-libs/libsecboot-db.sh
	install -m 640 lib/libhosts.sh $(PREFIX)/lib/dystopian-libs/libhosts.sh
	install -m 640 lib/libhosts-db.sh $(PREFIX)/lib/dystopian-libs/libhosts-db.sh
	install -m 640 lib/libaurtool.sh $(PREFIX)/lib/dystopian-libs/libaurtool.sh
	install -m 640 lib/libaurtool-db.sh $(PREFIX)/lib/dystopian-libs/libaurtool-db.sh
	install -d -m 755 $(PREFIX)/share/doc/dystopian-libs
	install -m 644 README.md $(PREFIX)/share/doc/dystopian-libs/README.md

remove-shared:
	rm -f $(PREFIX)/lib/dystopian-libs/libtools-variables.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libadmintools-variables.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libhelper.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libssl.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libgpg.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libcrypto-db.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libsecboot.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libsecboot-db.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libaurtool.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libaurtool-db.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libhosts.sh
	rm -f $(PREFIX)/lib/dystopian-libs/libhosts-db.sh
	rmdir $(PREFIX)/lib/dystopian-libs || true
	rm -f $(PREFIX)/share/doc/dystopian-libs/README.md
	rmdir $(PREFIX)/share/doc/dystopian-libs || true
