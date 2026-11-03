// Renders assets/icon.png (1024x1024) for electron-builder, which converts it to .icns and .ico.
// Run after `npm run build:electron`; the artwork lives in electron/icons.ts.
const fs = require("node:fs");
const path = require("node:path");
const { appIconPng } = require("../dist-electron/icons.js");

const out = path.join(__dirname, "..", "assets", "icon.png");
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, appIconPng(1024));
console.log(`Wrote ${path.relative(process.cwd(), out)}`);
