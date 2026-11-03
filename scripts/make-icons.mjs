// Writes assets/icon.png (1024px) from the compiled appIconPng, so electron-builder can
// make the .icns and .ico without a checked-in binary. Run after `npm run build:electron`.
import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
const { appIconPng } = require(path.join(root, "dist-electron", "icons.js"));

const out = path.join(root, "assets");
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, "icon.png"), appIconPng(1024));
console.log("Wrote assets/icon.png");
