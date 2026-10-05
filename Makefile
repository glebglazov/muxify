APP := build/Build/Products/Debug/Muxify.app

.PHONY: all setup project build run clean

all: build

setup: vendor/ghostty/lib/libghostty.a

vendor/ghostty/lib/libghostty.a:
	./scripts/setup-ghostty.sh

project: setup
	xcodegen generate --quiet

build: project
	xcodebuild -project Muxify.xcodeproj -scheme Muxify -configuration Debug \
		-derivedDataPath build -quiet build

run: build
	open $(APP)

clean:
	rm -rf build Muxify.xcodeproj
