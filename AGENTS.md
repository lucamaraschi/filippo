# Agents

## Project Overview

**Filippo** is a declarative, config-driven menu bar icon manager for macOS. It lets users control which app icons appear in the menu bar — visible, hidden behind a fold, or disabled entirely. Think Hidden Bar / Bartender but config-file-driven.

## Architecture

Two-component design connected via Unix domain socket (JSON protocol):

1. **Swift daemon (`filippod`)** — `app/MenuBarManager/`
   - Persistent background process that manipulates macOS menu bar icons
   - Uses `CGEvent` Cmd+drag technique (requires Accessibility permission)
   - Watches config file for live reload via `DispatchSource`
   - IPC server on Unix socket at `/tmp/filippo.sock`

2. **TypeScript CLI + TUI** — `packages/cli/`
   - CLI commands: `filippo configure|status|hide|show|show-all|disable|doctor|apply|install|uninstall`
   - TUI built with Ink (React for terminals)
   - Gracefully degrades when daemon isn't running

## Directory Structure

```
app/MenuBarManager/          # Swift daemon (SPM package, macOS 14+, Swift 5.9+)
packages/cli/                # TypeScript CLI (npm workspace, ESM, Node 20+)
launchd/                     # macOS launch agent plist template
homebrew/                    # Homebrew formula
config.example.toml          # Example config
```

## Configuration

- Location: `~/.config/filippo/config.toml`
- TOML format with three icon lists: `visible`, `hidden`, `disabled`
- Has `[defaults]` section with `unknown` behavior and `poll_interval`

## Build & Development

Prerequisites: Xcode 15+, Node 20+, npm

```bash
# Install npm dependencies
npm install

# Build everything
make all

# Build individually
make cli                # Build TS CLI (tsup)
make app                # Build Swift daemon (release)

# Development (no build step)
make cli-dev CMD=configure    # Run CLI/TUI directly via tsx
make app-dev                  # Run Swift daemon in debug mode

# Type-check
make cli-typecheck      # tsc --noEmit
```

There is no test suite yet. To verify changes:
- CLI: `make cli-typecheck` then `make cli-dev CMD=<command>`
- Swift: `cd app/MenuBarManager && swift build`
- See `TESTING.md` for manual integration testing steps

## Code Conventions

- TypeScript: ESM modules, strict mode, React JSX for TUI components
- Swift: SPM project, AppKit + Carbon frameworks, Objective-C bridging for CGS APIs
- Config parsing: `smol-toml` (TS), `TOMLKit` (Swift)
- No linter or formatter configured — follow existing style
- Minimal comments, self-documenting code preferred

## Key Technical Details

- **macOS menu bar APIs**: No public API to hide other apps' icons. Uses `CGWindowListCopyWindowInfo` for discovery (no permission needed) and `CGEvent` posting for Cmd+drag hiding (needs Accessibility permission). Must poll — no notification API for status item changes.
- **IPC**: Unix domain socket at `/tmp/filippo.sock`, JSON request/response protocol
- **Binary naming**: daemon is `filippod`, CLI is `filippo` (avoid collision)

## Naming

- GitHub: `lucamaraschi/filippo`
- npm: `@filippo/cli`
- Homebrew: `lucamaraschi/tap`
- Nix flake: `github:lucamaraschi/filippo`

## Git

- Use descriptive commit messages explaining the "why"
- Group related changes into logical commits
- Don't push unless explicitly asked
