import { createCanvas, loadImage, type SKRSContext2D } from "@napi-rs/canvas";
import type { RingStatus } from "./logic";
import { trayIconPng } from "./icons";

const CAPSULE_FILL = "rgba(14, 23, 36, 0.84)"; // ~ Swift calibratedRed 0.055,0.09,0.14
const CAPSULE_STROKE = "rgba(255, 255, 255, 0.16)";
const DIVIDER = "rgba(255, 255, 255, 0.22)";
const LABEL_MR = "rgb(255, 255, 255)";
const LABEL_RUN = "rgb(50, 173, 230)"; // systemCyan-ish
const LABEL_FAIL = "rgb(255, 69, 58)"; // systemRed-ish

const HEIGHT = 26;
const PAD_Y = 3;
const RING_X = 5;
const RING_SIZE = HEIGHT - PAD_Y * 2; // 20
const FONT = '500 12px ".AppleSystemUIFontMonospacedDigit", "SF Pro Text", Menlo, monospace';

export interface CapsuleCounts {
  mergeRequests: number;
  running: number;
  failed: number;
}

function roundRect(
  ctx: SKRSContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number,
): void {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + w, y, x + w, y + h, radius);
  ctx.arcTo(x + w, y + h, x, y + h, radius);
  ctx.arcTo(x, y + h, x, y, radius);
  ctx.arcTo(x, y, x + w, y, radius);
  ctx.closePath();
}

function counterParts(counts: CapsuleCounts): { text: string; color: string }[] {
  const parts: { text: string; color: string }[] = [];
  if (counts.mergeRequests > 0) parts.push({ text: `MR ${counts.mergeRequests}`, color: LABEL_MR });
  if (counts.running > 0) parts.push({ text: `Run ${counts.running}`, color: LABEL_RUN });
  if (counts.failed > 0) parts.push({ text: `Fail ${counts.failed}`, color: LABEL_FAIL });
  return parts;
}

/**
 * Swift MenuBarCapsule: dark inset pill, progress ring, optional MR/Run/Fail counters.
 * Returns a 2× PNG buffer (width×height in points); caller sets scaleFactor.
 */
export async function trayCapsulePng(
  status: RingStatus,
  progress: number,
  failing: boolean,
  counts: CapsuleCounts,
): Promise<{ png: Buffer; width: number; height: number }> {
  const scale = 2;
  const measure = createCanvas(4, 4).getContext("2d");
  measure.font = FONT;
  const parts = counterParts(counts);
  const textWidths = parts.map((p) => Math.ceil(measure.measureText(p.text).width));
  const width = parts.length === 0
    ? RING_X + RING_SIZE + RING_X
    : 38 + textWidths.reduce((a, b) => a + b, 0) + Math.max(0, parts.length - 1) * 16;

  const canvas = createCanvas(Math.ceil(width * scale), Math.ceil(HEIGHT * scale));
  const ctx = canvas.getContext("2d");
  ctx.scale(scale, scale);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";

  // Capsule background (inset 1pt like Swift).
  roundRect(ctx, 1, 1, width - 2, HEIGHT - 2, 8);
  ctx.fillStyle = CAPSULE_FILL;
  ctx.fill();
  ctx.strokeStyle = CAPSULE_STROKE;
  ctx.lineWidth = 0.5;
  ctx.stroke();

  // Progress ring.
  const ringPng = trayIconPng(failing ? "failed" : status, progress, failing, RING_SIZE * scale);
  const ring = await loadImage(ringPng);
  ctx.drawImage(ring, RING_X, PAD_Y, RING_SIZE, RING_SIZE);

  // Counters + dividers. Center with glyph bounds — "middle" baseline sits optically high on SF.
  let x = RING_X + RING_SIZE + 6;
  ctx.textBaseline = "alphabetic";
  ctx.font = FONT;
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    const m = ctx.measureText(part.text);
    const ascent = m.actualBoundingBoxAscent || 9;
    const descent = m.actualBoundingBoxDescent || 3;
    const textY = (HEIGHT - (ascent + descent)) / 2 + ascent;
    ctx.fillStyle = part.color;
    ctx.fillText(part.text, x, textY);
    x += textWidths[i];
    if (i < parts.length - 1) {
      x += 8;
      ctx.strokeStyle = DIVIDER;
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      ctx.moveTo(x, PAD_Y + 2);
      ctx.lineTo(x, HEIGHT - PAD_Y - 2);
      ctx.stroke();
      x += 8;
    }
  }

  return { png: canvas.toBuffer("image/png"), width, height: HEIGHT };
}
