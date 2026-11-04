const fs = require('node:fs');
const path = require('node:path');
const { createCanvas, loadImage } = require('@napi-rs/canvas');
async function board(rows, output) {
  const images = await Promise.all(rows.map(async row => ({ ...row, image: await loadImage(row.png) })));
  const width = Math.max(800, ...images.map(r => r.image.width + 48));
  const canvas = createCanvas(width, 64 + rows.length * 110);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#182c40'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#e8eff8'; ctx.font = '500 24px sans-serif';
  ctx.fillText('Menu bar · sample data', 24, 38);
  for (let i = 0; i < images.length; i++) {
    const row = images[i], y = 78 + i * 110;
    ctx.fillStyle = '#a9bbce'; ctx.font = '18px sans-serif'; ctx.fillText(row.label, 24, y);
    ctx.drawImage(row.image, 24, y + 12);
  }
  const file = path.join(output, 'menu-bar.png');
  fs.writeFileSync(file, canvas.toBuffer('image/png'));
  return { file: 'menu-bar.png', caption: 'Actual menu-bar renderer with synthetic values, arranged on a presentation backdrop.', size: { width, height: canvas.height } };
}
module.exports = async (_root, output) => {
  const { trayCapsulePng } = require('../../dist-electron/trayCapsule.js');
  const rows = [];
  for (const [label, status, progress, counts] of [
    ['Multiple requests and active pipelines', 'running', .55, { mergeRequests: 3, running: 2, failed: 1, mrTone: 'running' }],
    ['Ready to merge', 'passed', 1, { mergeRequests: 1, running: 0, failed: 0, mrTone: 'ready' }],
    ['Quiet state: zero counters hidden', 'passed', 1, { mergeRequests: 0, running: 0, failed: 0 }],
  ]) rows.push({ label, png: (await trayCapsulePng(status, progress, counts.failed > 0, counts)).png });
  return board(rows, output);
};
