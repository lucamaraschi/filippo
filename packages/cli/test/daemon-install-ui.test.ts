import test from "node:test";
import assert from "node:assert/strict";
import { chmod, mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { defaultConfig } from "../src/config.ts";
import { getItemStatus, mergeItemsWithConfig } from "../src/configure.tsx";
import { checkDaemon, findDaemon } from "../src/daemon.ts";
import { generatePlist } from "../src/install.ts";

test("mergeItemsWithConfig prefers live items and appends config-only items once", () => {
  const merged = mergeItemsWithConfig(
    [{ name: "Clock", owner: "SystemUIServer", status: "visible", active: true }],
    {
      ...defaultConfig(),
      icons: {
        visible: ["Clock"],
        hidden: ["Bluetooth"],
        disabled: ["Dropbox"],
      },
    },
  );

  assert.deepEqual(merged, [
    { name: "Clock", owner: "SystemUIServer", active: true },
    { name: "Bluetooth", owner: "Bluetooth", active: false },
    { name: "Dropbox", owner: "Dropbox", active: false },
  ]);
});

test("getItemStatus resolves configured state and falls back to defaults", () => {
  const cfg = defaultConfig();
  cfg.defaults.unknown = "disabled";
  cfg.icons.visible.push("Clock");
  cfg.icons.hidden.push("Bluetooth");

  assert.equal(getItemStatus("Clock", cfg), "visible");
  assert.equal(getItemStatus("Bluetooth", cfg), "hidden");
  assert.equal(getItemStatus("Wi-Fi", cfg), "disabled");
});

test("generatePlist embeds the daemon path and launch label", () => {
  const plist = generatePlist("/tmp/filippod");

  assert.match(plist, /com\.filippo\.agent/);
  assert.match(plist, /\/tmp\/filippod/);
  assert.match(plist, /RunAtLoad/);
  assert.match(plist, /KeepAlive/);
});

test("findDaemon falls back to PATH lookup", async () => {
  const dir = await mkdtemp(join(tmpdir(), "filippo-daemon-"));
  const binary = join(dir, "filippod");

  await mkdir(dir, { recursive: true });
  await writeFile(binary, "#!/bin/sh\nexit 0\n", "utf-8");
  await chmod(binary, 0o755);

  const previous = process.env.PATH;
  process.env.PATH = `${dir}:${previous ?? ""}`;

  try {
    assert.equal(await findDaemon(), binary);
  } finally {
    if (previous === undefined) {
      delete process.env.PATH;
    } else {
      process.env.PATH = previous;
    }
  }
});

test("checkDaemon reports an installed daemon that is not running", async () => {
  const dir = await mkdtemp(join(tmpdir(), "filippo-daemon-status-"));
  const binary = join(dir, "filippod");

  await mkdir(dir, { recursive: true });
  await writeFile(binary, "#!/bin/sh\nexit 0\n", "utf-8");
  await chmod(binary, 0o755);

  const previous = process.env.PATH;
  process.env.PATH = `${dir}:${previous ?? ""}`;

  try {
    assert.deepEqual(await checkDaemon(), {
      installed: true,
      path: binary,
      running: false,
    });
  } finally {
    if (previous === undefined) {
      delete process.env.PATH;
    } else {
      process.env.PATH = previous;
    }
  }
});
