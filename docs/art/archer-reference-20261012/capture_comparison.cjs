// HTML задаёт геометрию сравнения; исходные RGBA не редактируются.
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const browser = await chromium.launch({headless: true, channel: 'chrome'});
  try {
    const page = await browser.newPage({viewport: {width: 940, height: 800}, deviceScaleFactor: 1});
    await page.goto(pathToFileURL(path.join(__dirname, 'comparison.html')).href);
    await page.evaluate(() => Promise.all(Array.from(document.images).map(image => image.decode())));
    await page.screenshot({path: path.join(__dirname, 'comparison.png'), fullPage: true});
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
