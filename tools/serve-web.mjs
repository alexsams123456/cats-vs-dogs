import http from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

// Для телефона в той же Wi-Fi сети: node tools/serve-web.mjs --lan.
const root = resolve(fileURLToPath(new URL('../build/web-site/dist/', import.meta.url)));
const host = process.argv.includes('--lan') ? '0.0.0.0' : '127.0.0.1';
const port = Number(process.env.CVD_WEB_PORT || 8060);
const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.png': 'image/png', '.wasm': 'application/wasm', '.pck': 'application/octet-stream' };
if (!existsSync(resolve(root, 'index.html'))) throw new Error('Сначала выполните tools/build-web.ps1.');
const server = http.createServer((request, response) => {
	let pathname;
	try { pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname); }
	catch { response.writeHead(400).end(); return; }
	const filename = resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
	if (!filename.startsWith(root + sep) || !existsSync(filename) || !statSync(filename).isFile() || pathname.startsWith('/.')) {
		response.writeHead(404).end('Not found'); return;
	}
	if (request.method !== 'GET' && request.method !== 'HEAD') { response.writeHead(405).end(); return; }
	const extension = extname(filename);
	const headers = {
		'Content-Type': types[extension] || 'application/octet-stream',
		'Cache-Control': 'no-cache',
		'Content-Security-Policy': "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; worker-src 'self' blob:; img-src 'self' data: blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'"
	};
	if (extension === '.wasm' || extension === '.pck') headers['Content-Encoding'] = 'gzip';
	response.writeHead(200, headers);
	if (request.method === 'HEAD') response.end();
	else createReadStream(filename).pipe(response);
});
server.listen(port, host, () => console.log(`Игра: http://${host === '0.0.0.0' ? '<IP компьютера>' : host}:${port}/`));
