import React, { useState } from "react";
import { Box, Text, useApp, useInput } from "ink";
import type { Config, Status } from "./config.js";
import type { MenuBarItem } from "./ipc.js";

interface ConfigureProps {
  config: Config;
  items: MenuBarItem[];
  configPath: string;
  onSave: (config: Config) => void;
}

const STATUS_COLORS: Record<Status, string> = {
  visible: "green",
  hidden: "yellow",
  disabled: "red",
};

const STATUS_SYMBOLS: Record<Status, string> = {
  visible: "●",
  hidden: "◐",
  disabled: "○",
};

export function Configure({ config, items, configPath, onSave }: ConfigureProps) {
  const { exit } = useApp();
  const [cursor, setCursor] = useState(0);
  const [cfg, setCfg] = useState(config);
  const [modified, setModified] = useState(false);

  const allItems = mergeItemsWithConfig(items, cfg);

  useInput((input, key) => {
    if (key.upArrow || input === "k") {
      setCursor((c) => Math.max(0, c - 1));
    } else if (key.downArrow || input === "j") {
      setCursor((c) => Math.min(allItems.length - 1, c + 1));
    } else if (input === "v") {
      updateStatus("visible");
    } else if (input === "h") {
      updateStatus("hidden");
    } else if (input === "d") {
      updateStatus("disabled");
    } else if (input === "s") {
      onSave(cfg);
      exit();
    } else if (input === "q" || key.escape) {
      exit();
    }
  });

  function updateStatus(status: Status) {
    const item = allItems[cursor];
    if (!item) return;

    const next = structuredClone(cfg);
    // Remove from all lists
    next.icons.visible = next.icons.visible.filter((n) => n !== item.name);
    next.icons.hidden = next.icons.hidden.filter((n) => n !== item.name);
    next.icons.disabled = next.icons.disabled.filter((n) => n !== item.name);

    // Add to target list
    switch (status) {
      case "visible":
        next.icons.visible.push(item.name);
        break;
      case "hidden":
        next.icons.hidden.push(item.name);
        break;
      case "disabled":
        next.icons.disabled.push(item.name);
        break;
    }

    setCfg(next);
    setModified(true);
  }

  return (
    <Box flexDirection="column" padding={1}>
      <Box marginBottom={1}>
        <Text bold color="blueBright">
          {" "}Menu Bar Icons
        </Text>
        {modified && (
          <Text color="yellow"> (modified)</Text>
        )}
      </Box>

      {allItems.map((item, i) => {
        const selected = i === cursor;
        const status = getItemStatus(item.name, cfg);

        return (
          <Box key={item.name}>
            <Text color={selected ? "cyan" : undefined}>
              {selected ? "❯ " : "  "}
            </Text>
            <Text color={STATUS_COLORS[status]}>
              {STATUS_SYMBOLS[status]}
            </Text>
            <Text bold={selected}>
              {" "}
              {item.name}
            </Text>
            <Text dimColor>
              {"  "}
              {item.owner !== item.name ? item.owner : ""}
              {!item.active ? " (not running)" : ""}
            </Text>
            <Text color={STATUS_COLORS[status]} dimColor>
              {"  "}[{status}]
            </Text>
          </Box>
        );
      })}

      <Box marginTop={1}>
        <Text dimColor>
          {"  "}
          <Text color="green">[v]</Text>isible{"  "}
          <Text color="yellow">[h]</Text>idden{"  "}
          <Text color="red">[d]</Text>isabled{"  "}
          [s]ave & quit{"  "}
          [q]uit
        </Text>
      </Box>
    </Box>
  );
}

interface DisplayItem {
  name: string;
  owner: string;
  active: boolean;
}

export function mergeItemsWithConfig(
  liveItems: MenuBarItem[],
  cfg: Config,
): DisplayItem[] {
  const items: DisplayItem[] = [];
  const seen = new Set<string>();

  // Live items first
  for (const item of liveItems) {
    seen.add(item.name);
    items.push({ name: item.name, owner: item.owner, active: item.active });
  }

  // Config-only items (not currently running)
  for (const name of [
    ...cfg.icons.visible,
    ...cfg.icons.hidden,
    ...cfg.icons.disabled,
  ]) {
    if (!seen.has(name)) {
      seen.add(name);
      items.push({ name, owner: name, active: false });
    }
  }

  return items;
}

export function getItemStatus(name: string, cfg: Config): Status {
  if (cfg.icons.visible.includes(name)) return "visible";
  if (cfg.icons.hidden.includes(name)) return "hidden";
  if (cfg.icons.disabled.includes(name)) return "disabled";
  return cfg.defaults.unknown;
}
