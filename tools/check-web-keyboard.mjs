import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';

// Playwright can be supplied by the workspace runtime through NODE_PATH.
const { firefox } = createRequire(import.meta.url)('playwright');
const browser = await firefox.launch({ headless: true });
try {
	const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
	const page = await context.newPage();
	const errors = [];
	page.on('pageerror', error => errors.push(error.message));
	page.on('console', message => {
		if (/^(SCRIPT ERROR:|ERROR:)/.test(message.text())) errors.push(message.text());
	});
	await page.addInitScript(() => {
		window.keyboardEvents = [];
		for (const type of ['keydown', 'keyup']) {
			window.addEventListener(type, event => {
				queueMicrotask(() => window.keyboardEvents.push({
					type, code: event.code, canceled: event.defaultPrevented
				}));
			}, { capture: true });
		}
	});
	await page.goto(process.env.CVD_WEB_TEST_URL || 'http://127.0.0.1:8060/');
	await page.getByRole('button', { name: 'Играть', exact: true }).click();
	await page.locator('#status').waitFor({ state: 'hidden', timeout: 120000 });
	await page.waitForTimeout(4500);
	await page.locator('#canvas').focus();
	const results = await page.evaluate(() => {
		const canvas = document.getElementById('canvas');
		const results = [];
		for (const type of ['keydown', 'keyup']) {
			for (const key of ['F12', ' ', 'e']) {
				const event = new KeyboardEvent(type, {
					key, code: key === ' ' ? 'Space' : key === 'e' ? 'KeyE' : 'F12',
					bubbles: true, cancelable: true
				});
				results.push({ type, key, allowed: canvas.dispatchEvent(event) });
			}
		}
		return results;
	});
	for (const event of results) {
		assert.equal(event.allowed, event.key === 'F12', `${event.type}: ${event.key}`);
	}
	await page.evaluate(() => { window.keyboardEvents = []; });
	await page.keyboard.press('F12');
	const actualEvents = await page.evaluate(() => window.keyboardEvents);
	assert.equal(actualEvents.length, 2);
	assert.ok(actualEvents.every(event => event.code === 'F12' && !event.canceled));
	assert.deepEqual(errors, []);
	const report = { results, actualEvents, errors };
	writeFileSync(new URL('../.artifacts/web-keyboard.json', import.meta.url), JSON.stringify(report, null, 2));
	console.log('Firefox: F12 не отменяется (keydown/keyup), игровые Space/E обрабатываются, ошибок скриптов нет.');
} finally {
	await browser.close();
}
