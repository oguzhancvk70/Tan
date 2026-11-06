APP := Tan
BUILD := build.noindex
PRODUCT := $(BUILD)/Build/Products/Release/$(APP).app
ADAPTER := Resources/MediaRemoteAdapter.dylib
DMG := $(BUILD)/$(APP).dmg

.PHONY: gen build run install dmg install-dmg icon clean

$(ADAPTER): MediaRemoteAdapter/adapter.m
	clang -dynamiclib -fobjc-arc -framework Foundation -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 -o $@ $<
	codesign -f -s "Apple Development" $@

gen: $(ADAPTER)
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

dmg: build
	rm -rf $(BUILD)/dmg && mkdir -p $(BUILD)/dmg
	cp -R $(PRODUCT) $(BUILD)/dmg/
	ln -s /Applications $(BUILD)/dmg/Applications
	hdiutil create -volname $(APP) -srcfolder $(BUILD)/dmg -ov -format UDZO -quiet $(DMG)
	rm -rf $(BUILD)/dmg

install-dmg: dmg
	-pkill -x $(APP)
	-hdiutil detach $(BUILD)/mnt -quiet
	hdiutil attach $(DMG) -nobrowse -quiet -mountpoint $(BUILD)/mnt
	rm -rf /Applications/$(APP).app
	cp -R $(BUILD)/mnt/$(APP).app /Applications/
	hdiutil detach $(BUILD)/mnt -quiet
	open /Applications/$(APP).app

icon:
	swift Scripts/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf $(BUILD) $(APP).xcodeproj $(ADAPTER)
