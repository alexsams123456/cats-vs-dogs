
		// Keep Firefox DevTools available: Godot cancels canvas keyboard events.
		function preserveDevToolsKey(event) {
			if (event.key === 'F12' || event.code === 'F12') event.stopImmediatePropagation();
		}
		window.addEventListener('keydown', preserveDevToolsKey, { capture: true });
		window.addEventListener('keyup', preserveDevToolsKey, { capture: true });
		const touchDevice = navigator.maxTouchPoints > 0 || 'ontouchstart' in window;
		function updateOrientation() {
			document.getElementById('rotate').hidden = !touchDevice || innerWidth >= innerHeight;
		}
		window.addEventListener('resize', updateOrientation);
		if (window.visualViewport) window.visualViewport.addEventListener('resize', updateOrientation);
		updateOrientation();
		const config = __GODOT_CONFIG__;
		const engine = new Engine(config);
		const canvas = document.getElementById('canvas');
		// Desktop: request the GPU best suited to rendering. The browser decides.
		const getCanvasContext = canvas.getContext.bind(canvas);
		canvas.getContext = (type, attributes) => getCanvasContext(type,
			(type === 'webgl2' || type === 'webgl') && !touchDevice
				? { ...attributes, powerPreference: 'high-performance' }
				: attributes);
		const status = document.getElementById('status');
		const start = document.getElementById('start');
		const progress = document.getElementById('progress');
		const notice = document.getElementById('notice');
		const retry = document.getElementById('retry');
		retry.addEventListener('click', () => location.reload());
		function fail(error) {
			console.error(error);
			document.getElementById('fps').hidden = true;
			status.hidden = false;
			progress.hidden = true;
			start.hidden = true;
			notice.textContent = 'Не удалось запустить игру. Проверьте соединение и попробуйте обновить браузер. ' + (error.message || error);
			retry.hidden = false;
		}
		start.addEventListener('click', async () => {
			start.hidden = true;
			progress.hidden = false;
			notice.textContent = 'Загружаем двор… Первый запуск может занять немного времени.';
			try {
				const missing = Engine.getMissingFeatures({ threads: false });
				if (missing.length) throw new Error('Браузеру требуются: ' + missing.join(', '));
				await engine.startGame({
					canvas,
					onProgress(current, total) {
						if (total > 0) { progress.max = total; progress.value = current; }
						else progress.removeAttribute('value');
					},
					onExit(code) { fail(new Error('Игра завершилась (код ' + code + ').')); }
				});
				status.hidden = true;
				canvas.focus();
			} catch (error) { fail(error); }
		}, { once: true });
