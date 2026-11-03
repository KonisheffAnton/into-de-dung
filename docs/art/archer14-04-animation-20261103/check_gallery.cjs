const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const dir = __dirname;
const requests = JSON.parse(fs.readFileSync(path.join(dir, 'requests.json'), 'utf8'));
(async () => {
	const browser = await chromium.launch({ channel: 'msedge', headless: true });
	try {
		const page = await browser.newPage({ viewport: { width: 1800, height: 1200 }, deviceScaleFactor: 1 });
		const errors = [];
		page.on('pageerror', error => errors.push(String(error)));
		page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
		await page.goto(pathToFileURL(path.join(dir, 'gallery.html')).href);
		await page.waitForFunction(() => window.__galleryState && window.__galleryState().loaded);
		const report = await page.evaluate(() => ({
			title: document.querySelector('h1')?.textContent,
			documentTitle: document.title,
			state: window.__galleryState(),
			cards: document.querySelectorAll('#gallery article').length,
			idleCards: [...document.querySelectorAll('#gallery h2')].map(heading => heading.textContent),
			canvases: document.querySelectorAll('#gallery canvas').length,
			columns: getComputedStyle(document.querySelector('#gallery .grid')).gridTemplateColumns.split(' ').length,
		}));
		report.assetDecodes = await page.evaluate(() => window.__decodeGalleryAssets());
		await page.screenshot({ path: path.join(dir, 'gallery-overview.png'), fullPage: true });
		const setFrame = async (index, value) => page.locator(`[data-slider="${index}"]`).evaluate((slider, frame) => {
			slider.value = String(frame);
			slider.dispatchEvent(new Event('input', { bubbles: true }));
		}, value);
		const idleIndex = report.state.clips.findIndex(clip => clip.key === 'idle-1');
		const deathIndex = report.state.clips.findIndex(clip => clip.key === 'death-1');
		const abilityIndex = report.state.clips.findIndex(clip => clip.key === 'ability-1');
		await setFrame(idleIndex, 7);
		report.scrubFrame = (await page.evaluate(() => window.__galleryState().frameIndexes))[idleIndex];
		await setFrame(idleIndex, 32);
		await page.locator('#play').click();
		await page.waitForTimeout(180);
		report.idleLoopFrame = (await page.evaluate(() => window.__galleryState().frameIndexes))[idleIndex];
		report.idleLooped = report.idleLoopFrame < 32;
		await setFrame(deathIndex, 32);
		await page.locator('#play').click();
		await page.waitForTimeout(report.state.clips[deathIndex].timing.at(-1) + 200);
		report.deathHeldAtEnd = (await page.evaluate(() => window.__galleryState().frameIndexes))[deathIndex] === 32;
		await setFrame(abilityIndex, 32);
		await page.locator('#play').click();
		await page.waitForTimeout(report.state.clips[abilityIndex].timing.at(-1) + 200);
		report.abilityHeldAtEnd = (await page.evaluate(() => window.__galleryState().frameIndexes))[abilityIndex] === 32;
		await page.locator('#restart').click();
		report.restartFrame = (await page.evaluate(() => window.__galleryState().frameIndexes))[0];
		await page.setViewportSize({ width: 390, height: 900 });
		report.mobile = await page.evaluate(() => ({ width: innerWidth, documentWidth: document.documentElement.scrollWidth }));
		report.mobileOverflow = report.mobile.documentWidth > report.mobile.width;
		report.errors = errors;
		const expectedAssets = 2 + 2 * requests.length;
		const requestedKeys = requests.map(row => row.key).sort().join(',');
		const browserKeys = report.state.clips.map(clip => clip.key).sort().join(',');
		report.pass = report.title === 'Лучница 14-04 · 15 PixelLab-проб'
			&& report.state.clipCount === requests.length && report.state.assetCount === expectedAssets
			&& report.assetDecodes.count === expectedAssets && report.assetDecodes.all
			&& browserKeys === requestedKeys && report.cards === requests.length && report.canvases === requests.length && report.columns === 3
			&& report.scrubFrame === 7 && report.idleLooped && report.deathHeldAtEnd && report.abilityHeldAtEnd
			&& report.restartFrame === 0 && !report.mobileOverflow && !errors.length;
		fs.writeFileSync(path.join(dir, 'browser-validation.json'), JSON.stringify(report, null, 2) + '\n');
		console.log(JSON.stringify(report));
		if (!report.pass) process.exitCode = 1;
	} finally {
		await browser.close();
	}
})().catch(error => { console.error(error); process.exitCode = 1; });
