extends SceneTree
## Миниатюры, выбор карточки и авторская победа реальным вводом на ПК.

var _checks: int = 0
var _failures: int = 0
var _paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := preload("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _settle()
	app.show_editor()
	await _settle()
	var editor := app.editor
	var level := CampaignCatalog.LEVELS[6].duplicate(true) as LevelDefinition
	level.title = "Авторский обвал"
	editor._replace_draft(level, "")
	editor.save_level()
	_paths.append(editor.current_path)
	editor._show_exchange()
	await _settle()
	_click(editor.exchange_dialog.test_button)
	await _settle()
	_check(app.game != null and app.game.editor_preview, "Испытание из окна обмена")
	for tick in 90:
		await physics_frame
	var transform := app.game.slingshot.get_global_transform_with_canvas()
	_pointer(transform.origin, true)
	var motion := InputEventMouseMotion.new()
	motion.position = transform * Vector2(-70, 78)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_pointer(motion.position, false)
	_check(app.game.shots_left == 3, "Мышь запускает одного кота")
	var ability := false
	for tick in 1800:
		await physics_frame
		if not ability and app.game._flight_time >= 0.65 / Slingshot.FLIGHT_SPEED_SCALE:
			ability = true
			var key := InputEventKey.new()
			key.physical_keycode = KEY_E
			key.pressed = true
			root.push_input(key, true)
			key = key.duplicate() as InputEventKey
			key.pressed = false
			root.push_input(key, true)
		if app.game.state == GameRound.RoundState.WON:
			break
	_check(app.game.state == GameRound.RoundState.WON and editor.draft.is_author_completed(), "Настоящая победа мышью и E даёт отметку")
	app.game.return_to_menu()
	await _settle()
	for index in [3, 5]:
		var other := CampaignCatalog.LEVELS[index].duplicate(true) as LevelDefinition
		other.title = "Мой горный двор" if index == 3 else "Мой снежный двор"
		var saved := LevelLibrary.save_level(other)
		_paths.append(saved.path)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		DisplayServer.window_set_size(dimensions)
		await _settle()
		var touch := dimensions.x == 960
		editor._show_library()
		await _settle()
		_check(editor._library_dialog.size.x <= root.get_visible_rect().size.x and editor._library_dialog.size.y <= root.get_visible_rect().size.y, "Библиотека помещается в экран")
		var cards: Array[Button] = []
		for child in editor._library_list.get_children():
			if child is Button:
				cards.append(child)
		_check(cards.size() >= 6 and cards[0].get_children().size() > 0, "Пользовательские карточки стоят перед шаблонами")
		var scroll := editor._library_list.get_parent() as ScrollContainer
		for card in cards:
			scroll.ensure_control_visible(card)
			await _settle()
			_check(scroll.get_global_rect().encloses(card.get_global_rect()), "Карточка целиком доступна при прокрутке")
		scroll.scroll_vertical = 0
		await _settle()
		await _shot("library-%d" % dimensions.x)
		_click(cards[0], touch)
		await _settle()
		_check(not editor._library_dialog.visible and editor.draft.title == "Авторский обвал" and editor.draft.is_author_completed(), "Мышь или касание карточки открывает пройденный уровень")
		editor._show_exchange()
		await _settle()
		_check(editor.exchange_dialog.completion_label.text.contains(tr("Пройден автором · бросков: %d") % 1), "Отметка показана перед отправкой")
		_check(LevelExchange.decode(editor.exchange_dialog.code_edit.text).is_author_completed(), "Код передаёт отметку вместе с уровнем")
		await _shot("cleared-%d" % dimensions.x)
		editor.exchange_dialog.hide()
	for locale: String in ["de", "ar", "ja"]:
		TranslationServer.set_locale(locale)
		editor._show_library()
		await _settle()
		await _shot("library-" + locale)
		editor._library_dialog.hide()
	TranslationServer.set_locale("ru")
	var music: WeakRef = weakref((app.get_node("BackgroundMusic") as AudioStreamPlayer).get_stream_playback())
	app.queue_free()
	await _settle()
	var deadline := Time.get_ticks_msec() + 1000
	while music.get_ref() != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	for path in _paths:
		DirAccess.remove_absolute(path)
	print("Library graphic checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _click(button: Button, touch: bool = false) -> void:
	var point := button.get_global_rect().get_center()
	if button.get_window() != root:
		point += Vector2(button.get_window().position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	_pointer(point, true, touch)
	_pointer(point, false, touch)


func _pointer(point: Vector2, pressed: bool, touch: bool = false) -> void:
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
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		root.push_input(event, true)


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.artifacts/presentation-%s.png" % stage) == OK, "Снимок миниатюр и отметки")


func _settle() -> void:
	for frame in 8:
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
