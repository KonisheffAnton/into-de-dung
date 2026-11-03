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
		await page.waitForFunction(() => [...document.querySelectorAll('#archer-grid .card img')].every(image => image.complete && image.naturalWidth > 0));
		const report = await page.evaluate(() => ({
			title: document.querySelector('h1')?.textContent,
			documentTitle: document.title,
			cards: document.querySelectorAll('#archer-grid .card').length,
			ids: [...document.querySelectorAll('#archer-grid .card')].map(card => card.dataset.id),
			names: [...document.querySelectorAll('#archer-grid .card span')].map(label => label.textContent),
			embedded: [...document.querySelectorAll('#archer-grid img')].every(image => image.src.startsWith('data:image/png;base64,')),
			decoded: [...document.querySelectorAll('#archer-grid img')].every(image => image.complete && image.naturalWidth > 0),
			columns: getComputedStyle(document.querySelector('#archer-grid')).gridTemplateColumns,
			columnCount: getComputedStyle(document.querySelector('#archer-grid')).gridTemplateColumns.split(' ').length,
		}));
		await page.locator('#archer-grid').screenshot({ path: path.join(dir, 'archer-contact.png') });
		await page.locator('#archer-grid .card').nth(2).click();
		report.zoomOpen = await page.locator('#viewer').evaluate(dialog => dialog.open);
		report.selected = await page.locator('#viewer-title').textContent();
		await page.waitForFunction(() => document.getElementById('large').complete && document.getElementById('large').naturalWidth > 0);
		report.zoomDecoded = await page.locator('#large').evaluate(image => [image.naturalWidth, image.naturalHeight]);
		await page.keyboard.press('Escape');
		report.escapeClosed = await page.locator('#viewer').evaluate(dialog => !dialog.open);
		await page.locator('#archer-grid .card').nth(9).click();
		await page.locator('#close').click();
		report.buttonClosed = await page.locator('#viewer').evaluate(dialog => !dialog.open);
		await page.setViewportSize({ width: 390, height: 900 });
		report.mobile = await page.evaluate(() => ({
			width: innerWidth,
			documentWidth: document.documentElement.scrollWidth,
			columns: getComputedStyle(document.querySelector('#archer-grid')).gridTemplateColumns,
			columnCount: getComputedStyle(document.querySelector('#archer-grid')).gridTemplateColumns.split(' ').length,
		}));
		await page.locator('#archer-grid .card').first().click();
		report.mobileZoom = await page.locator('#viewer').evaluate(dialog => dialog.open);
		await page.keyboard.press('Escape');
		report.mobileOverflow = report.mobile.documentWidth > report.mobile.width;
		report.errors = errors;
		report.pass = report.title === 'Лучница · варианты 11–20'
			&& report.cards === 10 && report.ids.join(',') === '11,12,13,14,15,16,17,18,19,20'
			&& report.names.every((name, index) => name.startsWith(`${index + 11} · `))
			&& report.columnCount === 5 && report.embedded && report.decoded && report.zoomOpen && report.zoomDecoded[0] > 0
			&& report.escapeClosed && report.buttonClosed && report.mobileZoom
			&& report.mobile.columnCount === 2 && !report.mobileOverflow && !errors.length;
		fs.writeFileSync(path.join(dir, 'gallery-validation.json'), JSON.stringify(report, null, 2) + '\n');
		console.log(JSON.stringify(report));
		if (!report.pass) process.exitCode = 1;
	} finally {
		await browser.close();
	}
})().catch(error => { console.error(error); process.exitCode = 1; });
