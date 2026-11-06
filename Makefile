APP := Tan
BUILD := build
PRODUCT := $(BUILD)/Build/Products/Release/$(APP).app

.PHONY: gen build run install icon clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Release -derivedDataPath $(BUILD) -quiet build

run: build
	open $(PRODUCT)

install: build
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	cp -R $(PRODUCT) /Applications/
	open /Applications/$(APP).app

icon:
	swift Scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(BUILD) $(APP).xcodeproj
