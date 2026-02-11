.PHONY: all build test clean install release

VERSION_FILE = VERSION
CHANGELOG_FILE = CHANGELOG.md
INSTALL_DIR = $(HOME)/.local/zh
BIN_DIR = $(HOME)/.local/bin

all: build test

build:
	@echo "Building ZettelHub..."
	# Add build steps here, e.g., rubocop lib/ if available

test:
	@echo "Running tests..."
	@for test_file in test/*_test.rb test/**/*_test.rb; do \
		if [ -f "$$test_file" ]; then \
			echo "Running $$test_file..."; \
			ruby -Ilib "$$test_file" || exit 1; \
		fi; \
	done
	@if command -v bats >/dev/null 2>&1; then \
		bats test/zk.bats; \
	else \
		echo "bats not installed, skipping shell script tests"; \
	fi

clean:
	@echo "Cleaning..."

install:
	mkdir -p $(INSTALL_DIR)
	cp -r bin lib examples $(INSTALL_DIR)/
	mkdir -p $(BIN_DIR)
	ln -sf $(INSTALL_DIR)/bin/zh $(BIN_DIR)/zh
	@BACKUP=$$(date +%Y%m%d%H%M%S); \
	BACKUP_DIR="$(HOME)/.config/zh/backups/$$BACKUP"; \
	if [ -f "$(HOME)/.config/zh/config.yaml" ] || [ -d "$(HOME)/.config/zh/templates" ]; then \
		mkdir -p "$$BACKUP_DIR/templates"; \
		[ -f "$(HOME)/.config/zh/config.yaml" ] && cp "$(HOME)/.config/zh/config.yaml" "$$BACKUP_DIR/"; \
		[ -d "$(HOME)/.config/zh/templates" ] && cp -r "$(HOME)/.config/zh/templates" "$$BACKUP_DIR/"; \
		echo "Backed up existing config and templates to $$BACKUP_DIR"; \
	fi; \
	mkdir -p $(HOME)/.config/zh/templates; \
	ruby -Ilib lib/install_config.rb "$(CURDIR)/examples/config/config.yaml" "$(HOME)/.config/zh/config.yaml" "$$BACKUP_DIR" || exit 1; \
	cp lib/templates/*.erb $(HOME)/.config/zh/templates/; \
	echo "Config and templates installed/updated in $(HOME)/.config/zh"
	@echo "Installed ZettelHub to $(INSTALL_DIR)"
	@echo "Symlink created: $(BIN_DIR)/zh"

release:
	@current_version=$$(cat $(VERSION_FILE)); \
	IFS='.' read -r major minor patch <<< "$$current_version"; \
	new_patch=$$((patch + 1)); \
	new_version="$$major.$$minor.$$new_patch"; \
	echo $$new_version > $(VERSION_FILE); \
	last_tag=$$(git describe --tags --abbrev=0 2>/dev/null || echo ""); \
	if [ -z "$$last_tag" ]; then \
		commits=$$(git log --oneline --no-merges); \
	else \
		commits=$$(git log --oneline --no-merges $$last_tag..HEAD); \
	fi; \
	echo -e "\n## $$new_version" >> $(CHANGELOG_FILE); \
	echo "$$commits" | sed 's/^/- /' >> $(CHANGELOG_FILE); \
	git add $(VERSION_FILE) $(CHANGELOG_FILE); \
	git commit -m "Release v$$new_version"; \
	git tag v$$new_version; \
	@echo "Released v$$new_version"
