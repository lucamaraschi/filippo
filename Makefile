.PHONY: all cli app clean install

all: cli app

# --- CLI (TypeScript + Ink) ---
cli:
	cd packages/cli && npm run build

cli-dev:
	cd packages/cli && npx tsx src/index.ts $(CMD)

cli-typecheck:
	cd packages/cli && npm run typecheck

# --- Swift Menu Bar App (filippo daemon) ---
app:
	cd app/MenuBarManager && swift build -c release

app-dev:
	cd app/MenuBarManager && swift run

# --- Install ---
install: all
	cp app/MenuBarManager/.build/release/MenuBarManager /usr/local/bin/filippo
	cd packages/cli && npm link

# --- Launch Agent ---
install-agent:
	@mkdir -p ~/Library/LaunchAgents
	@sed "s|__BINARY__|$$(which filippo 2>/dev/null || echo /usr/local/bin/filippo)|" \
		launchd/com.filippo.agent.plist > ~/Library/LaunchAgents/com.filippo.agent.plist
	launchctl load ~/Library/LaunchAgents/com.filippo.agent.plist

uninstall-agent:
	launchctl unload ~/Library/LaunchAgents/com.filippo.agent.plist 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/com.filippo.agent.plist

clean:
	rm -rf packages/cli/dist packages/cli/node_modules
	cd app/MenuBarManager && swift package clean
