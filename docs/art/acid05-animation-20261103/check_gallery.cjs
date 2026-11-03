const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const dir = __dirname;
const reportDir = path.resolve(dir, '../../../test_reports/acid05-animation-20261103');
const portableDir = path.join(reportDir, 'portable');
const portableHtml = path.join(portableDir, 'gallery.html');
const requests = JSON.parse(fs.readFileSync(path.join(dir, 'requests.json'), 'utf8'));

function requireCondition(condition, message) {
	if (!condition) throw new Error(message);
}

(async () => {
	requireCondition(requests.length === 10, `Expected ten requests, got ${requests.length}`);
	fs.mkdirSync(portableDir, { recursive: true });
	fs.copyFileSync(path.join(dir, 'gallery.html'), portableHtml);
	const portableFiles = fs.readdirSync(portableDir).sort();
	requireCondition(portableFiles.length === 1 && portableFiles[0] === 'gallery.html', `Portable folder has neighbor files: ${portableFiles.join(', ')}`);

	const browser = await chromium.launch({ channel: 'msedge', headless: true });
	try {
		const page = await browser.newPage({ viewport: { width: 1800, height: 1200 }, deviceScaleFactor: 1 });
		const errors = [];
		page.on('pageerror', error => errors.push(String(error)));
		page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
		await page.goto(pathToFileURL(portableHtml).href);
		await page.waitForFunction(() => window.__galleryState && window.__galleryState().loaded
			&& document.querySelector('#input')?.naturalWidth === 256);

		const expectedKeys = requests.map(row => row.key).sort();
		const report = await page.evaluate(() => {
			const cards = [...document.querySelectorAll('#gallery article')];
			const assets = Object.entries(ASSETS);
			return {
				title: document.querySelector('h1')?.textContent,
				documentTitle: document.title,
				state: window.__galleryState(),
				cards: cards.length,
				cardNames: cards.map(card => card.querySelector('h2')?.textContent),
				canvases: document.querySelectorAll('#gallery canvas').length,
				sliders: document.querySelectorAll('#gallery input[type="range"]').length,
				columns: getComputedStyle(document.querySelector('#gallery')).gridTemplateColumns.split(' ').length,
				inputLoaded: document.querySelector('#input')?.naturalWidth === 256,
				assetKeys: assets.map(([key]) => key),
				technicalCaptionLeak: cards.some(card => /south-east|top-down|stationary blue-grey|Fixed isometric/i.test(card.textContent)),
			};
		});
		const decodedAssets = await page.evaluate(async () => Promise.all(Object.entries(ASSETS).map(([key, source]) => new Promise(resolve => {
			const image = new Image();
			image.onload = () => resolve({ key, ok: image.naturalWidth > 0 && image.naturalHeight > 0, size: [image.naturalWidth, image.naturalHeight] });
			image.onerror = () => resolve({ key, ok: false, size: [0, 0] });
			image.src = source;
		}))));
		report.assetCount = report.assetKeys.length;
		report.decodedAssets = decodedAssets;
		report.assetsAllDecode = decodedAssets.length === 22 && decodedAssets.every(asset => asset.ok);
		report.requestKeysMatch = report.assetKeys.includes('model/source-original.png')
			&& report.assetKeys.includes('model/input-256.png')
			&& expectedKeys.every(key => report.assetKeys.includes(`pixellab/${key}/sheet.png`) && report.assetKeys.includes(`pixellab/${key}/preview.gif`));
		await page.locator('#background').selectOption('checker');
		report.checker = await page.locator('#gallery article .stage').first().evaluate(stage => ({
			image: getComputedStyle(stage).backgroundImage,
			size: getComputedStyle(stage).backgroundSize,
			position: getComputedStyle(stage).backgroundPosition,
		}));
		report.checkerVisible = report.checker.image.includes('linear-gradient')
			&& report.checker.size.includes('20px 20px') && report.checker.position.includes('10px 10px');
		await page.locator('#background').selectOption('dark');

		const setFrame = async (index, value) => page.locator(`[data-slider="${index}"]`).evaluate((slider, frame) => {
			slider.value = String(frame);
			slider.dispatchEvent(new Event('input', { bubbles: true }));
		}, value);
		const getFrames = () => page.evaluate(() => window.__galleryState().frames);
		const measureCanvases = () => page.evaluate(() => {
			const boxes = [...document.querySelectorAll('#gallery canvas')].map(canvas => {
				const rect = canvas.getBoundingClientRect();
				return { width: rect.width, height: rect.height };
			});
			return {
				width: innerWidth,
				documentWidth: document.documentElement.scrollWidth,
				square: boxes.length === 10 && boxes.every(box => Math.abs(box.width - box.height) <= 1),
				boxes,
			};
		});
		await setFrame(0, 7);
		report.sliderFrame = (await getFrames())[0];
		report.sliderCounter = await page.locator('[data-counter="0"]').textContent();
		report.sliderRanges = await page.locator('#gallery input[type="range"]').evaluateAll(sliders => sliders.map(slider => ({ min: slider.min, max: slider.max })));
		await page.locator('#restart').click();
		await setFrame(0, 7);
		await page.locator('#play').click();
		await page.waitForTimeout(130);
		await page.locator('#play').click();
		const pausedBefore = (await getFrames())[0];
		await page.waitForTimeout(350);
		report.pauseFrames = { before: pausedBefore, after: (await getFrames())[0] };
		report.pausedButtonText = await page.locator('#play').textContent();
		await setFrame(0, 7);
		await page.locator('#step').click();
		report.stepFrame = (await getFrames())[0];
		report.stepCounter = await page.locator('[data-counter="0"]').textContent();

		await setFrame(0, 7);
		await page.screenshot({ path: path.join(reportDir, 'gallery-overview.png'), fullPage: true });
		report.overviewFrame = (await getFrames())[0];

		const measureSpeed = async speed => {
			await setFrame(0, 0);
			await page.locator('#speed').selectOption(String(speed));
			await page.locator('#play').click();
			await page.waitForTimeout(700);
			const frame = (await getFrames())[0];
			await page.locator('#play').click();
			return frame;
		};
		report.slowSpeedFrame = await measureSpeed(0.5);
		report.fastSpeedFrame = await measureSpeed(2);
		await page.locator('#restart').click();
		report.restartFrames = await getFrames();

		report.desktopScaleModes = {};
		for (const mode of ['', 'small', 'large']) {
			await page.locator('#size').selectOption(mode);
			report.desktopScaleModes[mode || 'default'] = await measureCanvases();
		}
		report.desktopScaleModesPass = Object.values(report.desktopScaleModes).every(layout => layout.square && layout.documentWidth <= layout.width);
		await page.locator('#size').selectOption('');

		await page.setViewportSize({ width: 390, height: 900 });
		report.mobileScaleModes = {};
		for (const mode of ['', 'small', 'large']) {
			await page.locator('#size').selectOption(mode);
			report.mobileScaleModes[mode || 'default'] = await measureCanvases();
		}
		report.mobileScaleModesPass = Object.values(report.mobileScaleModes).every(layout => layout.square && layout.documentWidth <= layout.width);
		await page.locator('#size').selectOption('');
		report.mobile = report.mobileScaleModes.default;
		report.mobileOverflow = report.mobile.documentWidth > report.mobile.width;
		await page.screenshot({ path: path.join(reportDir, 'gallery-mobile.png'), fullPage: true });
		report.largeMobile = report.mobileScaleModes.large;
		report.largeMobileOverflow = report.largeMobile.documentWidth > report.largeMobile.width;
		report.portableFiles = portableFiles;
		report.errors = errors;
		report.pass = report.state.clipCount === 10 && report.state.assetCount === 22
			&& report.cards === 10 && report.canvases === 10 && report.sliders === 10
			&& report.columns === 3 && report.inputLoaded && report.assetsAllDecode && report.requestKeysMatch
			&& !report.technicalCaptionLeak && report.checkerVisible
			&& report.sliderRanges.length === 10 && report.sliderRanges.every(range => range.min === '0' && range.max === '32')
			&& report.sliderFrame === 7 && report.sliderCounter === 'Кадр 8 / 33'
			&& report.pausedButtonText === 'Играть' && report.pauseFrames.before === report.pauseFrames.after
			&& report.stepFrame === 8 && report.stepCounter === 'Кадр 9 / 33'
			&& report.overviewFrame === 7 && report.fastSpeedFrame > report.slowSpeedFrame
			&& report.restartFrames.length === 10 && report.restartFrames.every(frame => frame === 0)
			&& report.desktopScaleModesPass && report.mobileScaleModesPass
			&& !report.mobileOverflow && !report.largeMobileOverflow && !errors.length;
		fs.writeFileSync(path.join(reportDir, 'browser-validation.json'), JSON.stringify(report, null, 2) + '\n');
		console.log(JSON.stringify(report));
		if (!report.pass) process.exitCode = 1;
	} finally {
		await browser.close();
	}
})().catch(error => { console.error(error); process.exitCode = 1; });
