const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const dir = __dirname;
const reportDir = path.resolve(dir, '../../../test_reports/hazard-masked-retry-20261105');
const portableDir = path.join(reportDir, 'portable');
const html = path.join(portableDir, 'gallery.html');
const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'requests.json'), 'utf8'));
const assert = (condition, message) => { if (!condition) throw new Error(message); };

(async () => {
  assert(manifest.length === 15, 'Expected fifteen requests');
  fs.mkdirSync(portableDir, { recursive: true });
  fs.copyFileSync(path.join(dir, 'gallery.html'), html);
  assert(fs.readdirSync(portableDir).join() === 'gallery.html', 'Portable folder must contain only gallery.html');
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
    const errors = [];
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(pathToFileURL(html).href);
    await page.waitForFunction(() => window.__galleryState && window.__galleryState().loaded);
    const report = await page.evaluate(() => ({
      state: window.__galleryState(),
      groups: document.querySelectorAll('#gallery section').length,
      cards: document.querySelectorAll('#gallery article').length,
      staticImagesLoaded: [...document.querySelectorAll('.source img,article .panels img')].every(x => x.naturalWidth > 0),
      maskImagesLoaded: [...document.querySelectorAll('.masks img,.maskcontext img')].every(x => x.naturalWidth > 0),
      renderedCanvases: [...document.querySelectorAll('article canvas')].filter(c => {
        const data = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
        return data.some((v, i) => i % 4 === 3 && v > 0);
      }).length,
      observationCards: [...document.querySelectorAll('article')].filter(x => x.textContent.includes('Наблюдение:')).length,
      sliderMax: [...document.querySelectorAll('article input[type="range"]')].map(x => Number(x.max)),
    }));
    await page.locator('#step').click();
    report.stepFrames = await page.evaluate(() => window.__galleryState().frames);
    await page.locator('#reset').click();
    report.resetFrames = await page.evaluate(() => window.__galleryState().frames);
    await page.locator('#play').click();
    report.pausedBefore = await page.evaluate(() => window.__galleryState().positions);
    await page.waitForTimeout(450);
    report.pausedAfter = await page.evaluate(() => window.__galleryState().positions);
    await page.locator('#play').click();
    await page.locator('#speed').selectOption('2');
    await page.waitForTimeout(450);
    report.speedAdvanced = (await page.evaluate(() => window.__galleryState().positions))[0] > 0;
    await page.locator('#play').click();
    const glint03 = manifest.findIndex(x => x.key === 'caltrops03-03');
    const slider = page.locator('article input[type="range"]').nth(glint03);
    await slider.evaluate(el => { el.value = '5'; el.dispatchEvent(new Event('input', { bubbles: true })); });
    report.glint03RepeatedPose = (await page.evaluate(() => window.__galleryState().frames))[glint03] === 1;
    await page.locator('#maskToggle').click();
    report.maskContextsVisible = await page.locator('.maskcontext').first().evaluate(el => getComputedStyle(el).display !== 'none');
    await page.locator('#maskToggle').click();
    const measure = async () => page.evaluate(() => ({
      viewport: innerWidth,
      document: document.documentElement.scrollWidth,
      squares: [...document.querySelectorAll('article canvas')].every(c => {
        const r = c.getBoundingClientRect(); return Math.abs(r.width - r.height) <= 1;
      }),
    }));
    report.desktop = {};
    for (const mode of ['', 'small', 'large']) {
      await page.locator('#size').selectOption(mode);
      report.desktop[mode || 'default'] = await measure();
    }
    await page.locator('#size').selectOption('');
    await page.screenshot({ path: path.join(reportDir, 'gallery-desktop.png') });
    await page.setViewportSize({ width: 390, height: 900 });
    report.mobile = {};
    for (const mode of ['', 'small', 'large']) {
      await page.locator('#size').selectOption(mode);
      report.mobile[mode || 'default'] = await measure();
    }
    await page.locator('#size').selectOption('');
    await page.screenshot({ path: path.join(reportDir, 'gallery-mobile.png') });
    const timelinePage = await browser.newPage({ viewport: { width: 390, height: 900 } });
    await timelinePage.clock.install();
    await timelinePage.goto(pathToFileURL(html).href);
    await timelinePage.waitForFunction(() => window.__galleryState && window.__galleryState().loaded);
    await timelinePage.clock.runFor(16600);
    report.timeline = await timelinePage.evaluate(() => {
      const state = window.__galleryState();
      return CLIPS.filter(x => x.kind === 'glint').map(x => {
        const index = CLIPS.findIndex(y => y.key === x.key);
        return { key: x.key, events: state.events[index] };
      });
    });
    await timelinePage.close();
    const expectedTimeline = {
      'caltrops03-01': { frames: [1, 0, 2, 3, 0], times: [4000, 4160, 8160, 8320, 12320] },
      'caltrops03-02': { frames: [1, 0, 2, 3, 0], times: [5000, 5160, 10160, 10320, 15320] },
      'caltrops03-03': { frames: [1, 0, 2, 0, 1, 3, 0], times: [4000, 4160, 8160, 8320, 12320, 12480, 16480] },
    };
    report.timelinePass = report.timeline.length === 3 && report.timeline.every(row => {
      const expected = expectedTimeline[row.key];
      return expected && row.events.length >= expected.frames.length &&
        expected.frames.every((frame, i) => row.events[i].frame === frame &&
          Math.abs(row.events[i].at_ms - expected.times[i]) <= 100);
    });
    report.errors = errors;
    report.pass = report.state.clipCount === 15 && report.state.groupCount === 5 &&
      report.groups === 5 && report.cards === 15 && report.observationCards === 15 &&
      report.state.assetCount === 105 && report.staticImagesLoaded && report.maskImagesLoaded &&
      report.renderedCanvases === 30 && report.sliderMax.every((max, i) =>
        max === manifest[i].playback_order.length - 1) &&
      report.stepFrames.every(x => x === 1) && report.resetFrames.every(x => x === 0) &&
      report.pausedBefore.every((x, i) => x === report.pausedAfter[i]) &&
      report.speedAdvanced && report.glint03RepeatedPose && report.maskContextsVisible && report.timelinePass &&
      Object.values(report.desktop).every(x => x.squares && x.document <= x.viewport) &&
      Object.values(report.mobile).every(x => x.squares && x.document <= x.viewport) &&
      !errors.length;
    fs.writeFileSync(path.join(reportDir, 'browser-validation.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({ pass: report.pass, groups: report.groups, cards: report.cards,
      desktop: report.desktop, mobile: report.mobile, errors }));
    if (!report.pass) process.exitCode = 1;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
