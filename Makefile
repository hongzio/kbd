INSTALL_DIR := $(HOME)/Library/Input Methods

.PHONY: build test install uninstall log

build:
	sh scripts/build-app.sh

test:
	# swift-build doesn't find the Testing macro plugin once the package has remote
	# dependencies (Command Line Tools only); load it explicitly.
	swift test -Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib

install: build
	-killall kbd
	rm -rf "$(INSTALL_DIR)/kbd.app"
	cp -R build/kbd.app "$(INSTALL_DIR)/"
	swift scripts/register.swift "$(INSTALL_DIR)/kbd.app"
	# Menu bar input menu caches icons; launchd restarts it.
	-killall TextInputMenuAgent

uninstall:
	-killall kbd
	rm -rf "$(INSTALL_DIR)/kbd.app"

log:
	log stream --level info --predicate 'subsystem == "com.hongzio.inputmethod.kbd"'
