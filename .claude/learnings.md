# Learnings

## Key Decisions
- **Go -> TypeScript pivot**: User prefers TS/JS over Go for CLI tooling. Using Ink (React for CLIs) as the TUI framework instead of bubbletea.
- **Two-component architecture**: Swift menu bar app (persistent daemon) + TypeScript CLI (commands + TUI). Connected via Unix domain socket with JSON protocol.
- **TOMLKit for Swift TOML**: Only Swift SPM library that supports both reading and writing TOML. `pelletier/go-toml` equivalent.
- **CGEvent Cmd+drag for hiding**: Same technique as Ice. No public API exists to hide other apps' menu bar icons. Requires Accessibility permission.

## Problems Solved
- `sockaddr_un.sun_path` exclusive access error in Swift: Use `withUnsafeMutableBytes(of:)` + `copyBytes(from:)` instead of nested `withUnsafeMutablePointer`.
- `CGEventField` naming: Swift uses `.mouseEventWindowUnderMousePointer` (camelCase), not the older `.MouseEventWindowUnderMousePointer` or `.windowUnderMousePointer`.
- NSObjectProtocol conformance: Just make the class inherit from `NSObject` directly instead of manually implementing all protocol methods.

## Patterns & Conventions
- Config at `~/.config/menubar/config.toml` — follows XDG-ish convention, Nix-friendly
- Swift app watches config file with `DispatchSource.makeFileSystemObjectSource` for live reload
- CLI gracefully degrades when app isn't running (shows config-only items, saves config for later)
- Launch agent plist template in `launchd/` with `__BINARY__` placeholder

## Naming & References
- GitHub repo: `lucamaraschi/filippo` (not `filippo/menubar`)
- Homebrew tap: `lucamaraschi/tap`
- npm package: `@filippo/cli` (not `@menubar/cli`)
- Nix flake: `github:lucamaraschi/filippo`
- Binary name remains `filippo` — only URLs/package names changed

## Useful Commands
- `make app-dev` — run Swift app directly
- `make cli-dev ARGS=configure` — run TUI configurator
- `cd app/MenuBarManager && swift build` — build Swift app
- `cd cli && npx tsc --noEmit` — type-check CLI
- `cd cli && npm run build` — build CLI dist

## macOS Menu Bar APIs
- `CGWindowListCopyWindowInfo`: No permission needed for basic info (bounds, PID, window ID). Needs Screen Recording for window titles.
- `CGEvent` posting: Requires Accessibility permission
- No callback/notification for new status items — must poll (Ice uses 5s interval)
- Private CGS APIs (`CGSGetProcessMenuBarWindowList`) give better results but break across OS versions
