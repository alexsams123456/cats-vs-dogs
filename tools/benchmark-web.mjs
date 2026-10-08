import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Playwright поставляется через NODE_PATH; каждый запуск использует чистый профиль.
const { firefox } = createRequire(import.meta.url)('playwright');
const root = fileURLToPath(new URL('../', import.meta.url));
const args = process.argv.slice(2);
const option = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const label = option('--label', 'baseline');
assert.match(label, /^[a-zA-Z0-9_-]+$/);
const url = option('--url', process.env.CVD_WEB_TEST_URL || 'http://127.0.0.1:8060/');
const durationMs = Number(option('--seconds', '8')) * 1000;
assert.ok(Number.isFinite(durationMs) && durationMs >= 1000 && durationMs <= 60000);
const prefix = resolve(root, '.artifacts', `web-performance-${label}`);
mkdirSync(resolve(root, '.artifacts'), { recursive: true });
function buildHashes() {
	const hashes = {};
	for (const file of ['index.html', 'game-loader.js', 'index.js', 'index.pck', 'index.wasm']) {
		try { hashes[file] = createHash('sha256').update(readFileSync(resolve(root, 'build/web-site/dist', file))).digest('hex'); }
		catch { hashes[file] = null; }
	}
	return hashes;
}
const hashes = buildHashes();
const startedAt = new Date().toISOString();
const browser = await firefox.launch({ headless: args.includes('--headless') });
try {
	const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
	const page = await context.newPage();
	const logs = [];
	page.on('console', message => logs.push(`${message.type()}: ${message.text()}`));
	page.on('pageerror', error => logs.push(`pageerror: ${error.message}`));
	await page.addInitScript(() => {
		const originalFrame = window.requestAnimationFrame;
		let draws = 0;
		window.cvdBenchmark = { collecting: false, renderedFrames: 0, samples: [], contextLost: 0 };
		window.addEventListener('webglcontextlost', () => { window.cvdBenchmark.contextLost++; }, true);
		for (const prototype of [window.WebGLRenderingContext?.prototype, window.WebGL2RenderingContext?.prototype]) {
			if (!prototype) continue;
			for (const method of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced']) {
				const original = prototype[method];
				if (!original) continue;
				prototype[method] = function (...parameters) {
					draws++;
					return original.apply(this, parameters);
				};
			}
		}
		window.requestAnimationFrame = callback => originalFrame.call(window, timestamp => {
			const drawStart = draws;
			const callbackStart = performance.now();
			try { callback(timestamp); }
			finally {
				if (draws > drawStart) {
					window.cvdBenchmark.renderedFrames++;
					if (window.cvdBenchmark.collecting) {
						window.cvdBenchmark.samples.push({ timestamp, milliseconds: performance.now() - callbackStart, draws: draws - drawStart });
					}
				}
			}
		});
	});
	await page.goto(url);
	await page.getByRole('button', { name: 'Играть', exact: true }).click();
	await page.locator('#status').waitFor({ state: 'hidden', timeout: 120000 });
	await page.bringToFront();
	await page.locator('#canvas').focus();
	await page.waitForTimeout(4500);
	await page.waitForFunction(() => window.cvdBenchmark.renderedFrames >= 10, null, { timeout: 30000 });
	const report = {
		startedAt, url, browser: `Firefox ${browser.version()}`, headed: !args.includes('--headless'),
		viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2, durationMs, localBuildSha256: hashes,
		measurement: 'Время синхронного rAF callback с WebGL draw calls, без ожидания завершения GPU; FPS по интервалам таких callbacks. Изолированный тестовый профиль.',
	};
	async function sample(name, sampleDurationMs = durationMs) {
		await page.evaluate(() => { window.cvdBenchmark.samples = []; window.cvdBenchmark.collecting = true; });
		await page.waitForTimeout(sampleDurationMs);
		report[name] = await page.evaluate(() => {
			window.cvdBenchmark.collecting = false;
			const frames = window.cvdBenchmark.samples;
			const values = frames.map(frame => frame.milliseconds).sort((a, b) => a - b);
			const intervals = frames.slice(1).map((frame, index) => frame.timestamp - frames[index].timestamp).sort((a, b) => a - b);
			const drawValues = frames.map(frame => frame.draws).sort((a, b) => a - b);
			const mean = list => list.reduce((sum, value) => sum + value, 0) / list.length;
			const percentile = (list, fraction) => list[Math.min(list.length - 1, Math.floor(list.length * fraction))];
			const canvas = document.querySelector('canvas');
			const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
			const debug = gl?.getExtension('WEBGL_debug_renderer_info');
			return {
				frames: frames.length, meanMs: mean(values), medianMs: percentile(values, 0.5), p95Ms: percentile(values, 0.95), p99Ms: percentile(values, 0.99),
				meanDraws: mean(drawValues), p95Draws: percentile(drawValues, 0.95),
				meanIntervalMs: mean(intervals), p95IntervalMs: percentile(intervals, 0.95), p99IntervalMs: percentile(intervals, 0.99),
				effectiveFps: 1000 / mean(intervals), intervalsOver33ms: intervals.filter(value => value > 33.34).length, intervalsOver50ms: intervals.filter(value => value > 50).length,
				canvas: [canvas.width, canvas.height], contextAttributes: gl?.getContextAttributes(),
				renderer: debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : gl?.getParameter(gl.RENDERER),
				documentVisibility: document.visibilityState,
			};
		});
		report[name].durationMs = sampleDurationMs;
		await page.screenshot({ path: `${prefix}-${name}.png` });
		if (report[name].frames === 0) {
			writeFileSync(`${prefix}.json`, JSON.stringify({ ...report, incomplete: true }, null, 2));
			writeFileSync(`${prefix}.log`, logs.join('\n'));
		}
		assert.ok(report[name].frames > 0, `${name}: не получены WebGL кадры`);
		console.log(`${name}: ${report[name].effectiveFps.toFixed(1)} FPS, callback ${report[name].meanMs.toFixed(2)} ms, ${report[name].meanDraws.toFixed(0)} draw calls`);
	}
	await sample('menu');
	await page.mouse.click(1020, 280);
	await page.waitForTimeout(2600);
	await sample('level');
	await page.mouse.move(235, 460);
	await page.mouse.down();
	await page.mouse.move(120, 492, { steps: 15 });
	await page.mouse.up();
	await sample('flight', 2000);
	report.flight.scenario = 'Первые 2 s после одинакового выстрела мышью на первом уровне: полёт, столкновения и эффекты. Возможный переход к результату входит в окно, отдельную победу этот замер не подтверждает.';
	await page.screenshot({ path: `${prefix}-shot.png` });
	await page.mouse.click(1180, 55);
	await page.waitForTimeout(400);
	await page.screenshot({ path: `${prefix}-pause.png` });
	report.scriptErrors = logs.filter(message => /^pageerror:|^error: (SCRIPT ERROR:|ERROR:)/i.test(message));
	report.contextLostEvents = await page.evaluate(() => window.cvdBenchmark.contextLost);
	report.localBuildSha256AtEnd = buildHashes();
	report.localBuildUnchanged = JSON.stringify(report.localBuildSha256) === JSON.stringify(report.localBuildSha256AtEnd);
	writeFileSync(`${prefix}.json`, JSON.stringify(report, null, 2));
	writeFileSync(`${prefix}.log`, logs.join('\n'));
	console.log(`Отчёт: ${prefix}.json`);
	assert.deepEqual(report.scriptErrors, [], 'Ошибки игры в браузере');
	assert.equal(report.contextLostEvents, 0, 'Потерян WebGL контекст');
	if (['127.0.0.1', 'localhost'].includes(new URL(url).hostname)) {
		assert.ok(report.localBuildUnchanged, 'Локальная сборка изменилась во время замера; результаты могут смешивать две версии');
	}
} finally {
	await browser.close();
}
