PREFIX     := $(HOME)/.local
BINDIR     := $(PREFIX)/bin
WIDGET_DIR := $(HOME)/.local/share/plasma/plasmoids/com.github.aladex.jira-tray
AUTOSTART  := $(HOME)/.config/autostart/jira-tray.desktop

.PHONY: build install uninstall dev package

build:
	go build -o jira-tray

install: build
	-pkill -x jira-tray
	sleep 1
	mkdir -p $(BINDIR)
	cp jira-tray $(BINDIR)/jira-tray
	mkdir -p $(WIDGET_DIR)/contents/ui
	mkdir -p $(WIDGET_DIR)/contents/config
	cp widget/metadata.json $(WIDGET_DIR)/metadata.json
	cp widget/contents/ui/main.qml $(WIDGET_DIR)/contents/ui/main.qml
	cp widget/contents/ui/ConfigGeneral.qml $(WIDGET_DIR)/contents/ui/ConfigGeneral.qml
	cp widget/contents/config/main.xml $(WIDGET_DIR)/contents/config/main.xml
	cp widget/contents/config/config.qml $(WIDGET_DIR)/contents/config/config.qml
	mkdir -p $(HOME)/.config/autostart
	sed 's|HOME_PLACEHOLDER|$(HOME)|g' jira-tray.desktop > $(AUTOSTART)

dev: install
	nohup $(BINDIR)/jira-tray > /dev/null 2>&1 &
	nohup plasmashell --replace > /dev/null 2>&1 &
	@sleep 2
	@echo "reloaded"

package:
	cd widget && zip -r ../com.github.aladex.jira-tray.plasmoid metadata.json contents/
	@echo "created com.github.aladex.jira-tray.plasmoid"

uninstall:
	rm -f $(BINDIR)/jira-tray
	rm -rf $(WIDGET_DIR)
	rm -f $(AUTOSTART)
