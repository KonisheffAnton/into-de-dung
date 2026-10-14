const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {pathToFileURL} = require('node:url');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const browser = await chromium.launch({headless: true, channel: 'chrome'});
  try {
    const page = await browser.newPage({viewport: {width: 1728, height: 900}, deviceScaleFactor: 1});
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    await page.goto(pathToFileURL(path.join(__dirname, 'comparison.html')).href);
    await page.evaluate(() => window.ready);
    await page.screenshot({path: path.join(__dirname, 'comparison.png'), fullPage: true});
    await page.locator('#corrected').screenshot({path: path.join(__dirname, 'archer-corrected-on-tile.png')});
    const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, 'manifest.json'), 'utf8'));
    const sourceChecks = Object.entries(manifest.sources).map(([key, source]) => ({key,
      unchanged: crypto.createHash('sha256').update(fs.readFileSync(path.resolve(__dirname, '../../..', source.path))).digest('hex') === source.sha256}));
    await page.check('#axes');
    const axes = await page.isChecked('#axes');
    const dimensions = await page.evaluate(() => Object.fromEntries(['defender','original','corrected'].map(id => {
      const c = document.getElementById(id); return [id, [c.width, c.height]];
    })));
    if (errors.length || sourceChecks.some(item => !item.unchanged) || !axes ||
        Object.keys(dimensions).length !== 3 || manifest.geometry.corrected.height !== 51.840026784 ||
        manifest.geometry.corrected.scale !== 51.840026784 / (manifest.sources.corrected.bbox_alpha128[3] - manifest.sources.corrected.bbox_alpha128[1])) {
      throw new Error('Preview validation failed');
    }
    const result = {status: 'PASS', errors, source_checks: sourceChecks, axes_control: axes,
      canvas_dimensions: dimensions, corrected_alpha_height: manifest.sources.corrected.bbox_alpha128[3] - manifest.sources.corrected.bbox_alpha128[1],
      corrected_display_height: manifest.geometry.corrected.height,
      scope: 'HTML/source loading, controls, unchanged source hashes; visual QA separate. Not Godot/F5/GPU or art acceptance.'};
    fs.writeFileSync(path.join(__dirname, 'validation.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
