const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const dir = __dirname;
(async () => {
	const browser = await chromium.launch({ channel: 'msedge', headless: true });
	try {
		const page = await browser.newPage({ viewport: { width: 1800, height: 1200 }, deviceScaleFactor: 1 });
		const errors = [];
		page.on('pageerror', error => errors.push(String(error)));
		page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
		await page.goto(pathToFileURL(path.join(dir, 'gallery.html')).href);
		await page.waitForFunction(() => [...document.querySelectorAll('#comparison img')].every(image => image.complete && image.naturalWidth > 0));
		const report = await page.evaluate(() => ({
			title: document.querySelector('h1')?.textContent,
			documentTitle: document.title,
			variantIds: [...document.querySelectorAll('#variant-grid .card')].map(card => card.dataset.id),
			variantFiles: [...document.querySelectorAll('#variant-grid .card')].map(card => card.dataset.file),
			variantNames: [...document.querySelectorAll('#variant-grid .card span')].map(label => label.textContent),
			referenceFiles: [...document.querySelectorAll('#reference-grid .card')].map(card => card.dataset.file),
			referenceLabels: [...document.querySelectorAll('#reference-grid .card span')].map(label => label.textContent),
			imageCount: document.querySelectorAll('#comparison img').length,
			embedded: [...document.querySelectorAll('#comparison img')].every(image => image.src.startsWith('data:image/png;base64,')),
			decoded: [...document.querySelectorAll('#comparison img')].every(image => image.complete && image.naturalWidth > 0),
			variantColumns: getComputedStyle(document.querySelector('#variant-grid')).gridTemplateColumns.split(' ').length,
			referenceColumns: getComputedStyle(document.querySelector('#reference-grid')).gridTemplateColumns.split(' ').length,
			previewWidths: [...document.querySelectorAll('#comparison .card img')].map(image => image.getBoundingClientRect().width),
		}));
		await page.locator('#comparison').screenshot({ path: path.join(dir, 'comparison.png') });
		await page.locator('#reference-grid .card').first().click();
		report.referenceZoomOpen = await page.locator('#viewer').evaluate(dialog => dialog.open);
		report.referenceSelected = await page.locator('#viewer-title').textContent();
		await page.waitForFunction(() => document.getElementById('large').complete && document.getElementById('large').naturalWidth > 0);
		report.zoomDecoded = await page.locator('#large').evaluate(image => [image.naturalWidth, image.naturalHeight]);
		await page.keyboard.press('Escape');
		report.escapeClosed = await page.locator('#viewer').evaluate(dialog => !dialog.open);
		await page.locator('#variant-grid .card').nth(2).click();
		report.variantZoomOpen = await page.locator('#viewer').evaluate(dialog => dialog.open);
		await page.locator('#close').click();
		report.buttonClosed = await page.locator('#viewer').evaluate(dialog => !dialog.open);
		await page.setViewportSize({ width: 390, height: 900 });
		report.mobile = await page.evaluate(() => ({
			width: innerWidth,
			documentWidth: document.documentElement.scrollWidth,
			variantColumns: getComputedStyle(document.querySelector('#variant-grid')).gridTemplateColumns.split(' ').length,
			referenceColumns: getComputedStyle(document.querySelector('#reference-grid')).gridTemplateColumns.split(' ').length,
		}));
		await page.locator('#reference-grid .card').nth(2).click();
		report.mobileZoom = await page.locator('#viewer').evaluate(dialog => dialog.open);
		await page.keyboard.press('Escape');
		report.mobileOverflow = report.mobile.documentWidth > report.mobile.width;
		report.errors = errors;
		report.pass = report.title === 'Лучница 14 · пять переработок'
			&& report.variantIds.join(',') === '14-01,14-02,14-03,14-04,14-05'
			&& report.variantFiles.join(',') === 'archer-14-01.png,archer-14-02.png,archer-14-03.png,archer-14-04.png,archer-14-05.png'
			&& report.variantNames.every((name, index) => name.startsWith(`${report.variantIds[index]} · `))
			&& report.referenceFiles.join(',') === '../archer-variants-20261103/archer-14.png,../warrior-variants-20261029/warrior-11.png,../warrior-variants-20261029/warrior-02.png'
			&& report.referenceLabels.join(',') === 'Лучница 14 · оригинал,Воин 11,Защитник 02'
			&& report.imageCount === 8 && report.embedded && report.decoded
			&& report.variantColumns === 5 && report.referenceColumns === 3
			&& Math.max(...report.previewWidths) - Math.min(...report.previewWidths) < 1
			&& report.referenceZoomOpen && report.variantZoomOpen && report.zoomDecoded[0] > 0
			&& report.escapeClosed && report.buttonClosed && report.mobileZoom
			&& report.mobile.variantColumns === 2 && report.mobile.referenceColumns === 2
			&& !report.mobileOverflow && !errors.length;
		fs.writeFileSync(path.join(dir, 'gallery-validation.json'), JSON.stringify(report, null, 2) + '\n');
		console.log(JSON.stringify(report));
		if (!report.pass) process.exitCode = 1;
	} finally {
		await browser.close();
	}
})().catch(error => { console.error(error); process.exitCode = 1; });
