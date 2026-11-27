// Renders the captioned App Store frames from the plain screenshots:
//   node render.js   (reads ../../iPhone 6.3in and ../../iPad 13in, writes ../iPhone 6.3in and ../iPad 13in)
// Needs Playwright's Chromium and network access for the Instrument web fonts.
const { chromium } = require('playwright');
const { readFileSync, mkdirSync } = require('fs');
const { pathToFileURL } = require('url');
const path = require('path');
const here = __dirname;
const captions = JSON.parse(readFileSync(path.join(here, 'captions.json'), 'utf8'));
const sets = [['iPhone 6.3in', 1206, 2622, 0], ['iPad 13in', 2064, 2752, 1]];
(async () => {
const browser = await chromium.launch();
for (const [dir, w, h, ipad] of sets) {
  const out = path.join(here, '..', dir); mkdirSync(out, { recursive: true });
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
  for (const [name, t] of captions) {
    const s = pathToFileURL(path.join(here, '..', '..', dir, name + '.png')).href;
    const url = pathToFileURL(path.join(here, 'frame.html')).href + '?' + new URLSearchParams({ t, s, w, h, ipad });
    await page.goto(url); await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => document.getElementById('s').complete);
    await page.screenshot({ path: path.join(out, name + '.png') });
  }
  await page.close();
}
await browser.close();
})();
