import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

async function withHomeDir<T>(fn: (home: string) => Promise<T>): Promise<T> {
  const previous = process.env.HOME;
  const home = await mkdtemp(join(tmpdir(), "filippo-home-"));
  process.env.HOME = home;

  try {
    return await fn(home);
  } finally {
    if (previous === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = previous;
    }
  }
}

test("socketPath resolves under the user home directory", async () => {
  await withHomeDir(async (home) => {
    const { socketPath } = await import("../src/ipc.ts");

    assert.equal(
      socketPath(),
      join(home, "Library", "Application Support", "filippo", "filippo.sock"),
    );
  });
});

test("parseResponse decodes valid IPC payloads", async () => {
  const { parseResponse } = await import("../src/ipc.ts");

  assert.deepEqual(parseResponse('{"success":true,"data":["ok"]}'), {
    success: true,
    data: ["ok"],
  });
});

test("parseResponse rejects invalid JSON payloads", async () => {
  const { parseResponse } = await import("../src/ipc.ts");

  assert.throws(() => parseResponse("not-json"), /Invalid response: not-json/);
});

test("isAppRunning returns false when the socket is unavailable", async () => {
  await withHomeDir(async () => {
    const { isAppRunning } = await import("../src/ipc.ts");
    assert.equal(await isAppRunning(), false);
  });
});
