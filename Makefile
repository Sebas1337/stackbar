# `make build` / `make test` work everywhere; `app`, `run` and `cert` need the macOS host.
SIGN_IDENTITY ?= Stackbar Dev
APP := build/Stackbar.app

.PHONY: build test app run cert clean

build:
	swift build

test:
	swift test

app:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/build-app.sh

# Quit a running Stackbar first and wait for it to exit, so `open` launches the new build.
run: app
	@if pkill -x Stackbar; then while pgrep -x Stackbar >/dev/null; do sleep 0.1; done; fi
	open "$(APP)"

cert:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/make-dev-cert.sh

clean:
	rm -rf build
