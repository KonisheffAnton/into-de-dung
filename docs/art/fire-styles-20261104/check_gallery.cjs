'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE
  || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const PACKAGE_DIR = __dirname;
const REPORT_DIR = path.resolve(PACKAGE_DIR, '../../../test_reports/fire-styles-20261104');
const PORTABLE_DIR = path.join(REPORT_DIR, 'portable');
const PORTABLE_HTML = path.join(PORTABLE_DIR, 'gallery.html');
const PROMPTS = JSON.parse(fs.readFileSync(path.join(PACKAGE_DIR, 'prompts.json'), 'utf8'));
const EXPECTED_VARIANTS = PROMPTS.variants.map((variant) => ({ id: variant.id, name: variant.name }));

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

async function inspectStages(page) {
  return page.evaluate(() => {
    const stages = [...document.querySelectorAll('#gallery .stage')];
    const bad = [];
    for (const stage of stages) {
      const stageRect = stage.getBoundingClientRect();
      for (const image of stage.querySelectorAll('img')) {
        const imageRect = image.getBoundingClientRect();
        const fit = getComputedStyle(image).objectFit;
        if (Math.abs(stageRect.width - imageRect.width) > 1
          || Math.abs(stageRect.height - imageRect.height) > 1
          || fit !== 'contain' || !image.complete || image.naturalWidth === 0) {
          bad.push({ stage: [stageRect.width, stageRect.height], image: [imageRect.width, imageRect.height], fit, loaded: image.complete });
        }
      }
    }
    return {
      count: stages.length,
      documentWidth: document.documentElement.scrollWidth,
      viewportWidth: innerWidth,
      imageTransform: getComputedStyle(document.querySelector('#gallery .layers')).transform,
      bad,
    };
  });
}

