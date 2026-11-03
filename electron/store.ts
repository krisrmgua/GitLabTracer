import fs from "node:fs";
import path from "node:path";
import { app } from "electron";
import { DEFAULT_PREFS, sanitizePrefs, type Prefs } from "./logic";

interface StoreData {
  version: 1;
  prefs: Prefs;
  /** Failures already announced, including ones found on the first refresh. */
  notifiedFailureIDs: string[];
}

const MAX_NOTIFIED = 300;

/** Preferences and notification memory. Never credentials: glab and gh own the tokens. */
export class Store {
  private data: StoreData;
  private readonly file: string;

  constructor() {
    const dir = path.join(app.getPath("userData"), "data");
    fs.mkdirSync(dir, { recursive: true });
    this.file = path.join(dir, "pipelinetracer.json");
    this.data = this.load();
  }

  private load(): StoreData {
    try {
      const parsed = JSON.parse(fs.readFileSync(this.file, "utf8")) as Partial<StoreData>;
      return {
        version: 1,
        prefs: sanitizePrefs(parsed.prefs),
        notifiedFailureIDs: Array.isArray(parsed.notifiedFailureIDs)
          ? parsed.notifiedFailureIDs.filter((s): s is string => typeof s === "string").slice(-MAX_NOTIFIED)
          : [],
      };
    } catch {
      return { version: 1, prefs: { ...DEFAULT_PREFS }, notifiedFailureIDs: [] };
    }
  }

  private persist(): void {
    fs.writeFileSync(this.file, JSON.stringify(this.data, null, 2), { encoding: "utf8", mode: 0o600 });
  }

  get prefs(): Prefs {
    return { ...this.data.prefs };
  }

  setPrefs(input: Partial<Prefs>): Prefs {
    this.data.prefs = sanitizePrefs({ ...this.data.prefs, ...input }, this.data.prefs);
    this.persist();
    return this.prefs;
  }

  /** True the first time a failure key is seen. Remembered across launches. */
  claimFailure(key: string): boolean {
    const ids = this.data.notifiedFailureIDs;
    if (ids.includes(key)) return false;
    if (key.startsWith("gitlab:") && ids.includes(key.slice("gitlab:".length))) return false;
    ids.push(key);
    if (ids.length > MAX_NOTIFIED) ids.splice(0, ids.length - MAX_NOTIFIED);
    this.persist();
    return true;
  }
}
