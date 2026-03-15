import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { parse, stringify } from "smol-toml";

export type Status = "visible" | "hidden" | "disabled";

export interface Config {
  defaults: {
    unknown: Status;
    poll_interval: number;
  };
  icons: {
    visible: string[];
    hidden: string[];
    disabled: string[];
  };
}

export function defaultPath(): string {
  return join(homedir(), ".config", "menubar", "config.toml");
}

export function defaultConfig(): Config {
  return {
    defaults: { unknown: "hidden", poll_interval: 5 },
    icons: { visible: [], hidden: [], disabled: [] },
  };
}

export async function loadConfig(path?: string): Promise<Config> {
  const p = path ?? defaultPath();
  try {
    const content = await readFile(p, "utf-8");
    const raw = parse(content) as Partial<Config>;
    const cfg = defaultConfig();
    if (raw.defaults?.unknown) cfg.defaults.unknown = raw.defaults.unknown;
    if (raw.defaults?.poll_interval)
      cfg.defaults.poll_interval = raw.defaults.poll_interval;
    if (raw.icons?.visible) cfg.icons.visible = raw.icons.visible;
    if (raw.icons?.hidden) cfg.icons.hidden = raw.icons.hidden;
    if (raw.icons?.disabled) cfg.icons.disabled = raw.icons.disabled;
    return cfg;
  } catch (e: any) {
    if (e.code === "ENOENT") return defaultConfig();
    throw e;
  }
}

export async function saveConfig(
  cfg: Config,
  path?: string,
): Promise<void> {
  const p = path ?? defaultPath();
  await mkdir(join(p, ".."), { recursive: true });
  const content = stringify(cfg);
  await writeFile(p, content, "utf-8");
}

export function statusOf(cfg: Config, name: string): Status {
  if (cfg.icons.visible.includes(name)) return "visible";
  if (cfg.icons.hidden.includes(name)) return "hidden";
  if (cfg.icons.disabled.includes(name)) return "disabled";
  return cfg.defaults.unknown;
}

export function setStatus(cfg: Config, name: string, status: Status): Config {
  const next = structuredClone(cfg);
  next.icons.visible = next.icons.visible.filter((n) => n !== name);
  next.icons.hidden = next.icons.hidden.filter((n) => n !== name);
  next.icons.disabled = next.icons.disabled.filter((n) => n !== name);

  switch (status) {
    case "visible":
      next.icons.visible.push(name);
      break;
    case "hidden":
      next.icons.hidden.push(name);
      break;
    case "disabled":
      next.icons.disabled.push(name);
      break;
  }

  return next;
}
