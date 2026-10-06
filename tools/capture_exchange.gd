extends SceneTree
## Графическая проверка обмена мышью и синтетическими касаниями на ПК.

var _checks: int = 0
var _failures: int = 0
var _created: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var clipboard_test := DisplayServer.clipboard_has() and not DisplayServer.clipboard_has_image()
	var clipboard := DisplayServer.clipboard_get() if clipboard_test else ""
	var editor := preload("res://scenes/editor/level_editor.tscn").instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	current_scene = editor
	await _settle()
	var shared := CampaignCatalog.LEVELS[8].duplicate(true) as LevelDefinition
	shared.title = "Двор с цепной реакцией"
	shared.normalize_materials()
	editor._replace_draft(shared, "")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		DisplayServer.window_set_size(dimensions)
		await _settle()
		var touch := dimensions.x == 960
		var button: Button
		for node in editor.find_children("*", "Button", true, false):
			if (node as Button).text == "Обмен":
				button = node as Button
		_check(button != null and editor.get_viewport_rect().encloses(button.get_global_rect()), "Кнопка обмена доступна")
		_click(button, touch)
		await _settle()
		var dialog := editor.exchange_dialog
		_check(dialog.visible and not dialog.code_edit.editable, "Мышь или касание открывает обмен")
		_check(dialog.size.y <= root.get_visible_rect().size.y, "Окно первого экспорта помещается в экран")
		await _shot("share", dimensions.x)
		if clipboard_test:
			_click(dialog.copy_button, touch)
			await _settle()
			_check(LevelExchange.decode(DisplayServer.clipboard_get()) != null, "Копирование настоящего кода")
		_click(dialog.import_button, touch)
		await _settle()
		if clipboard_test:
			_click(dialog.paste_button, touch)
		else:
			dialog.code_edit.text = LevelExchange.encode(shared)
			dialog._validate_code()
		await _settle()
		_check(not dialog._sharing and dialog._incoming != null and not dialog.add_button.disabled and dialog.summary.text.contains(shared.title), "Вставка из буфера даёт предпросмотр")
		for control: Control in [dialog.code_edit, dialog.paste_button, dialog.open_button, dialog.add_button, dialog.get_ok_button()]:
			_check(Rect2(Vector2.ZERO, Vector2(dialog.size)).encloses(control.get_global_rect()), "Все действия внутри окна обмена")
		await _shot("import", dimensions.x)
		var source := editor.draft
		_click(dialog.add_button, touch)
		await _settle()
		_check(editor.draft != source and editor.draft.weight_positions == shared.weight_positions and not editor.current_path.is_empty(), "Добавление сохраняет грузовой двор новой копией")
		_created.append(editor.current_path)
		# Проверяем встроенный резервный выбор файла, не управление системным окном.
		editor._show_exchange()
		await _settle()
		dialog.file_dialog.use_native_dialog = false
		_click(dialog.save_button, touch)
		await _settle()
		_check(dialog.file_dialog.visible and dialog.file_dialog.current_file == "level.cvdlevel", "Экспорт открывает выбор файла с расширением")
		dialog.file_dialog.hide()
		dialog.hide()
		await _settle()
	# Проверка раскладки переводов: окно не должно расширяться за экран.
	DisplayServer.window_set_size(Vector2i(960, 720))
	await _settle()
	for locale: String in ["en", "de", "ar", "ja"]:
		TranslationServer.set_locale(locale)
		editor._show_exchange()
		await _settle()
		var dialog := editor.exchange_dialog
		dialog._show_import()
		dialog.code_edit.text = LevelExchange.encode(shared)
		dialog._validate_code()
		await _settle()
		_check(dialog.size.x <= root.get_visible_rect().size.x and dialog.size.y <= root.get_visible_rect().size.y, "Переведённое окно помещается в узком экране")
		await _shot(locale, 960)
		dialog.hide()
	if clipboard_test:
		DisplayServer.clipboard_set(clipboard)
	TranslationServer.set_locale("ru")
	editor.queue_free()
	await _settle()
	for path in _created:
		DirAccess.remove_absolute(path)
	print("Exchange graphic checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _click(button: Button, touch: bool) -> void:
	var point := button.get_global_rect().get_center()
	var window := button.get_window()
	if window != root:
		point += Vector2(window.position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = point
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(event, true)


func _shot(stage: String, width: int) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png("res://.artifacts/exchange-%d-%s.png" % [width, stage]) == OK, "Снимок окна обмена")


func _settle() -> void:
	for frame in 8:
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
