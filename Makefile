WIDGET_DIR := $(HOME)/.local/share/plasma/plasmoids/com.github.aladex.jira-tray

.PHONY: install uninstall dev package

install:
	mkdir -p $(WIDGET_DIR)/contents/ui
	mkdir -p $(WIDGET_DIR)/contents/config
	mkdir -p $(WIDGET_DIR)/contents/icons
	cp widget/metadata.json $(WIDGET_DIR)/metadata.json
	cp widget/contents/ui/main.qml $(WIDGET_DIR)/contents/ui/main.qml
	cp widget/contents/ui/ConfigGeneral.qml $(WIDGET_DIR)/contents/ui/ConfigGeneral.qml
	cp widget/contents/config/main.xml $(WIDGET_DIR)/contents/config/main.xml
	cp widget/contents/config/config.qml $(WIDGET_DIR)/contents/config/config.qml
	cp widget/contents/icons/jira-tray.svg $(WIDGET_DIR)/contents/icons/jira-tray.svg

dev: install
	nohup plasmashell --replace > /dev/null 2>&1 &
	@sleep 2
	@echo "reloaded"

package:
	cd widget && zip -r ../com.github.aladex.jira-tray.plasmoid metadata.json contents/
	@echo "created com.github.aladex.jira-tray.plasmoid"

uninstall:
	rm -rf $(WIDGET_DIR)
