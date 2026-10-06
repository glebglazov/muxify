APP := build/Build/Products/Debug/Muxify.app
RELEASE_APP := build/Build/Products/Release/Muxify.app
INSTALL_DIR ?= /Applications

.PHONY: all setup tools project build run install clean

all: build

setup: tools vendor/ghostty/lib/libghostty.a

tools:
	command -v xcodegen >/dev/null || brew install xcodegen

vendor/ghostty/lib/libghostty.a: | tools
	./scripts/setup-ghostty.sh

project: setup
	xcodegen generate --quiet

build: project
	xcodebuild -project Muxify.xcodeproj -scheme Muxify -configuration Debug \
		-derivedDataPath build -quiet build

run: build
	open $(APP)

install: project
	xcodebuild -project Muxify.xcodeproj -scheme Muxify -configuration Release \
		-derivedDataPath build -quiet build
	rm -rf "$(INSTALL_DIR)/Muxify.app"
	cp -R $(RELEASE_APP) "$(INSTALL_DIR)/"

clean:
	rm -rf build Muxify.xcodeproj
