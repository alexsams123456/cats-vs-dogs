import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Изолированные профили: настоящий прогресс игрока не меняется.
const { firefox, webkit } = createRequire(import.meta.url)('playwright');
const label = process.env.CVD_WEB_TEST_LABEL || '';
assert.match(label, /^[a-zA-Z0-9_-]*$/);
const artifact = name => new URL(`../.artifacts/web-fps-${label ? label + '-' : ''}${name}`, import.meta.url);
mkdirSync(new URL('../.artifacts/', import.meta.url), { recursive: true });
const report = [];
for (const [name, browserType, touch] of [['firefox', firefox, false], ['webkit-touch', webkit, true]]) {
	if (process.argv.includes('--firefox-only') && touch) continue;
	const browser = await browserType.launch({ headless: true });
	try {
		const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, hasTouch: touch });
		const page = await context.newPage();
		const errors = [];
		page.on('pageerror', error => errors.push(error.message));
		page.on('console', message => {
			if (/^(SCRIPT ERROR:|ERROR:)/.test(message.text())) errors.push(message.text());
		});
		await page.goto(process.env.CVD_WEB_TEST_URL || 'http://127.0.0.1:8060/');
		assert.equal(await page.locator('#fps').isVisible(), false, 'FPS скрыт до запуска');
		await page.evaluate(() => {
			window.fpsSamples = [];
			new MutationObserver(() => window.fpsSamples.push(document.getElementById('fps').textContent))
				.observe(document.getElementById('fps'), { childList: true });
		});
		const start = page.getByRole('button', { name: 'Играть', exact: true });
		if (touch) await start.tap(); else await start.click();
		await page.locator('#status').waitFor({ state: 'hidden', timeout: 120000 });
		await page.waitForFunction(() => /^FPS: [1-9]\d*$/.test(document.getElementById('fps').textContent));
		await page.waitForTimeout(2500);
		const sizes = [];
		for (const width of [1280, 1600, 960]) {
			await page.setViewportSize({ width, height: 720 });
			await page.waitForTimeout(400);
			const layout = await page.locator('#fps').evaluate(element => {
				const box = element.getBoundingClientRect();
				return { text: element.textContent, left: box.left, right: box.right, top: box.top, bottom: box.bottom,
					pointerEvents: getComputedStyle(element).pointerEvents,
					underneath: document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)?.id };
			});
			assert.ok(layout.left >= 0 && layout.right <= width && layout.top >= 0 && layout.bottom <= 720);
			assert.equal(layout.pointerEvents, 'none');
			assert.equal(layout.underneath, 'canvas', 'Счётчик пропускает ввод в игру');
			sizes.push({ width, ...layout });
			await page.screenshot({ path: fileURLToPath(artifact(`${name}-${width}.png`)) });
		}
		await page.setViewportSize({ width: 1280, height: 720 });
		await page.waitForTimeout(400);
		if (touch) await page.touchscreen.tap(1020, 280); else await page.mouse.click(1020, 280);
		await page.waitForTimeout(2600);
		if (touch) await page.touchscreen.tap(1180, 55); else await page.mouse.click(1180, 55);
		await page.waitForTimeout(400);
		await page.evaluate(() => { window.fpsSamples = []; });
		await page.waitForTimeout(3200);
		const pausedSamples = await page.evaluate(() => window.fpsSamples);
		// Настоящее окно паузы нужно подтвердить просмотром снимка canvas.
		assert.ok(pausedSamples.length >= 2, 'FPS обновляется после нажатия кнопки паузы');
		assert.ok(pausedSamples.every(text => /^FPS: [1-9]\d*$/.test(text)));
		await page.screenshot({ path: fileURLToPath(artifact(`${name}-pause.png`)) });
		assert.deepEqual(errors, []);
		report.push({ browser: name, sizes, pausedSamples, errors });
		console.log(`${name}: FPS виден в трёх размерах, пропускает ввод и обновляется после кнопки паузы; снимки требуют просмотра.`);
	} finally {
		await browser.close();
	}
}
writeFileSync(artifact('report.json'), JSON.stringify(report, null, 2));
