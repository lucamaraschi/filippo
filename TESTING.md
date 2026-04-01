# Testing filippo — step by step

## Prerequisites

```bash
cd /Users/batman/src/lm/filippo
```

Make sure you have Node.js >= 20 and Xcode CLI tools installed.

## Fast path

If you just want the friendliest local flow, use the Make targets:

```bash
# Show all available developer targets
make help

# Install CLI dependencies once
make bootstrap

# Default local verification
make test

# Full local verification, including CLI coverage
make sanity
```

`make test` runs CLI typecheck, CLI build, CLI tests, and a Swift build using writable scratch paths.
`make sanity` does the same and also runs CLI coverage.

---

## Step 1: Build everything

```bash
# Install CLI dependencies
npm install

# Build CLI
npm run build --workspace=packages/cli

# Build Swift daemon (debug mode is faster for testing)
cd app/MenuBarManager && swift build && cd ../..
```

Expected: both build with no errors.

---

## Step 2: Test CLI without daemon (graceful degradation)

```bash
# Run the CLI — should show usage
npx --workspace=packages/cli filippo

# Doctor should report daemon not found
npx --workspace=packages/cli filippo doctor

# Status should show install instructions then fall back to config
npx --workspace=packages/cli filippo status
```

Expected: clear install instructions for `filippod`, no crashes.

---

## Step 3: Create a config file

```bash
mkdir -p ~/.config/filippo

cat > ~/.config/filippo/config.toml << 'EOF'
[defaults]
unknown = "visible"
poll_interval = 5

[icons]
visible = [
  "Control Center",
  "Clock",
]

hidden = [
  "Bluetooth",
]

disabled = []
EOF
```

Then verify the CLI reads it:

```bash
npx --workspace=packages/cli filippo status
```

Expected: shows Control Center (visible), Clock (visible), Bluetooth (hidden) — all marked "(not running)" since daemon isn't up.

---

## Step 4: Test the TUI configurator (offline mode)

```bash
npx --workspace=packages/cli filippo configure
```

Expected:
- Shows the install warning, then launches the TUI
- Lists the 3 icons from config with their statuses
- Arrow keys (or j/k) move the cursor
- `v`, `h`, `d` change status — you should see the indicator change color
- `s` saves and quits — verify `~/.config/filippo/config.toml` was updated
- (Or `q` quits without saving)

---

## Step 5: Start the daemon

Open a **new terminal** (the daemon needs to keep running):

```bash
cd /Users/batman/src/lm/filippo/app/MenuBarManager
swift run
```

First time: you'll get an **Accessibility permission** dialog.
1. Click "Open System Settings"
2. In System Settings → Privacy & Security → Accessibility, find MenuBarManager and enable it
3. The daemon will detect the permission within ~2 seconds and print "MenuBarManager started"

You should see a `‹` icon appear in your menu bar.

---

## Step 6: Test CLI with daemon running

In your original terminal:

```bash
# Doctor should show all green
npx --workspace=packages/cli filippo doctor

# Status should show live items from your actual menu bar
npx --workspace=packages/cli filippo status

# Hide an icon (pick one you see in status output)
npx --workspace=packages/cli filippo hide Bluetooth

# Show it again
npx --workspace=packages/cli filippo show Bluetooth

# Show all hidden icons temporarily
npx --workspace=packages/cli filippo show-all
```

Expected:
- `doctor` shows all green checkmarks
- `status` lists real menu bar icons with their statuses
- `hide`/`show` updates config AND tells the running daemon to reload
- `show-all` makes hidden icons temporarily visible

---

## Step 7: Test the TUI configurator (live mode)

```bash
npx --workspace=packages/cli filippo configure
```

Expected:
- Lists all **real** menu bar icons discovered by the daemon
- Changing a status with `v`/`h`/`d` and saving with `s` should:
  - Write to `~/.config/filippo/config.toml`
  - Tell the daemon to reload (you should see "Config file changed, reloading..." in the daemon terminal)

---

## Step 7b: Test the native menu UI

With the daemon running:

- click the Filippo control in the menu bar
- verify the menu shows daemon status and `Start at login`
- change one icon from `Hidden` to `Visible`
- change the same icon back to `Hidden`

Expected:
- the menu opens reliably
- `Start at login` toggles without crashing
- the selected icon changes state and the config file persists the change
- you may still see a single move animation, but not repeated reshuffling

---

## Step 8: Test config file live reload

With the daemon still running, edit the config directly:

```bash
cat > ~/.config/filippo/config.toml << 'EOF'
[defaults]
unknown = "hidden"
poll_interval = 3

[icons]
visible = ["Control Center"]
hidden = ["Bluetooth", "Clock"]
disabled = []
EOF
```

Expected: the daemon terminal should print "Config file changed, reloading..." and apply the new rules.

---

## Step 9: Test the menu bar toggle

- Click the `‹` icon in your menu bar → hidden icons should appear (icon changes to `›`)
- Click again → they hide again
- Click the Filippo control next to it → the Filippo menu should open without moving any icons by itself

---

## Step 10: Test late-arriving app detection

With the daemon running:

1. Quit an app that has a menu bar icon (e.g., if you see Docker in `filippo status`, quit Docker)
2. Relaunch that app
3. Within ~5 seconds (or 3s if you changed poll_interval), the daemon should detect the new icon and apply config rules

---

## Cleanup

Stop the daemon with Ctrl+C in its terminal.

To reset config:
```bash
rm -rf ~/.config/filippo
```

---

## Quick smoke test (all-in-one)

If you just want a fast check that both components build and talk to each other:

```bash
# Terminal 1: start daemon
cd app/MenuBarManager && swift run

# Terminal 2: verify connection
npx --workspace=packages/cli filippo doctor
npx --workspace=packages/cli filippo status
npx --workspace=packages/cli filippo configure
```
