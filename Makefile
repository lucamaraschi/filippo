.PHONY: help all bootstrap deps build cli cli-dev cli-typecheck cli-test cli-test-coverage cli-check cli-smoke doctor app app-dev app-check app-test test sanity install-daemon install-cli install reinstall uninstall install-agent uninstall-agent release-formula clean

SWIFT_SCRATCH_PATH ?= /tmp/filippo-swift-build
CLANG_MODULE_CACHE_PATH ?= /tmp/filippo-clang-cache
HOME_BIN_DIR := $(HOME)/.local/bin
ifneq ($(shell [ -w /opt/homebrew/bin ] && printf yes),)
DEFAULT_BIN_DIR := /opt/homebrew/bin
else ifneq ($(shell [ -w /usr/local/bin ] && printf yes),)
DEFAULT_BIN_DIR := /usr/local/bin
else
DEFAULT_BIN_DIR := $(HOME_BIN_DIR)
endif
BIN_DIR ?= $(DEFAULT_BIN_DIR)
DAEMON_SOURCE ?= app/MenuBarManager/.build/release/MenuBarManager
DAEMON_DEST ?= $(BIN_DIR)/filippod

help:
	@printf "filippo developer targets\n\n"
	@printf "  make bootstrap          Install npm workspace dependencies\n"
	@printf "  make build              Build both the CLI and daemon\n"
	@printf "  make cli                Build the CLI bundle\n"
	@printf "  make cli-dev CMD=...    Run a CLI command through tsx\n"
	@printf "  make cli-typecheck      Type-check the CLI\n"
	@printf "  make cli-test           Run CLI tests\n"
	@printf "  make cli-test-coverage  Run CLI tests with coverage\n"
	@printf "  make cli-check          Type-check, build, and test the CLI\n"
	@printf "  make cli-smoke          Run a quick offline CLI smoke test\n"
	@printf "  make doctor             Run the built CLI doctor command\n"
	@printf "  make app                Build the Swift daemon in release mode\n"
	@printf "  make app-dev            Run the Swift daemon in debug mode\n"
	@printf "  make app-check          Build the Swift daemon with writable scratch paths\n"
	@printf "  make app-test           Run Swift daemon tests\n"
	@printf "  make test               Run the default local verification suite\n"
	@printf "  make sanity             Run the full local verification suite, including coverage\n"
	@printf "  make install-daemon     Build and install filippod to $(DAEMON_DEST)\n"
	@printf "  make install-cli        npm link the filippo CLI\n"
	@printf "  make install            Build and install both daemon and CLI\n"
	@printf "  make reinstall          Rebuild and reinstall both daemon and CLI\n"
	@printf "  make uninstall          Remove installed daemon binary and npm unlink the CLI\n"
	@printf "  make release-formula    Render the Homebrew formula from VERSION, RELEASE_URL, and SHA256\n"
	@printf "\n"
	@printf "  Override install path with: make install BIN_DIR=$$HOME/.local/bin\n"
	@printf "  Example formula render: make release-formula VERSION=0.1.0 RELEASE_URL=https://... SHA256=...\n"
	@printf "  make clean              Remove local build artifacts\n"

all: cli app

bootstrap deps:
	npm install --workspace=packages/cli

build: all

# --- CLI (TypeScript + Ink) ---
cli:
	cd packages/cli && npm run build

cli-dev:
	cd packages/cli && npx tsx src/index.ts $(CMD)

cli-typecheck:
	cd packages/cli && npm run typecheck

cli-test:
	cd packages/cli && npm run test

cli-test-coverage:
	cd packages/cli && npm run test:coverage

cli-check: cli-typecheck cli cli-test

cli-smoke: cli
	cd packages/cli && node dist/index.js doctor
	cd packages/cli && node dist/index.js status

doctor: cli
	cd packages/cli && node dist/index.js doctor

# --- Swift Menu Bar App (filippo daemon) ---
app:
	cd app/MenuBarManager && swift build -c release

app-dev:
	cd app/MenuBarManager && swift run

app-check:
	cd app/MenuBarManager && env CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) swift build --scratch-path $(SWIFT_SCRATCH_PATH)

app-test:
	cd app/MenuBarManager && env CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) swift test --scratch-path /tmp/filippo-swift-test-build

test: bootstrap cli-check app-check app-test

sanity: bootstrap cli-check cli-test-coverage app-check app-test

# --- Install ---
install-daemon: app
	@mkdir -p $(BIN_DIR)
	@if [ ! -w "$(BIN_DIR)" ]; then \
		printf "BIN_DIR is not writable: %s\n" "$(BIN_DIR)"; \
		printf "Try: make install BIN_DIR=%s\n" "$(HOME_BIN_DIR)"; \
		exit 1; \
	fi
	install -m 755 $(DAEMON_SOURCE) $(DAEMON_DEST)
	@printf "Installed filippod to %s\n" "$(DAEMON_DEST)"
	@if [ "$(findstring $(HOME_BIN_DIR),$(BIN_DIR))" = "$(HOME_BIN_DIR)" ]; then \
		printf "Ensure %s is on your PATH.\n" "$(HOME_BIN_DIR)"; \
	fi

install-cli: bootstrap cli
	cd packages/cli && npm link

install: install-daemon install-cli

reinstall: build install

uninstall:
	rm -f $(DAEMON_DEST)
	cd packages/cli && npm unlink

# --- Launch Agent ---
install-agent:
	@mkdir -p ~/Library/LaunchAgents
	@daemon_path="$$(which filippod 2>/dev/null || echo $(DAEMON_DEST))"; \
	app_path="$${daemon_path%%/Contents/MacOS/*}"; \
	if [ "$$app_path" = "$$daemon_path" ]; then \
		app_path="$$daemon_path"; \
	fi; \
	sed "s|__APP__|$$app_path|" \
		launchd/com.filippo.agent.plist > ~/Library/LaunchAgents/com.filippo.agent.plist
	launchctl load ~/Library/LaunchAgents/com.filippo.agent.plist

uninstall-agent:
	launchctl unload ~/Library/LaunchAgents/com.filippo.agent.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.filippo.agent.plist

release-formula:
	@test -n "$(VERSION)" || (printf "VERSION is required\n" && exit 1)
	@test -n "$(RELEASE_URL)" || (printf "RELEASE_URL is required\n" && exit 1)
	@test -n "$(SHA256)" || (printf "SHA256 is required\n" && exit 1)
	@bash scripts/render_homebrew_formula.sh "$(VERSION)" "$(RELEASE_URL)" "$(SHA256)"

clean:
	rm -rf packages/cli/dist packages/cli/node_modules
	cd app/MenuBarManager && swift package clean
