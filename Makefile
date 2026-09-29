APP := build/Aurolight.app
PORT ?= $(firstword $(wildcard /dev/cu.usbserial-* /dev/cu.wchusbserial* /dev/cu.usbmodem*))
BOARD ?= nano
SWIFT_SOURCES := core/Package.swift core/Sources core/Tests macos/Package.swift macos/Sources macos/Tests
FIRMWARE_SOURCES := $(wildcard firmware/Aurolight/*.ino firmware/Aurolight/*.h)
SHELL_SCRIPTS := $(wildcard scripts/*.sh scripts/git-hooks/*)

.PHONY: build test benchmark benchmark-footage format format-check lint hooks app run release clean flash firmware

build:
	swift build --package-path macos

test:
	swift test --package-path core
	swift test --package-path macos

benchmark:
	AUROLIGHT_BENCHMARK=1 swift test --package-path core -c release --filter Benchmark

# Needs ffmpeg; downloads ~480 MB of open movies into .footage/ once.
benchmark-footage:
	./scripts/fetch-footage.sh
	AUROLIGHT_FOOTAGE=$(CURDIR)/.footage swift test --package-path core -c release --filter FootageBenchmark

format:
	swift format -i -r --parallel $(SWIFT_SOURCES)
	clang-format -i $(FIRMWARE_SOURCES)

format-check:
	swift format lint -s -r --parallel $(SWIFT_SOURCES)
	clang-format --dry-run -Werror $(FIRMWARE_SOURCES)

lint:
	swiftlint lint --quiet --strict
	shellcheck $(SHELL_SCRIPTS)
	cd macos && periphery scan --strict --quiet --disable-update-check

hooks:
	git config core.hooksPath scripts/git-hooks

app:
	./scripts/bundle-app.sh

run: app
	open $(APP)

release:
	./scripts/release.sh

clean:
	rm -rf core/.build macos/.build build firmware/.pio/build

# Quit the app first: the serial port can only be open in one program.
flash:
	pio run -d firmware -e $(BOARD) -t upload $(if $(PORT),--upload-port $(PORT))

firmware:
	pio run -d firmware $(foreach e,$(shell ./scripts/firmware-boards.sh),-e $(e))
