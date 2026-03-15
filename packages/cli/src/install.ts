import { writeFile, mkdir, readFile, access } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { execSync } from "node:child_process";
import chalk from "chalk";

const LABEL = "com.menubar.agent";

function launchAgentsDir(): string {
  return join(homedir(), "Library", "LaunchAgents");
}

function plistPath(): string {
  return join(launchAgentsDir(), `${LABEL}.plist`);
}

function findDaemonBinary(): string {
  // Check common locations
  const candidates = [
    "/usr/local/bin/menubar-daemon",
    join(homedir(), ".nix-profile/bin/menubar-daemon"),
    join(homedir(), ".local/bin/menubar-daemon"),
  ];

  for (const p of candidates) {
    try {
      execSync(`test -x "${p}"`, { stdio: "ignore" });
      return p;
    } catch {
      // not found
    }
  }

  // Try which
  try {
    return execSync("which menubar-daemon", { encoding: "utf-8" }).trim();
  } catch {
    // fall through
  }

  // Default
  return "/usr/local/bin/menubar-daemon";
}

function generatePlist(binaryPath: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${binaryPath}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/menubar.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/menubar.err</string>
</dict>
</plist>`;
}

export async function install(binaryPath?: string) {
  const bin = binaryPath ?? findDaemonBinary();

  // Verify binary exists
  try {
    await access(bin);
  } catch {
    console.error(
      chalk.red(
        `Binary not found at ${bin}\n` +
          `Build the app first with 'make app' and 'make install', ` +
          `or pass the path: menubar install --binary /path/to/menubar-daemon`,
      ),
    );
    process.exit(1);
  }

  console.log(`Using binary: ${chalk.cyan(bin)}`);

  // Create LaunchAgents directory if needed
  await mkdir(launchAgentsDir(), { recursive: true });

  // Unload existing agent if present
  try {
    execSync(`launchctl unload "${plistPath()}" 2>/dev/null`, {
      stdio: "ignore",
    });
  } catch {
    // Not loaded, that's fine
  }

  // Write plist
  const plist = generatePlist(bin);
  await writeFile(plistPath(), plist, "utf-8");
  console.log(`Wrote launch agent to ${chalk.cyan(plistPath())}`);

  // Load the agent
  try {
    execSync(`launchctl load "${plistPath()}"`, { stdio: "inherit" });
    console.log(chalk.green("Launch agent loaded. MenuBarManager will start at login."));
  } catch {
    console.error(chalk.red("Failed to load launch agent."));
    process.exit(1);
  }
}

export async function uninstall() {
  // Unload
  try {
    execSync(`launchctl unload "${plistPath()}"`, { stdio: "ignore" });
    console.log("Launch agent unloaded.");
  } catch {
    // Not loaded
  }

  // Remove plist
  try {
    const { unlink } = await import("node:fs/promises");
    await unlink(plistPath());
    console.log(`Removed ${plistPath()}`);
  } catch {
    // Doesn't exist
  }

  console.log(chalk.green("MenuBarManager uninstalled."));
}
