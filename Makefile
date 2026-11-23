APP := build/Clipman.app
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: app debug run install icon test clean

app:
	scripts/build-app.sh

debug:
	CONFIG=debug scripts/build-app.sh

run: debug
	-pkill -x Clipman
	open $(APP)

install: app
	-pkill -x Clipman
	rm -rf /Applications/Clipman.app
	cp -R $(APP) /Applications/
	open /Applications/Clipman.app

icon:
	scripts/make-icon.sh

test:
	swift test

clean:
	rm -rf .build build
