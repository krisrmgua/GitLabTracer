import type { RingSlice, RingStatus } from "./logic";
import { encodePng, over, rasterize, segmentDistance, type RGBA } from "./png";

/**
 * Brightness of the moving gleam at `local` (0..1 inside one job's slice).
 * The gleam loops inside the orange fill and is zero past it.
 */
export function runningGleam(local: number, fill: number, phase: number): number {
  if (!(fill > 0) || local < 0 || local > fill) return 0;
  const pos = (phase - Math.floor(phase)) * fill;
  let dist = Math.abs(local - pos);
  if (dist > fill / 2) dist = fill - dist;
  const sigma = Math.max(1e-6, fill * 0.18 * (fill * 0.18));
  return Math.exp(-(dist * dist) / sigma);
}

const RING_COLORS: Record<RingStatus, [number, number, number]> = {
  passed: [52, 199, 89],
  running: [255, 149, 0],
  failed: [255, 59, 48],
  pending: [142, 142, 147],
  canceled: [142, 142, 147],
  skipped: [142, 142, 147],
};

/**
 * The tray ring: color is the status-card pipeline's state, the arc is how many of its jobs
 * finished. With unresolved failures it becomes a solid red disc with a white "!" so the
 * failure reads at a glance even on Windows, where the tray has no room for text.
 */
export function trayIconPng(
  status: RingStatus,
  progress: number,
  failing: boolean,
  size: number,
  slices: RingSlice[] = [],
  now = Date.now(),
): Buffer {
  const c = size / 2;
  const lineWidth = size * (3 / 20);
  const radius = size / 2 - lineWidth / 2 - size * 0.04;
  const [r, g, b] = RING_COLORS[failing ? "failed" : status];
  const trackAlpha = status === "pending" && !failing ? 0.7 : 0.3;
  const fraction = Math.min(Math.max(progress, 0), 1);
  const outer = size / 2 - size * 0.04;
  const white: RGBA = [255, 255, 255, 1];
  const gleamAt = (now % 1100) / 1100;

  return encodePng(
    size,
    size,
    rasterize(size, (x, y) => {
      const dx = x - c;
      const dy = y - c;
      const d = Math.hypot(dx, dy);
      if (failing) {
        if (d > outer) return null;
        const bar = segmentDistance(x, y, c, size * 0.24, c, size * 0.56) <= size * 0.075;
        const dot = Math.hypot(x - c, y - size * 0.74) <= size * 0.08;
        return bar || dot ? white : [r, g, b, 1];
      }
      if (Math.abs(d - radius) > lineWidth / 2) return null;
      // Angle from 12 o'clock, clockwise, 0..1.
      const angle = (Math.atan2(dx, -dy) / (2 * Math.PI) + 1) % 1;
      if (slices.length === 0) return angle <= fraction ? [r, g, b, 1] : [r, g, b, trackAlpha];
      const n = slices.length;
      const index = Math.min(n - 1, Math.floor(angle * n));
      const local = angle * n - index;
      const slice = slices[index];
      if (n > 1 && local > 0.94) return [r, g, b, trackAlpha * 0.35];
      const filled = slice.kind === "done" || local <= slice.fill;
      let rr = r;
      let gg = g;
      let bb = b;
      let alpha = filled ? 1 : trackAlpha;
      if (slice.kind === "running") {
        const gleam = runningGleam(local, slice.fill, gleamAt);
        rr = rr + (255 - rr) * gleam;
        gg = gg + (255 - gg) * gleam;
        bb = bb + (255 - bb) * gleam;
        alpha = Math.min(1, alpha + gleam * 0.85);
      }
      return [rr, gg, bb, alpha];
    }),
  );
}

const NODES: Array<[number, number]> = [
  [512, 736],
  [318, 624],
  [706, 624],
  [512, 512],
  [318, 400],
  [706, 400],
  [512, 288],
];
const LINKS: Array<[number, number]> = [
  [0, 1],
  [0, 2],
  [1, 3],
  [2, 3],
  [3, 4],
  [3, 5],
  [4, 6],
  [5, 6],
];

/** Same artwork as menubar/Artwork/generate-icon.swift: a navy tile with linked cyan nodes. */
export function appIconPng(size: number): Buffer {
  const s = 1024 / size;
  const top: [number, number, number] = [0.14 * 255, 0.25 * 255, 0.36 * 255];
  const bottom: [number, number, number] = [0.035 * 255, 0.07 * 255, 0.13 * 255];
  const radius = 202;
  return encodePng(
    size,
    size,
    rasterize(
      size,
      (px, py) => {
        const x = px * s;
        // Artwork coordinates have y pointing up, like AppKit.
        const y = 1024 - py * s;
        const qx = Math.max(Math.abs(x - 512) - (448 - radius), 0);
        const qy = Math.max(Math.abs(y - 512) - (448 - radius), 0);
        if (Math.hypot(qx, qy) > radius) return null;
        const t = (y - 64) / 896;
        let color: RGBA | null = [
          bottom[0] + (top[0] - bottom[0]) * t,
          bottom[1] + (top[1] - bottom[1]) * t,
          bottom[2] + (top[2] - bottom[2]) * t,
          1,
        ];
        for (const [a, b] of LINKS) {
          const [ax, ay] = NODES[a];
          const [bx, by] = NODES[b];
          if (segmentDistance(x, y, ax, ay, bx, by) <= 14) {
            color = over([0.2 * 255, 0.71 * 255, 0.86 * 255, 0.45], color);
            break;
          }
        }
        NODES.forEach(([nx, ny], index) => {
          if (Math.hypot(x - nx, y - ny) <= 69) {
            color = index === 3 ? [255, 255, 255, 1] : [0.24 * 255, 0.81 * 255, 0.94 * 255, 1];
          }
        });
        return color;
      },
      size >= 256 ? 2 : 4,
    ),
  );
}
