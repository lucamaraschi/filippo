.PHONY: all cli app clean install

all: cli app

# --- CLI (TypeScript + Ink) ---
cli:
	cd packages/cli && npm run build

cli-dev:
	cd packages/cli && npx tsx src/index.ts $(ARGS)

cli-typecheck:
	cd packages/cli && npm run typecheck

# --- Swift Menu Bar App ---
app:
	cd app/MenuBarManager && swift build -c release

app-dev:
	cd app/MenuBarManager && swift run

# --- Install ---
install: all
	cp app/MenuBarManager/.build/release/MenuBarManager /usr/local/bin/menubar-daemon
	cd packages/cli && npm link

# --- Launch Agent ---
install-agent:
	@mkdir -p ~/Library/LaunchAgents
	@sed "s|__BINARY__|$$(which menubar-daemon 2>/dev/null || echo /usr/local/bin/menubar-daemon)|" \
		launchd/com.menubar.agent.plist > ~/Library/LaunchAgents/com.menubar.agent.plist
	launchctl load ~/Library/LaunchAgents/com.menubar.agent.plist

uninstall-agent:
	launchctl unload ~/Library/LaunchAgents/com.menubar.agent.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.menubar.agent.plist

clean:
	rm -rf packages/cli/dist packages/cli/node_modules
	cd app/MenuBarManager && swift package clean
