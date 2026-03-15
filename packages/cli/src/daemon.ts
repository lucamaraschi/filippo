import { access } from "node:fs/promises";
import { execSync } from "node:child_process";
import { join } from "node:path";
import { homedir } from "node:os";
import chalk from "chalk";

const DAEMON_NAME = "filippo";
const BREW_TAP = "filippo/tap";
const BREW_FORMULA = "filippo";

const SEARCH_PATHS = [
  "/usr/local/bin/filippo",
  "/opt/homebrew/bin/filippo",
  join(homedir(), ".nix-profile/bin/filippo"),
  join(homedir(), ".local/bin/filippo"),
];

export interface DaemonStatus {
  installed: boolean;
  path: string | null;
  running: boolean;
}

export async function findDaemon(): Promise<string | null> {
  // Check common paths
  for (const p of SEARCH_PATHS) {
    try {
      await access(p);
      return p;
    } catch {
      // not found here
    }
  }

  // Try which/where
  try {
    return execSync(`which ${DAEMON_NAME} 2>/dev/null`, { encoding: "utf-8" }).trim() || null;
  } catch {
    return null;
  }
}

export async function checkDaemon(): Promise<DaemonStatus> {
  const path = await findDaemon();
  let running = false;

  if (path) {
    try {
      execSync(`pgrep -f "${path}" >/dev/null 2>&1`);
      running = true;
    } catch {
      // Not running
    }
  }

  return { installed: path !== null, path, running };
}

export function printInstallInstructions(): void {
  console.log(
    chalk.yellow.bold(`\n  ${DAEMON_NAME} is not installed.\n`),
  );
  console.log(
    `  The ${chalk.cyan(DAEMON_NAME)} daemon is required to manage menu bar icons.`,
  );
  console.log(`  It runs in the background and does the actual hiding/showing.\n`);
  console.log(chalk.bold("  Install via Homebrew (recommended):"));
  console.log(chalk.cyan(`    brew install ${BREW_TAP}/${BREW_FORMULA}\n`));
  console.log(chalk.bold("  Install via Nix:"));
  console.log(chalk.cyan(`    nix profile install github:filippo/menubar#filippo\n`));
  console.log(chalk.bold("  Install from source:"));
  console.log(chalk.cyan("    git clone https://github.com/filippo/menubar"));
  console.log(chalk.cyan("    cd menubar && make app install\n"));
  console.log(
    chalk.dim(
      `  After installing, start it with: ${chalk.reset("filippo")}`,
    ),
  );
  console.log(
    chalk.dim(
      `  Or set it to auto-start with:    ${chalk.reset("menubar install")}`,
    ),
  );
  console.log();
}

export function printNotRunningMessage(): void {
  console.log(
    chalk.yellow(`\n  ${DAEMON_NAME} is installed but not running.\n`),
  );
  console.log(chalk.bold("  Start it with:"));
  console.log(chalk.cyan(`    filippo\n`));
  console.log(chalk.bold("  Or auto-start on login:"));
  console.log(chalk.cyan(`    menubar install\n`));
}