async function setScale(page, value) {
  await page.locator('#zoom-range').evaluate((input, next) => {
    input.value = String(next);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);
}

async function run() {
  requireCondition(EXPECTED_VARIANTS.length === 20, `prompts.json has ${EXPECTED_VARIANTS.length} variants`);
  const galleryPath = path.join(PACKAGE_DIR, 'gallery.html');
  requireCondition(fs.existsSync(galleryPath) && fs.statSync(galleryPath).isFile(),
    'gallery.html is missing; run build_gallery.cjs after all PNGs arrive');
  fs.mkdirSync(PORTABLE_DIR, { recursive: true });
  fs.copyFileSync(galleryPath, PORTABLE_HTML);
  const portableFiles = fs.readdirSync(PORTABLE_DIR).sort();
  requireCondition(portableFiles.length === 1 && portableFiles[0] === 'gallery.html',
    `portable folder must contain only gallery.html, found: ${portableFiles.join(', ')}`);

  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const report = { portableFiles, expectedVariants: EXPECTED_VARIANTS, failures: [] };
  const errors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1600, height: 1100 }, deviceScaleFactor: 1 });
    page.on('pageerror', (error) => errors.push(String(error)));
    page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(pathToFileURL(PORTABLE_HTML).href, { waitUntil: 'load' });
    await page.waitForFunction(() => typeof ASSETS !== 'undefined' && ASSETS.variants?.length === 20);
    await page.waitForFunction(() => [...document.querySelectorAll('#gallery img')]
      .every((image) => image.complete && image.naturalWidth > 0));
    report.embeddedAssets = await page.evaluate(async () => {
      const all = [{ id: 'tile-reference', ...ASSETS.reference }, ...ASSETS.variants];
      return Promise.all(all.map((asset) => new Promise((resolve) => {
        const image = new Image();
        image.onload = () => resolve({
          id: asset.id,
          ok: image.naturalWidth > 0 && image.naturalHeight > 0,
          width: image.naturalWidth,
          height: image.naturalHeight,
          source: asset.data.slice(0, 22),
        });
        image.onerror = () => resolve({ id: asset.id, ok: false, width: 0, height: 0, source: asset.data.slice(0, 22) });
        image.src = asset.data;
      })));
    });
    report.initial = await page.evaluate(() => ({
      cards: [...document.querySelectorAll('#gallery article')].map((card) => ({
        id: card.querySelector('.number')?.textContent,
        name: card.querySelector('.name')?.textContent,
      })),
      imageCount: document.querySelectorAll('#gallery img').length,
      title: document.title,
      note: document.querySelector('.note')?.textContent,
    }));
    report.namesAndIdsMatch = JSON.stringify(report.initial.cards) === JSON.stringify(EXPECTED_VARIANTS);
    report.assetDimensionsMatch = report.embeddedAssets.length === 21
      && report.embeddedAssets.every((image) => image.ok && image.source === 'data:image/png;base64,')
      && report.embeddedAssets[0].width === 1024 && report.embeddedAssets[0].height === 1024
      && report.embeddedAssets.slice(1).every((image) => image.width === 1254 && image.height === 1254);
    report.embeddedImageCount = report.initial.imageCount;

    report.modeChecks = {};
    for (const mode of ['tile', 'fire']) {
      await page.locator(mode === 'tile' ? '#mode-tile' : '#mode-fire').click();
      report.modeChecks[mode] = await page.locator('#gallery .stage').first().evaluate((stage) => ({
        mode: stage.dataset.mode,
        tileDisplay: getComputedStyle(stage.querySelector('.tile-layer')).display,
        pressedTile: document.getElementById('mode-tile').getAttribute('aria-pressed'),
        pressedFire: document.getElementById('mode-fire').getAttribute('aria-pressed'),
      }));
    }
    report.modeChecksPass = report.modeChecks.tile.mode === 'tile'
      && report.modeChecks.tile.tileDisplay !== 'none'
      && report.modeChecks.tile.pressedTile === 'true' && report.modeChecks.tile.pressedFire === 'false'
      && report.modeChecks.fire.mode === 'fire'
      && report.modeChecks.fire.tileDisplay === 'none'
      && report.modeChecks.fire.pressedTile === 'false' && report.modeChecks.fire.pressedFire === 'true';

    await page.locator('#mode-tile').click();
    report.scaleChecks = {};
    for (const scale of ['0.7', '1', '1.6']) {
      await setScale(page, scale);
      const layout = await inspectStages(page);
      report.scaleChecks[scale] = { ...layout, label: await page.locator('#zoom-value').textContent() };
    }
    report.scalesFitWholeCards = Object.values(report.scaleChecks).every((layout) => layout.bad.length === 0
      && layout.imageTransform === 'none' && layout.documentWidth <= layout.viewportWidth);

    await setScale(page, '1.6');
    await page.locator('#gallery .open-card').first().click();
    report.modal = await page.evaluate(() => {
      const dialog = document.getElementById('viewer');
      const stage = document.getElementById('viewer-stage');
      const image = stage.querySelector('.fire-layer');
      const stageRect = stage.getBoundingClientRect();
      const imageRect = image.getBoundingClientRect();
      return {
        open: dialog.open,
        title: document.getElementById('viewer-title').textContent,
        position: document.getElementById('viewer-position').textContent,
        imageCount: stage.querySelectorAll('img').length,
        fit: getComputedStyle(image).objectFit,
        stage: [stageRect.width, stageRect.height],
        image: [imageRect.width, imageRect.height],
      };
    });
    await setScale(page, '0.7');
    report.modalAfterZoom = await page.locator('#viewer-stage').evaluate((stage) => {
      const rect = stage.getBoundingClientRect();
      const image = stage.querySelector('.fire-layer');
      const imageRect = image.getBoundingClientRect();
      return { stage: [rect.width, rect.height], image: [imageRect.width, imageRect.height], fit: getComputedStyle(image).objectFit };
    });
    await page.locator('#next').click();
    report.modalNext = await page.locator('#viewer-title').textContent();
    report.modalNextPosition = await page.locator('#viewer-position').textContent();
    await page.locator('#previous').click();
    report.modalPrevious = await page.locator('#viewer-title').textContent();
    report.dialogImageCount = await page.locator('#viewer-stage img').count();
    report.totalImageElements = report.embeddedImageCount + report.dialogImageCount;
    await page.keyboard.press('Escape');
    report.escapeCloses = !(await page.locator('#viewer').evaluate((dialog) => dialog.open));
    report.modalWorks = report.modal.open && report.modal.title === 'fire-01 · ' + EXPECTED_VARIANTS[0].name
      && report.modal.position === '1 / 20' && report.modal.imageCount === 2 && report.modal.fit === 'contain'
      && report.modal.stage.every((value, index) => Math.abs(value - report.modal.image[index]) <= 1)
      && report.modalAfterZoom.stage.every((value, index) => Math.abs(value - report.modal.stage[index]) <= 1)
      && report.modalAfterZoom.image.every((value, index) => Math.abs(value - report.modalAfterZoom.stage[index]) <= 1)
      && report.modalNext === 'fire-02 · ' + EXPECTED_VARIANTS[1].name && report.modalNextPosition === '2 / 20'
      && report.modalPrevious === report.modal.title && report.dialogImageCount === 2 && report.escapeCloses;

    report.embeddedAssetCount = report.embeddedAssets.length;
    await setScale(page, '1');
    await page.locator('#mode-tile').click();
    await page.screenshot({ path: path.join(REPORT_DIR, 'fire-gallery-desktop.png'), fullPage: true });
    await page.locator('#mode-fire').click();
    await page.screenshot({ path: path.join(REPORT_DIR, 'fire-gallery-fire-only.png'), fullPage: true });
    await page.locator('#mode-tile').click();
    await page.setViewportSize({ width: 390, height: 900 });
    report.mobile = {};
    for (const scale of ['0.7', '1', '1.6']) {
      await setScale(page, scale);
      report.mobile[scale] = await inspectStages(page);
    }
    report.mobileFits = Object.values(report.mobile).every((layout) => layout.bad.length === 0
      && layout.imageTransform === 'none' && layout.documentWidth <= layout.viewportWidth);
    await setScale(page, '1');
    await page.screenshot({ path: path.join(REPORT_DIR, 'fire-gallery-mobile.png'), fullPage: true });
    await page.screenshot({ path: path.join(REPORT_DIR, 'fire-gallery-mobile-top.png') });
    report.portableFiles = fs.readdirSync(PORTABLE_DIR).sort();
    report.errors = errors;
    report.pass = report.namesAndIdsMatch && report.assetDimensionsMatch && report.embeddedImageCount === 40
      && report.totalImageElements === 42
      && report.modeChecksPass && report.scalesFitWholeCards && report.modalWorks && report.mobileFits
      && report.portableFiles.length === 1 && report.portableFiles[0] === 'gallery.html' && errors.length === 0;
    fs.writeFileSync(path.join(REPORT_DIR, 'browser-validation.json'), `${JSON.stringify(report, null, 2)}\n`);
    console.log(JSON.stringify(report, null, 2));
    if (!report.pass) process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

fs.mkdirSync(REPORT_DIR, { recursive: true });
run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
