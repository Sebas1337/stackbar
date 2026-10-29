# `make build` / `make test` work everywhere; `app`, `run` and `cert` need the macOS host.
SIGN_IDENTITY ?= Stackbar Dev
ARCHS ?= $(shell uname -m)
APP := build/Stackbar.app

.PHONY: build test app run cert clean

build:
	swift build

# Command Line Tools 26.3 ships _Testing_Foundation.framework without its module, so
# `import Testing` + `import Foundation` fails there. Point at the CLT frameworks and skip the
# cross-import overlay (not needed by our tests). Xcode, CI and Linux use plain `swift test`.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
ifeq ($(shell xcode-select -p 2>/dev/null),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F$(CLT_FRAMEWORKS) -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -F$(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

test:
	swift test $(TEST_FLAGS)

# ARCHS="arm64 x86_64" builds a universal binary (default: host architecture only).
app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" ARCHS="$(ARCHS)" scripts/build-app.sh

# Quit a running Stackbar first (force after 5 s) and wait for it to exit, so `open` launches the
# new build instead of re-activating the old one.
run: app
	@if pkill -x Stackbar; then \
		for _ in $$(seq 50); do pgrep -x Stackbar >/dev/null || break; sleep 0.1; done; \
		pkill -9 -x Stackbar || true; \
	fi
	open "$(APP)"

cert:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/make-dev-cert.sh

clean:
	rm -rf build
