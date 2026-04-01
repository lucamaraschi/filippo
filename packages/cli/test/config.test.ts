import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  defaultConfig,
  loadConfig,
  saveConfig,
  setStatus,
  statusOf,
} from "../src/config.ts";

test("loadConfig returns defaults when the file does not exist", async () => {
  const dir = await mkdtemp(join(tmpdir(), "filippo-config-missing-"));
  const path = join(dir, "config.toml");

  assert.deepEqual(await loadConfig(path), defaultConfig());
});

test("loadConfig merges partial config with defaults", async () => {
  const dir = await mkdtemp(join(tmpdir(), "filippo-config-partial-"));
  const path = join(dir, "config.toml");

  await writeFile(
    path,
    [
      "[defaults]",
      'unknown = "visible"',
      "",
      "[icons]",
      'visible = ["Clock"]',
      "",
    ].join("\n"),
    "utf-8",
  );

  const loaded = await loadConfig(path);
  assert.equal(loaded.defaults.unknown, "visible");
  assert.equal(loaded.defaults.poll_interval, 5);
  assert.deepEqual(loaded.icons.visible, ["Clock"]);
  assert.deepEqual(loaded.icons.hidden, []);
  assert.deepEqual(loaded.icons.disabled, []);
});

test("saveConfig writes TOML and loadConfig reads it back", async () => {
  const dir = await mkdtemp(join(tmpdir(), "filippo-config-roundtrip-"));
  const path = join(dir, "nested", "config.toml");
  const cfg = {
    defaults: { unknown: "disabled" as const, poll_interval: 9 },
    icons: {
      visible: ["Clock"],
      hidden: ["Bluetooth"],
      disabled: ["Dropbox"],
    },
  };

  await saveConfig(cfg, path);

  const content = await readFile(path, "utf-8");
  assert.match(content, /\[defaults\]/);
  assert.deepEqual(await loadConfig(path), cfg);
});

test("statusOf falls back to unknown when an icon is not configured", () => {
  const cfg = defaultConfig();
  cfg.defaults.unknown = "disabled";

  assert.equal(statusOf(cfg, "Clock"), "disabled");
});

test("setStatus moves an icon between buckets without mutating input", () => {
  const cfg = {
    defaults: { unknown: "hidden" as const, poll_interval: 5 },
    icons: {
      visible: ["Clock"],
      hidden: ["Bluetooth"],
      disabled: ["Dropbox"],
    },
  };

  const next = setStatus(cfg, "Bluetooth", "visible");

  assert.deepEqual(next.icons.visible, ["Clock", "Bluetooth"]);
  assert.deepEqual(next.icons.hidden, []);
  assert.deepEqual(next.icons.disabled, ["Dropbox"]);

  assert.deepEqual(cfg.icons.visible, ["Clock"]);
  assert.deepEqual(cfg.icons.hidden, ["Bluetooth"]);
  assert.deepEqual(cfg.icons.disabled, ["Dropbox"]);
});
