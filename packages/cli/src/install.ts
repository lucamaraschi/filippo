import { writeFile, mkdir, access, unlink } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { execSync } from "node:child_process";
import chalk from "chalk";
import { findDaemon, printInstallInstructions } from "./daemon.js";

const LABEL = "com.filippo.agent";

export function launchAgentsDir(): string {
  return join(homedir(), "Library", "LaunchAgents");
}

export function plistPath(): string {
  return join(launchAgentsDir(), `${LABEL}.plist`);
}

export async function hasLaunchAgent(): Promise<boolean> {
  try {
    await access(plistPath());
    return true;
  } catch {
    return false;
  }
}

export function generatePlist(binaryPath: string): string {
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
    <string>/tmp/filippo.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/filippo.err</string>
</dict>
</plist>`;
}

export async function install(binaryPath?: string) {
  const bin = binaryPath ?? (await findDaemon());

  if (!bin) {
    printInstallInstructions();
    console.log(
      chalk.dim("  Once installed, run `filippo install` again to set up auto-start.\n"),
    );
    process.exit(1);
  }

  // Verify binary exists
  try {
    await access(bin);
  } catch {
    printInstallInstructions();
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
    console.log(chalk.green("Launch agent loaded. filippo will start at login."));
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
    await unlink(plistPath());
    console.log(`Removed ${plistPath()}`);
  } catch {
    // Doesn't exist
  }

  console.log(chalk.green("filippo uninstalled from auto-start."));
}
