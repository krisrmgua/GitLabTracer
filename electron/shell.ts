import { execFile } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type Tool = "glab" | "gh";

export interface RunResult {
  /** Process exit code. -1 when the CLI is missing or could not start. */
  status: number;
  out: string;
}

const isWindows = process.platform === "win32";

/**
 * Apps started from Finder, a LaunchAgent, or the Start menu get a short PATH, so the usual
 * install locations for glab and gh are searched too. Nothing outside PATH-style folders is run.
 */
function wellKnownDirs(): string[] {
  const home = os.homedir();
  if (isWindows) {
    const env = process.env;
    const programFiles = env.ProgramFiles || "C:\\Program Files";
    const programFilesX86 = env["ProgramFiles(x86)"] || "C:\\Program Files (x86)";
    const localAppData = env.LOCALAPPDATA || path.join(home, "AppData", "Local");
    const programData = env.ProgramData || "C:\\ProgramData";
    return [
      path.join(programFiles, "GitHub CLI"),
      path.join(programFilesX86, "GitHub CLI"),
      path.join(programFiles, "glab"),
      path.join(localAppData, "Programs", "glab"),
      path.join(localAppData, "Microsoft", "WinGet", "Links"),
      path.join(home, "scoop", "shims"),
      path.join(programData, "chocolatey", "bin"),
    ];
  }
  return [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/opt/local/bin",
    path.join(home, ".local", "bin"),
    path.join(home, "bin"),
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin",
  ];
}

let extraDirs: string[] = [];
let resolved: Partial<Record<Tool, string | null>> = {};
let lastDiscovery = 0;

function searchDirs(): string[] {
  const fromEnv = (process.env.PATH ?? process.env.Path ?? "").split(path.delimiter);
  const seen = new Set<string>();
  const out: string[] = [];
  for (const dir of [...fromEnv, ...extraDirs, ...wellKnownDirs()]) {
    if (!dir) continue;
    const key = isWindows ? dir.toLowerCase() : dir;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(dir);
  }
  return out;
}

function isExecutable(file: string): boolean {
  try {
    if (!fs.statSync(file).isFile()) return false;
    if (!isWindows) fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function findOnPath(tool: Tool): string | null {
  // Windows builds of glab and gh are real .exe files, so no cmd.exe shim is ever needed.
  const name = isWindows ? `${tool}.exe` : tool;
  for (const dir of searchDirs()) {
    const candidate = path.join(dir, name);
    if (isExecutable(candidate)) return candidate;
  }
  return null;
}

function capture(file: string, args: string[], timeout: number): Promise<string> {
  return new Promise((resolve) => {
    execFile(file, args, { timeout, windowsHide: true, encoding: "utf8" }, (err, stdout) => {
      resolve(err ? "" : stdout);
    });
  });
}

/**
 * Picks up PATH entries the app process did not inherit: the login shell on macOS, and the
 * current user + machine PATH from the registry on Windows (so a fresh winget install works
 * without signing out).
 */
export async function discoverPath(): Promise<void> {
  lastDiscovery = Date.now();
  let raw = "";
  if (isWindows) {
    const ps = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    raw = await capture(
      ps,
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "[Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')",
      ],
      5000,
    );
  } else {
    const shell = process.env.SHELL || "/bin/zsh";
    const marker = "__PIPELINE_TRACER_PATH__";
    const out = await capture(shell, ["-lc", `printf '%s' "${marker}$PATH${marker}"`], 5000);
    raw = out.split(marker)[1] ?? "";
  }
  extraDirs = raw
    .trim()
    .split(path.delimiter)
    .map((d) => d.trim())
    .filter(Boolean);
  resolved = {};
}

export function toolPath(tool: Tool): string | null {
  if (!(tool in resolved)) resolved[tool] = findOnPath(tool);
  return resolved[tool] ?? null;
}

/** Re-checks a missing CLI at most once a minute, so installing glab or gh mid-session works. */
export async function refreshToolsIfMissing(): Promise<void> {
  if (toolPath("glab") && toolPath("gh")) return;
  if (Date.now() - lastDiscovery < 60_000) return;
  await discoverPath();
}

function childEnv(): NodeJS.ProcessEnv {
  return {
    ...process.env,
    PATH: searchDirs().join(path.delimiter),
    NO_COLOR: "1",
    CLICOLOR: "0",
    GH_PROMPT_DISABLED: "1",
    GH_NO_UPDATE_NOTIFIER: "1",
    NO_PROMPT: "1",
  };
}

/** Runs `glab` or `gh` directly (no shell). stderr is dropped, like the Swift app. */
export function run(tool: Tool, args: string[], timeout = 60_000): Promise<RunResult> {
  const file = toolPath(tool);
  if (!file) return Promise.resolve({ status: -1, out: "" });
  return new Promise((resolve) => {
    execFile(
      file,
      args,
      {
        env: childEnv(),
        timeout,
        maxBuffer: 64 * 1024 * 1024,
        windowsHide: true,
        encoding: "utf8",
      },
      (err, stdout) => {
        if (!err) return resolve({ status: 0, out: stdout });
        const code = (err as { code?: unknown }).code;
        resolve({ status: typeof code === "number" ? code : -1, out: stdout ?? "" });
      },
    );
  });
}

function parseJSON(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

/** `glab api <path>` parsed as JSON, or null on failure. */
export async function glabJSON(apiPath: string, method?: string): Promise<unknown> {
  const args = ["api", "--hostname", "gitlab.com"];
  if (method) args.push("-X", method);
  args.push(apiPath);
  const r = await run("glab", args);
  if (r.status !== 0 || !r.out) return null;
  return parseJSON(r.out) ?? null;
}

/** `glab api graphql -f query=…` data object, or null on failure. */
export async function glabGraphQL(query: string): Promise<Record<string, unknown> | null> {
  const r = await run("glab", ["api", "graphql", "--hostname", "gitlab.com", "-f", `query=${query}`]);
  if (r.status !== 0 || !r.out) return null;
  const root = parseJSON(r.out) as Record<string, unknown> | undefined;
  if (!root || root.errors != null) return null;
  return (root.data as Record<string, unknown>) ?? null;
}

/** `gh api graphql --hostname github.com` data object, or null on failure. */
export async function ghGraphQL(query: string): Promise<Record<string, unknown> | null> {
  const r = await run("gh", ["api", "graphql", "--hostname", "github.com", "-f", `query=${query}`]);
  if (r.status !== 0) return null;
  const root = parseJSON(r.out) as Record<string, unknown> | undefined;
  if (!root || root.errors != null) return null;
  return (root.data as Record<string, unknown>) ?? null;
}

/** `gh api --hostname github.com <path>`. 404 is a missing repo or disabled Actions, not a transport failure. */
export async function ghGET(apiPath: string): Promise<{ status: number; json: unknown }> {
  const r = await run("gh", ["api", "--hostname", "github.com", apiPath]);
  const json = parseJSON(r.out);
  if (json === undefined) return { status: r.status === 0 ? -1 : r.status, json: null };
  if (r.status !== 0) {
    const message = (json as Record<string, unknown> | null)?.message;
    return { status: message === "Not Found" ? 404 : r.status, json: null };
  }
  return { status: 0, json };
}

export function parseObject(text: string): Record<string, unknown> | null {
  const v = parseJSON(text);
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
}
