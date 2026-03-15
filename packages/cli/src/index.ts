#!/usr/bin/env node

import { render } from "ink";
import React from "react";
import chalk from "chalk";
import {
  loadConfig,
  saveConfig,
  setStatus,
  defaultPath,
  type Config,
  type Status,
} from "./config.js";
import { fetchItems, sendRequest, isAppRunning, type MenuBarItem } from "./ipc.js";
import { Configure } from "./configure.js";
import { install, uninstall } from "./install.js";
import { checkDaemon, printInstallInstructions, printNotRunningMessage } from "./daemon.js";

const [, , command, ...args] = process.argv;

async function main() {
  switch (command) {
    case "configure":
      return cmdConfigure();
    case "status":
      return cmdStatus();
    case "apply":
      return cmdApply();
    case "show":
      return cmdSetStatus("visible", args[0]);
    case "hide":
      return cmdSetStatus("hidden", args[0]);
    case "disable":
      return cmdSetStatus("disabled", args[0]);
    case "show-all":
      return cmdShowAll();
    case "install":
      return install(args[0]);
    case "uninstall":
      return uninstall();
    case "doctor":
      return cmdDoctor();
    default:
      printUsage();
      process.exit(command ? 1 : 0);
  }
}

function printUsage() {
  console.log(`${chalk.bold("menubar")} - declarative menu bar icon manager

${chalk.dim("Usage:")}
  menubar configure          Interactive TUI to configure icon visibility
  menubar status             Show current state of all menu bar icons
  menubar apply              Apply config to running menu bar app
  menubar show <name>        Set an icon to visible
  menubar hide <name>        Set an icon to hidden
  menubar disable <name>     Set an icon to disabled
  menubar show-all           Temporarily show all hidden icons
  menubar install [binary]   Install launch agent for auto-start
  menubar uninstall          Remove launch agent
  menubar doctor             Check if filippo daemon is installed and running

${chalk.dim("Config:")} ${defaultPath()}`);
}

async function requireDaemon(): Promise<boolean> {
  const daemon = await checkDaemon();

  if (!daemon.installed) {
    printInstallInstructions();
    return false;
  }

  if (!daemon.running) {
    printNotRunningMessage();
    return false;
  }

  return true;
}

async function cmdDoctor() {
  const daemon = await checkDaemon();

  console.log(`\n  ${chalk.bold("filippo doctor")}\n`);

  // Daemon binary
  if (daemon.installed) {
    console.log(`  ${chalk.green("✓")} filippo daemon found at ${chalk.cyan(daemon.path)}`);
  } else {
    console.log(`  ${chalk.red("✗")} filippo daemon not found`);
  }

  // Daemon running
  if (daemon.running) {
    console.log(`  ${chalk.green("✓")} filippo daemon is running`);
  } else if (daemon.installed) {
    console.log(`  ${chalk.yellow("!")} filippo daemon is not running`);
  }

  // IPC socket
  if (await isAppRunning()) {
    console.log(`  ${chalk.green("✓")} IPC socket is responding`);
  } else {
    console.log(`  ${chalk.yellow("!")} IPC socket is not responding`);
  }

  // Config file
  try {
    await loadConfig();
    console.log(`  ${chalk.green("✓")} Config loaded from ${chalk.dim(defaultPath())}`);
  } catch (e: any) {
    console.log(`  ${chalk.red("✗")} Config error: ${e.message}`);
  }

  console.log();

  if (!daemon.installed) {
    printInstallInstructions();
  } else if (!daemon.running) {
    printNotRunningMessage();
  }
}

async function cmdConfigure() {
  const cfg = await loadConfig();
  let items: MenuBarItem[] = [];

  const daemon = await checkDaemon();

  if (!daemon.installed) {
    printInstallInstructions();
    console.log(
      chalk.dim("  You can still configure settings — they'll apply when filippo starts.\n"),
    );
    items = configToItems(cfg);
  } else if (await isAppRunning()) {
    items = await fetchItems();
  } else {
    printNotRunningMessage();
    console.log(
      chalk.dim("  You can still configure settings — they'll apply when filippo starts.\n"),
    );
    items = configToItems(cfg);
  }

  const { waitUntilExit } = render(
    React.createElement(Configure, {
      config: cfg,
      items,
      configPath: defaultPath(),
      onSave: async (newCfg: Config) => {
        await saveConfig(newCfg);
        console.log(chalk.green("Config saved to " + defaultPath()));

        if (await isAppRunning()) {
          await sendRequest({ type: "reload_config" });
          console.log(chalk.green("Config applied to running app."));
        }
      },
    }),
  );

  await waitUntilExit();
}

async function cmdStatus() {
  let items: MenuBarItem[];

  if (await isAppRunning()) {
    items = await fetchItems();
  } else {
    if (!(await requireDaemon())) {
      const cfg = await loadConfig();
      items = configToItems(cfg);
      console.log(chalk.dim("  Showing config only:\n"));
    } else {
      return;
    }
  }

  for (const item of items) {
    const color =
      item.status === "visible"
        ? chalk.green
        : item.status === "hidden"
          ? chalk.yellow
          : chalk.red;

    const active = item.active ? "" : chalk.dim(" (not running)");
    console.log(
      `  ${color("●")} ${item.name.padEnd(30)} ${color(item.status.padEnd(10))} ${chalk.dim(item.owner)}${active}`,
    );
  }
}

async function cmdApply() {
  if (!(await requireDaemon())) {
    process.exit(1);
  }

  const resp = await sendRequest({ type: "reload_config" });
  if (!resp.success) {
    console.error(chalk.red(`Apply failed: ${resp.error}`));
    process.exit(1);
  }
  console.log(chalk.green("Config applied."));
}

async function cmdSetStatus(status: Status, name?: string) {
  if (!name) {
    console.error(`Usage: menubar ${command} <icon-name>`);
    process.exit(1);
  }

  let cfg = await loadConfig();
  cfg = setStatus(cfg, name, status);
  await saveConfig(cfg);

  if (await isAppRunning()) {
    await sendRequest({ type: "reload_config" });
    console.log(chalk.green(`Set ${name} to ${status}.`));
  } else {
    console.log(
      chalk.green(
        `Set ${name} to ${status} (will apply when filippo starts).`,
      ),
    );
  }
}

async function cmdShowAll() {
  if (!(await requireDaemon())) {
    process.exit(1);
  }

  const resp = await sendRequest({ type: "show_all" });
  if (!resp.success) {
    console.error(chalk.red(`Failed: ${resp.error}`));
    process.exit(1);
  }
  console.log("All icons temporarily visible.");
}

function configToItems(cfg: Config): MenuBarItem[] {
  const items: MenuBarItem[] = [];
  for (const name of cfg.icons.visible) {
    items.push({ name, owner: name, status: "visible", active: false });
  }
  for (const name of cfg.icons.hidden) {
    items.push({ name, owner: name, status: "hidden", active: false });
  }
  for (const name of cfg.icons.disabled) {
    items.push({ name, owner: name, status: "disabled", active: false });
  }
  return items;
}

main().catch((e) => {
  console.error(chalk.red(`menubar: ${e.message}`));
  process.exit(1);
});
