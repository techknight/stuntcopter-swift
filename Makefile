# StuntCopter for modern macOS.
#   make            build (debug)
#   make test       run the test suite
#   make app        release build → build/StuntCopter.app (ad-hoc signed)
#   make run        build and open the app
#   make universal  like `make app`, but arm64 + x86_64
#   make release    universal app, signed with your Developer ID (hardened runtime),
#                   notarized and stapled → build/StuntCopter-<version>.zip
#                   Local notarization uses a notarytool keychain profile, created once:
#                     xcrun notarytool store-credentials stuntcopter-notary \
#                       --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer UUID>
#                   CI passes NOTARY_ARGS="--key … --key-id … --issuer …" instead.
#   make dump       write every PICT/RGN/icon resource as PNG into build/dump
#   make resources  re-extract Resources/StuntCopter.rsrc from the original AppleDouble
#                   and regenerate Sources/StuntCopterCore/EmbeddedResources.swift
#   make golden     re-record the golden snapshot images used by the tests
#   make reference SYSTEM_IMAGE=<System 6.0.8 Startup.img>
#                   build an 800K boot floppy that runs the original 1987 StuntCopter
#   make text SYSTEM_IMAGE=<…>   re-render all of the game's text from Chicago 12 in that
#                   System 6 disk image (the font goes to build/, never into the repo)
#   (the last two need: python3 -m venv .venv && .venv/bin/pip install machfs)

APP      := build/StuntCopter.app
VERSION  := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
ZIP      := build/StuntCopter-$(VERSION).zip
SIGN_IDENTITY  ?= Developer ID Application
NOTARY_PROFILE ?= stuntcopter-notary
NOTARY_ARGS    ?= --keychain-profile $(NOTARY_PROFILE)
RSRC     := Resources/StuntCopter.rsrc
ICNS     := build/AppIcon.icns
TOOL     := .build/debug/rsrc-tool
ARCHFLAGS ?=

.PHONY: all build test app run release universal dump resources golden reference text clean

all: build

build:
	swift build

test:
	swift test

$(TOOL): Sources/rsrc-tool/main.swift $(wildcard Sources/ClassicToolbox/*.swift)
	swift build --product rsrc-tool

$(ICNS): $(RSRC) $(TOOL)
	@rm -rf build/AppIcon.iconset
	@mkdir -p build
	$(TOOL) iconset $(RSRC) build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $(ICNS)

app: $(ICNS)
	swift build -c release $(ARCHFLAGS)
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp "$$(swift build -c release $(ARCHFLAGS) --show-bin-path)/StuntCopter" $(APP)/Contents/MacOS/StuntCopter
	cp Support/Info.plist $(APP)/Contents/Info.plist
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP)
	@echo "Built $(APP)"

universal:
	$(MAKE) app ARCHFLAGS="--arch arm64 --arch x86_64"

run: app
	open $(APP)

release:
	$(MAKE) universal
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" $(APP)
	codesign --verify --strict --verbose=2 $(APP)
	@rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	xcrun notarytool submit $(ZIP) $(NOTARY_ARGS) --wait
	xcrun stapler staple $(APP)
	@rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)
	spctl --assess --type execute -vv $(APP)
	@echo "Release: $(ZIP)"

dump: $(TOOL)
	$(TOOL) dump $(RSRC) build/dump

resources: $(TOOL)
	$(TOOL) extract original/StuntCopter1.5.AppleDouble $(RSRC)
	$(TOOL) embed $(RSRC) Sources/StuntCopterCore/EmbeddedResources.swift EmbeddedResources

golden:
	RECORD_GOLDEN=1 swift test

reference:
	@test -n "$(SYSTEM_IMAGE)" || (echo "usage: make reference SYSTEM_IMAGE=<System Startup.img>"; exit 1)
	@mkdir -p build/reference
	.venv/bin/python Tools/make_reference_disk.py "$(SYSTEM_IMAGE)" build/reference/StuntCopter-boot.dsk

text:
	@test -n "$(SYSTEM_IMAGE)" || (echo "usage: make text SYSTEM_IMAGE=<System Startup.img>"; exit 1)
	@mkdir -p build
	cd Tools && ../.venv/bin/python extract_system_font.py "$(abspath $(SYSTEM_IMAGE))" ../build/Chicago12.FONT
	swift build --product rsrc-tool
	$(TOOL) text-sheet build/Chicago12.FONT $(RSRC) Resources/StuntCopter.textsheet
	$(TOOL) embed Resources/StuntCopter.textsheet Sources/StuntCopterCore/EmbeddedTextSheet.swift EmbeddedTextSheet

clean:
	rm -rf .build build
