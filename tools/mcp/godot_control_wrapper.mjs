import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { fileURLToPath } from "node:url";

const WRAPPER_DIR = path.dirname(fileURLToPath(import.meta.url));

const DEFAULT_CANDIDATES = [
  path.join(WRAPPER_DIR, "godot-mcp", "build", "index.js"),
  path.join(WRAPPER_DIR, "..", "..", "godot-mcp", "build", "index.js"),
];

function resolveMcpEntry() {
  const envEntry = process.env.GODOT_MCP_ENTRY;
  if (envEntry && envEntry.trim()) return envEntry.trim();

  for (const candidate of DEFAULT_CANDIDATES) {
    if (fs.existsSync(candidate)) return candidate;
  }

  console.error(
    "[godot_control_wrapper] GODOT_MCP_ENTRY is not set and no default entry was found.",
  );
  console.error(
    "[godot_control_wrapper] Set GODOT_MCP_ENTRY to the path of godot-mcp's build/index.js.",
  );
  console.error(
    `[godot_control_wrapper] Checked: ${DEFAULT_CANDIDATES.join(", ")}`,
  );
  process.exit(2);
}

const GODOT_MCP_ENTRY = resolveMcpEntry();

function encodeContentLengthFrame(jsonText) {
  const payload = Buffer.from(jsonText, "utf8");
  const header = Buffer.from(`Content-Length: ${payload.length}\r\n\r\n`, "ascii");
  return Buffer.concat([header, payload]);
}

function parseHeaders(headerText) {
  const headers = new Map();
  for (const line of headerText.split("\r\n")) {
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim().toLowerCase();
    const value = line.slice(idx + 1).trim();
    headers.set(key, value);
  }
  return headers;
}

function proxy() {
  const child = spawn(process.execPath, [GODOT_MCP_ENTRY], {
    stdio: ["pipe", "pipe", "pipe"],
    env: process.env,
  });

  child.on("exit", (code, signal) => {
    console.error(`[godot_control_wrapper] child exit code=${code} signal=${signal}`);
    process.exit(code ?? 1);
  });

  child.stderr.on("data", (chunk) => process.stderr.write(chunk));

  let clientFraming = null; // "content-length" | "newline"

  const childStdout = readline.createInterface({ input: child.stdout });
  childStdout.on("line", (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    if (clientFraming === "newline") {
      process.stdout.write(`${trimmed}\n`);
      return;
    }
    process.stdout.write(encodeContentLengthFrame(trimmed));
  });

  let stdinBuffer = Buffer.alloc(0);

  function processStdinBuffer() {
    while (stdinBuffer.length > 0) {
      const headerEnd = stdinBuffer.indexOf("\r\n\r\n");
      if (headerEnd !== -1) {
        const headerText = stdinBuffer.toString("ascii", 0, headerEnd);
        if (/^content-length:/i.test(headerText)) {
          const headers = parseHeaders(headerText);
          const lengthValue = headers.get("content-length");
          const contentLength = lengthValue ? Number.parseInt(lengthValue, 10) : NaN;
          if (!Number.isFinite(contentLength) || contentLength < 0) {
            console.error(
              `[godot_control_wrapper] invalid Content-Length: ${lengthValue ?? ""}`,
            );
            stdinBuffer = stdinBuffer.subarray(headerEnd + 4);
            continue;
          }

          const payloadStart = headerEnd + 4;
          const payloadEnd = payloadStart + contentLength;
          if (stdinBuffer.length < payloadEnd) return;

          const payload = stdinBuffer.toString("utf8", payloadStart, payloadEnd);
          stdinBuffer = stdinBuffer.subarray(payloadEnd);

          try {
            const msg = JSON.parse(payload);
            clientFraming = clientFraming ?? "content-length";
            child.stdin.write(`${JSON.stringify(msg)}\n`);
          } catch (err) {
            console.error(
              `[godot_control_wrapper] failed to parse framed JSON: ${err}`,
            );
          }
          continue;
        }
      }

      const nl = stdinBuffer.indexOf("\n");
      if (nl === -1) return;
      const line = stdinBuffer.toString("utf8", 0, nl).trim();
      stdinBuffer = stdinBuffer.subarray(nl + 1);
      if (!line) continue;

      try {
        const msg = JSON.parse(line);
        clientFraming = clientFraming ?? "newline";
        child.stdin.write(`${JSON.stringify(msg)}\n`);
      } catch (err) {
        console.error(`[godot_control_wrapper] failed to parse line JSON: ${err}`);
      }
    }
  }

  process.stdin.on("data", (chunk) => {
    stdinBuffer = Buffer.concat([stdinBuffer, chunk]);
    processStdinBuffer();
  });
  process.stdin.on("error", (err) => {
    console.error(`[godot_control_wrapper] stdin error: ${err}`);
  });

  for (const sig of ["SIGINT", "SIGTERM"]) {
    process.on(sig, () => {
      child.kill(sig);
      process.exit(0);
    });
  }
}

proxy();
