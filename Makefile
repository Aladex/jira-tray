PREFIX     := $(HOME)/.local
BINDIR     := $(PREFIX)/bin
WIDGET_DIR := $(HOME)/.local/share/plasma/plasmoids/com.github.aladex.jira-tray
AUTOSTART  := $(HOME)/.config/autostart/jira-tray.desktop

.PHONY: build install uninstall

build:
	go build -o jira-tray

install: build
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

uninstall:
	rm -f $(BINDIR)/jira-tray
	rm -rf $(WIDGET_DIR)
	rm -f $(AUTOSTART)
