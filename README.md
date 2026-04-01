# Filippo

Filippo is a declarative, config-driven menu bar icon manager for macOS.

It lets you decide which menu bar icons are:

- `visible`
- `hidden` behind a fold
- `disabled`

Think Hidden Bar / Dozer, but driven by config and a CLI instead of manual arrangement as the primary workflow.

## Current Model

Filippo runs a background daemon, `filippod`, that manages menu bar icon placement using macOS accessibility-driven dragging under the hood.

The user-facing workflow is still declarative:

- configure icon state in `filippo configure`, in Filippo's native menu, or in `~/.config/filippo/config.toml`
- Filippo applies that state to the menu bar
- hidden icons live behind Filippo’s fold control

On macOS, status items reserve real menu bar slots. Filippo currently uses a Dozer-style two-control UI so that reserved slot is explicit and stable rather than behaving like a broken gap.

## Install

### Homebrew

Recommended:

```bash
brew install lucamaraschi/tap/filippo
```

This installs:

- `filippod` — the background daemon
- `filippo` — the CLI / TUI

### From Source

Prerequisites:

- macOS 14+
- Xcode 15+
- Node 20+
- npm

```bash
git clone https://github.com/lucamaraschi/filippo
cd filippo
make install
```

## Quick Start

Run the interactive configurator:

```bash
filippo configure
```

After saving, Filippo will ask whether the daemon should auto-start at login.

Once the daemon is running, you can also use Filippo directly from the menu bar:

- chevron control: expand or collapse the hidden section
- Filippo control: open the native Filippo menu
- native menu actions: `Start at login`, `Reload config`, and per-icon `Visible` / `Hidden` / `Disabled`

If you prefer to start it manually:

```bash
filippod
```

If you installed via Homebrew, you can also use:

```bash
brew services start filippo
```

## Accessibility Permission

Filippo requires Accessibility permission to control menu bar items.

On first run, macOS should prompt for it. If not, enable it manually in:

- `System Settings`
- `Privacy & Security`
- `Accessibility`

Without this permission, the daemon can read config but cannot move menu bar icons.

## Commands

```bash
filippo configure
filippo status
filippo apply
filippo show <icon-name>
filippo hide <icon-name>
filippo disable <icon-name>
filippo show-all
filippo doctor
filippo install
filippo uninstall
```

### Notes

- `filippo install` installs a launch agent for auto-start
- `filippo uninstall` removes that launch agent
- `filippo show-all` temporarily expands hidden icons without changing config
- the native menu bar UI can edit icon state directly once `filippod` is running

## Configuration

Config lives at:

```bash
~/.config/filippo/config.toml
```

Example:

```toml
[defaults]
unknown = "hidden"
poll_interval = 5

[icons]
visible = ["Control Center", "Clock"]
hidden = ["Bluetooth", "TimeMachine"]
disabled = ["Spotlight"]
```

Semantics:

- `visible`: always shown
- `hidden`: shown behind Filippo’s fold
- `disabled`: kept out of the visible bar
- `unknown`: default status for icons not listed explicitly

See [config.example.toml](/Users/batman/src/lm/filippo/config.example.toml).

## Development

Useful local targets:

```bash
make bootstrap
make cli-check
make app-check
make app-test
make reinstall
```

Run the daemon in debug mode:

```bash
cd app/MenuBarManager
FILIPPO_DEBUG=1 swift run
```

Manual verification notes live in [TESTING.md](/Users/batman/src/lm/filippo/TESTING.md).

Release notes are in [RELEASING.md](/Users/batman/src/lm/filippo/RELEASING.md).

## Limitations

- macOS does not provide a public API for controlling other apps’ menu bar icons
- Filippo relies on synthetic drag behavior internally
- system-managed icons can be less stable than third-party icons
- menu bar slot width is ultimately controlled by AppKit, so Filippo’s fold control uses an explicit two-control UI rather than pretending those reserved slots do not exist
