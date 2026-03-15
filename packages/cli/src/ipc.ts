import { connect, type Socket } from "node:net";
import { join } from "node:path";
import { homedir } from "node:os";

export interface MenuBarItem {
  name: string;
  owner: string;
  status: string;
  active: boolean;
}

export interface IPCRequest {
  type: string;
  payload?: unknown;
}

export interface IPCResponse {
  success: boolean;
  error?: string;
  data?: unknown;
}

export function socketPath(): string {
  return join(
    homedir(),
    "Library",
    "Application Support",
    "menubar",
    "menubar.sock",
  );
}

function connectToSocket(): Promise<Socket> {
  return new Promise((resolve, reject) => {
    const sock = connect(socketPath(), () => resolve(sock));
    sock.on("error", reject);
  });
}

export async function sendRequest(req: IPCRequest): Promise<IPCResponse> {
  const sock = await connectToSocket();

  return new Promise((resolve, reject) => {
    let data = "";

    sock.on("data", (chunk) => {
      data += chunk.toString();
      // Responses are newline-delimited JSON
      const newlineIdx = data.indexOf("\n");
      if (newlineIdx !== -1) {
        try {
          const resp = JSON.parse(data.slice(0, newlineIdx)) as IPCResponse;
          sock.destroy();
          resolve(resp);
        } catch (e) {
          sock.destroy();
          reject(new Error(`Invalid response: ${data}`));
        }
      }
    });

    sock.on("error", reject);
    sock.on("end", () => {
      if (data.trim()) {
        try {
          resolve(JSON.parse(data) as IPCResponse);
        } catch {
          reject(new Error(`Invalid response: ${data}`));
        }
      } else {
        reject(new Error("Connection closed without response"));
      }
    });

    sock.write(JSON.stringify(req) + "\n");
  });
}

export async function fetchItems(): Promise<MenuBarItem[]> {
  const resp = await sendRequest({ type: "list_items" });
  if (!resp.success) throw new Error(resp.error ?? "Failed to list items");
  return resp.data as MenuBarItem[];
}

export async function isAppRunning(): Promise<boolean> {
  try {
    await sendRequest({ type: "list_items" });
    return true;
  } catch {
    return false;
  }
}
