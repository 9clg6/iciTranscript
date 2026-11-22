VERSION ?= $(shell grep '^version:' apps/app_macos/pubspec.yaml | head -1 | awk '{print $$2}')
APP_NAME = Oats
BUILD_DIR = apps/app_macos/build/macos/Build/Products/Release

.PHONY: build sign dmg clean

build:
	cd apps/app_macos && flutter build macos --release

sign: build
	codesign --sign - --deep --force "$(BUILD_DIR)/$(APP_NAME).app"

dmg: sign
	create-dmg \
		--volname "Oats" \
		--window-pos 200 120 \
		--window-size 660 400 \
		--icon-size 80 \
		--icon "$(APP_NAME).app" 180 170 \
		--hide-extension "$(APP_NAME).app" \
		--app-drop-link 480 170 \
		--no-internet-enable \
		"Oats-v$(VERSION).dmg" \
		"$(BUILD_DIR)/$(APP_NAME).app"

clean:
	cd apps/app_macos && flutter clean
