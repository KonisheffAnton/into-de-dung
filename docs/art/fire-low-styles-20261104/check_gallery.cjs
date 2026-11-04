'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dir = __dirname;
const reportDir = path.resolve(dir, '../../../test_reports/fire-low-styles-20261104');
const portable = path.join(reportDir, 'portable');
const variants = JSON.parse(fs.readFileSync(path.join(dir, 'prompts.json'), 'utf8')).variants;
const expected = variants.map(v => ({ number: String(v.number), name: v.name }));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
async function scale(page, value) {
  await page.locator('#zoom-range').evaluate((el, v) => { el.value = String(v); el.dispatchEvent(new Event('input')); }, value);
}
async function layout(page, selector = '#gallery .stage') {
  return page.evaluate(selector => {
    const stages = [...document.querySelectorAll(selector)];
    return { count: stages.length, overflow: document.documentElement.scrollWidth > innerWidth,
      bad: stages.flatMap(stage => {
        const a = stage.getBoundingClientRect();
        const imgs = [...stage.querySelectorAll('img')];
        if (imgs.length !== 1) return ['image count'];
        const im = imgs[0], b = im.getBoundingClientRect(), css = getComputedStyle(im);
        return !im.complete || !im.naturalWidth || Math.abs(a.width-b.width)>1 || Math.abs(a.height-b.height)>1
          || css.objectFit !== 'contain' || css.transform !== 'none' ? [{a:[a.width,a.height],b:[b.width,b.height]}] : [];
      }) };
  }, selector);
}
async function run() {
  fs.mkdirSync(portable, { recursive: true });
  fs.copyFileSync(path.join(dir, 'gallery.html'), path.join(portable, 'gallery.html'));
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const errors = [], report = { checks: {} };
  try {
    const page = await browser.newPage({ viewport: { width: 1600, height: 1100 }, deviceScaleFactor: 1 });
    page.on('pageerror', e => errors.push(String(e)));
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
    await page.goto(pathToFileURL(path.join(portable, 'gallery.html')).href);
    await page.waitForFunction(() => [...document.querySelectorAll('#gallery img')].length === 20
      && [...document.querySelectorAll('#gallery img')].every(im => im.complete && im.naturalWidth));
    report.cards = await page.locator('#gallery .card').evaluateAll(cards => cards.map(c => ({ number: c.querySelector('.number').textContent, name: c.querySelector('.name').textContent })));
    report.checks.names = same(report.cards, expected);
    report.assets = await page.evaluate(() => ASSETS.map(a => ({id:a.id,width:a.width,height:a.height,embedded:a.data.startsWith('data:image/png;base64,')})));
    report.decoded = await page.locator('#gallery img').evaluateAll(images => images.map(im => ({width:im.naturalWidth,height:im.naturalHeight})));
    report.checks.assets = report.assets.length === 20 && report.assets.every((a,i) => a.id === variants[i].id && a.embedded && a.width === report.decoded[i].width && a.height === report.decoded[i].height);
    report.desktop = {};
    for (const s of [0.7,1,1.6]) { await scale(page,s); report.desktop[s] = await layout(page); }
    report.checks.desktop = Object.values(report.desktop).every(r => r.count===20 && !r.overflow && !r.bad.length);
    await page.locator('.open-card').first().click();
    await page.locator('#viewer-stage img').evaluate(im => im.decode());
    report.modal = await layout(page, '#viewer-stage');
    const before = await page.locator('#viewer-stage').boundingBox();
    await scale(page,0.7);
    const after = await page.locator('#viewer-stage').boundingBox();
    report.checks.modalFit = !report.modal.bad.length && Math.abs(before.width-after.width)<1 && Math.abs(before.height-after.height)<1;
    await page.locator('#next').click();
    const next = await page.locator('#viewer-title').textContent();
    await page.locator('#previous').click();
    const previous = await page.locator('#viewer-title').textContent();
    await page.locator('#previous').click();
    const wrap = await page.locator('#viewer-title').textContent();
    await page.locator('#viewer-stage img').evaluate(im => im.decode());
    await page.screenshot({ path: path.join(reportDir, 'modal.png') });
    await page.keyboard.press('Escape');
    report.checks.navigation = next.startsWith('fire-low-22 ·') && previous.startsWith('fire-low-21 ·') && wrap.startsWith('fire-low-40 ·') && !(await page.locator('#viewer').evaluate(d => d.open));
    await scale(page,1);
    await page.screenshot({ path: path.join(reportDir, 'comparison.png'), fullPage: true });
    await page.setViewportSize({width:390,height:900});
    report.mobile = {};
    for (const s of [0.7,1,1.6]) { await scale(page,s); report.mobile[s] = await layout(page); }
    report.checks.mobile = Object.values(report.mobile).every(r => r.count===20 && !r.overflow && !r.bad.length);
    await scale(page,1);
    await page.screenshot({ path: path.join(reportDir, 'mobile.png') });
    report.checks.portable = same(fs.readdirSync(portable), ['gallery.html']);
    report.errors = errors;
    report.pass = Object.values(report.checks).every(Boolean) && !errors.length;
    fs.writeFileSync(path.join(reportDir,'browser-validation.json'), JSON.stringify(report,null,2)+'\n','utf8');
    console.log(JSON.stringify({pass:report.pass,checks:report.checks,errors}));
    if (!report.pass) process.exitCode=1;
  } finally { await browser.close(); }
}
run().catch(e => { console.error(e); process.exitCode=1; });
