const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dir = __dirname, reportDir = path.resolve(dir, '../../../test_reports/fire-spikes-animation-20261105');
const partial = process.argv.includes('--completed-only');
const portableDir = path.join(reportDir, partial ? 'portable-partial' : 'portable');
const portableHtml = path.join(portableDir, 'gallery.html');
const rows = JSON.parse(fs.readFileSync(path.join(dir, 'requests.json'), 'utf8'));
const manifest = JSON.parse(fs.readFileSync(path.join(dir, partial ? 'pixellab-validation-partial.json' : 'pixellab-validation.json'), 'utf8'));
const selected = manifest.clips;
const expectedGroups = [...new Set(selected.map(x => x.source_key))];
const expectedGroupSizes = expectedGroups.map(key => selected.filter(x => x.source_key === key).length);
const expectedAssets = 2 * expectedGroups.length + (expectedGroups.includes('spike01') ? 1 : 0) + 2 * selected.length;
const assert = (condition, message) => { if (!condition) throw new Error(message); };

(async () => {
  assert(rows.length === 18, 'Expected 18 requests');
  assert(manifest.expected === 18 && manifest.completed === selected.length, 'Export manifest mismatch');
  assert(partial ? !manifest.complete : manifest.complete && selected.length === 18, 'Completion mode mismatch');
  fs.mkdirSync(portableDir, { recursive: true });
  fs.copyFileSync(path.join(dir, partial ? 'gallery-partial.html' : 'gallery.html'), portableHtml);
  assert(fs.readdirSync(portableDir).join() === 'gallery.html', 'Portable folder must contain only gallery.html');
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1800, height: 1200 } });
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(pathToFileURL(portableHtml).href);
    await page.waitForFunction(() => window.__galleryState && window.__galleryState().loaded);
    const report = await page.evaluate(() => ({
      state: window.__galleryState(), groups: document.querySelectorAll('#gallery section').length,
      cards: document.querySelectorAll('#gallery article').length,
      observationCards: [...document.querySelectorAll('#gallery article')].filter(card => card.textContent.includes('Наблюдение:')).length,
      sliders: [...document.querySelectorAll('#gallery input[type="range"]')].map(x => [x.min, x.max]),
      inputsLoaded: [...document.querySelectorAll('.source img')].every(x => x.naturalWidth === 256),
      cardStillsLoaded: [...document.querySelectorAll('article .pair img')].every(x => x.naturalWidth === 256),
      sameSizePairs: [...document.querySelectorAll('article .pair')].every(pair => {
        const still = pair.querySelector('img').getBoundingClientRect();
        const animated = pair.querySelector('canvas').getBoundingClientRect();
        return Math.abs(still.width - animated.width) <= 1 && Math.abs(still.height - animated.height) <= 1;
      }),
      groupSizes: [...document.querySelectorAll('#gallery section')].map(x => x.querySelectorAll('article').length),
    }));
    const setFrame = value => page.locator('#gallery input[type="range"]').first().evaluate((slider, frame) => {
      slider.value = String(frame); slider.dispatchEvent(new Event('input', { bubbles: true }));
    }, value);
    await setFrame(4);
    report.sliderFrame = (await page.evaluate(() => window.__galleryState().frames))[0];
    await page.locator('#step').click();
    report.stepFrame = (await page.evaluate(() => window.__galleryState().frames))[0];
    await page.locator('#restart').click();
    report.restartFrames = await page.evaluate(() => window.__galleryState().frames);
    await page.locator('#play').click();
    report.pausedBefore = await page.evaluate(() => window.__galleryState().frames);
    await page.waitForTimeout(250);
    report.pausedAfter = await page.evaluate(() => window.__galleryState().frames);
    const measureSpeed = async speed => {
      await page.locator('#speed').selectOption(String(speed));
      await page.locator('#restart').click();
      await page.waitForTimeout(650);
      await page.locator('#play').click();
      return (await page.evaluate(() => window.__galleryState().frames))[0];
    };
    report.slowSpeedFrame = await measureSpeed(0.5);
    report.fastSpeedFrame = await measureSpeed(2);
    await page.locator('#background').selectOption('checker');
    report.checkerVisible = await page.locator('.stage').first().evaluate(x => getComputedStyle(x).backgroundImage.includes('linear-gradient'));
    const measure = async () => page.evaluate(() => ({
      viewport: innerWidth, document: document.documentElement.scrollWidth,
      square: [...document.querySelectorAll('canvas')].every(x => {
        const r = x.getBoundingClientRect(); return Math.abs(r.width - r.height) <= 1;
      }),
      pairSame: [...document.querySelectorAll('article .pair')].every(pair => {
        const a = pair.querySelector('img').getBoundingClientRect();
        const b = pair.querySelector('canvas').getBoundingClientRect();
        return Math.abs(a.width - b.width) <= 1 && Math.abs(a.height - b.height) <= 1;
      }),
    }));
    report.desktop = {};
    for (const mode of ['', 'small', 'large']) {
      await page.locator('#size').selectOption(mode);
      report.desktop[mode || 'default'] = await measure();
    }
    await page.locator('#size').selectOption('');
    await page.screenshot({ path: path.join(reportDir, partial ? 'gallery-partial-desktop.png' : 'gallery-desktop.png') });
    await page.setViewportSize({ width: 390, height: 900 });
    report.mobile = {};
    for (const mode of ['', 'small', 'large']) {
      await page.locator('#size').selectOption(mode);
      report.mobile[mode || 'default'] = await measure();
    }
    report.oneWay = await page.evaluate(() => {
      const card = [...document.querySelectorAll('#gallery article')].find(x => x.querySelector('h3')?.textContent.startsWith('spike01-01'));
      if (!card) return null;
      const slider = card.querySelector('input[type="range"]');
      const count = Number(slider.max) + 1;
      slider.value = String(count - 1);
      slider.dispatchEvent(new Event('input', { bubbles: true }));
      const atEnd = card.querySelector('.note').textContent.includes('Кадр ' + count + ' / ' + count);
      card.querySelector('button').click();
      const reset = slider.value === '0';
      return { endpointImages: card.querySelectorAll('.pair img').length, count, atEnd, reset };
    });
    await page.screenshot({ path: path.join(reportDir, partial ? 'gallery-partial-mobile.png' : 'gallery-mobile.png'), fullPage: true });
    report.errors = errors;
    report.pass = report.state.clipCount === selected.length && report.state.assetCount === expectedAssets &&
      report.groups === expectedGroups.length && report.cards === selected.length && report.observationCards === selected.length &&
      report.groupSizes.every((x, i) => x === expectedGroupSizes[i]) &&
      report.inputsLoaded && report.cardStillsLoaded && report.sameSizePairs && report.sliders.length === selected.length &&
      report.sliders.every(([min, max], i) => min === '0' && max === String(selected[i].actual_frames - 1)) &&
      report.sliderFrame === 4 && report.stepFrame === 5 % selected[0].actual_frames &&
      report.restartFrames.every(x => x === 0) && report.pausedBefore.every((x, i) => x === report.pausedAfter[i]) &&
      report.fastSpeedFrame > report.slowSpeedFrame && report.checkerVisible &&
      Object.values(report.desktop).every(x => x.square && x.pairSame && x.document <= x.viewport) &&
      Object.values(report.mobile).every(x => x.square && x.pairSame && x.document <= x.viewport) &&
      (partial && !selected.some(x => x.source_key === 'spike01') ? report.oneWay === null :
        report.oneWay && report.oneWay.endpointImages === 2 && report.oneWay.atEnd && report.oneWay.reset) &&
      !errors.length;
    fs.writeFileSync(path.join(reportDir, partial ? 'browser-validation-partial.json' : 'browser-validation.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({ pass: report.pass, groups: report.groups, clips: report.cards, mobile: report.mobile, errors }));
    if (!report.pass) process.exitCode = 1;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
