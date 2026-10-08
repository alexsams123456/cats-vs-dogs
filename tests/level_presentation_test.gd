extends SceneTree
## Миниатюры и отметка прохождения точной авторской версии.

var _checks: int = 0
var _failures: int = 0
var _paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := CampaignCatalog.LEVELS[6].duplicate(true) as LevelDefinition
	level.normalize_materials()
	_check(not level.is_author_completed(), "Старые уровни не имеют автоматической отметки")
	level.record_author_completion(1, &"classic", &"scout")
	_check(level.is_author_completed(), "Победа отмечает точную версию")
	for key: String in ["title", "biome", "shots", "par_shots", "tutorial", "dog_positions", "block_positions", "block_sizes", "block_materials", "weight_positions", "cat_sequence", "dog_kinds", "dog_house_materials", "dog_house_types"]:
		var edited := level.duplicate(true) as LevelDefinition
		match key:
			"title": edited.title += "!"
			"biome": edited.biome = "glacier"
			"shots": edited.shots -= 1
			"par_shots": edited.par_shots = 0
			"tutorial": edited.tutorial = &"aim"
			"dog_positions": edited.dog_positions[0].x += 0.0001
			"block_positions": edited.block_positions[0].y += 0.0001
			"block_sizes": edited.block_sizes[0].x += 1
			"block_materials": edited.block_materials[0] = "stone"
			"weight_positions": edited.weight_positions[0].x += 1
			"cat_sequence": edited.cat_sequence.reverse()
			"dog_kinds": edited.dog_kinds[0] = "armored"
			"dog_house_materials": edited.dog_house_materials[0] = "glass"
			"dog_house_types": edited.dog_house_types[0] = "barrel"
		_check(not edited.is_author_completed(), "Правка сбрасывает отметку: " + key)
	level.dog_positions[0] += Vector2(0.12347, 0.65432)
	level.record_author_completion(1, &"classic", &"scout")
	_check(LevelExchange.decode(LevelExchange.encode(level)).is_author_completed(), "Обмен сохраняет отметку с дробными координатами")
	var result := LevelLibrary.save_level(level)
	_paths.append(result.path)
	_check(result.error == OK and LevelLibrary.load_level(result.path).is_author_completed(), "Ресурс сохраняет отметку с дробными координатами")
	var recovery := "user://presentation_%d.json" % Time.get_ticks_usec()
	_paths.append(recovery)
	var store := EditorDraftStore.new(recovery)
	_check(store.save_draft(level, result.path, true) == OK and store.load_draft().level.is_author_completed(), "Восстановление сохраняет отметку")
	for metadata: Variant in [true, "passed", {"fingerprint": true}, {"fingerprint": level.gameplay_fingerprint(), "shots": true, "cat": "classic", "dog": "scout"}, {"fingerprint": level.gameplay_fingerprint(), "shots": 21, "cat": "classic", "dog": "scout"}]:
		var data := LevelData.to_dictionary(level)
		data.author_completion = metadata
		var loaded := LevelData.from_dictionary(data)
		_check(loaded != null and not loaded.is_author_completed(), "Неверная отметка не мешает открыть сам уровень")
	var thumbnail := LevelThumbnail.new()
	thumbnail.draft = level
	root.add_child(thumbnail)
	await _settle()
	var original := level.gameplay_fingerprint()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = thumbnail.world_to_local(Vector2(800, 550))
	thumbnail._gui_input(touch)
	_check(level.gameplay_fingerprint() == original and thumbnail.selected_kind == -1, "Касание миниатюры не редактирует двор")
	_check(not thumbnail.grid_enabled and not thumbnail.show_guides and not thumbnail.is_processing_input(), "Миниатюра не запускает редакторский ввод")
	_check(thumbnail._backdrop.process_mode == Node.PROCESS_MODE_DISABLED and thumbnail.find_children("*", "PhysicsBody2D", true, false).is_empty(), "Миниатюра не создаёт физику и анимационный цикл")
	thumbnail.queue_free()
	await _settle()
	await _editor(level)
	await _preview()
	for path in _paths:
		DirAccess.remove_absolute(path)
	print("Level presentation checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _editor(level: LevelDefinition) -> void:
	var editor := preload("res://scenes/editor/level_editor.tscn").instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	await _settle()
	editor._replace_draft(level.duplicate(true) as LevelDefinition, "")
	editor._on_title_changed("Изменённый двор")
	editor._finish_edit()
	_check(not editor.draft.is_author_completed() and editor.draft.author_completion.is_empty(), "Редактор очищает устаревшую отметку")
	editor.undo()
	_check(editor.draft.is_author_completed(), "Отмена возвращает пройденную версию и её отметку")
	editor.redo()
	_check(not editor.draft.is_author_completed(), "Повтор правки убирает отметку")
	editor.record_preview_win(level, 1, &"classic", &"scout")
	_check(not editor.draft.is_author_completed(), "Победа другой версии не отмечает текущий двор")
	editor._show_library()
	await _settle()
	_check(editor._library_list.find_children("*", "LevelThumbnail", true, false).size() >= 4, "Миниатюра есть у шаблонов и пользовательского уровня")
	editor._library_dialog.hide()
	editor._show_exchange()
	await _settle()
	_check(editor.exchange_dialog.completion_label.text.contains(tr("Нет отметки прохождения")), "До испытания статус показан в обмене")
	editor.exchange_dialog.hide()
	editor._replace_draft(level.duplicate(true) as LevelDefinition, "")
	editor._show_exchange()
	await _settle()
	_check(editor.exchange_dialog.completion_label.text.contains(tr("Пройден автором · бросков: %d") % 1), "Перед отправкой видны отметка и число бросков")
	editor.queue_free()
	await _settle()


func _preview() -> void:
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
	editor._replace_draft(level, "")
	editor.save_level()
	var path := editor.current_path
	_paths.append(path)
	editor._show_exchange()
	await _settle()
	editor.exchange_dialog.test_button.pressed.emit()
	await _settle()
	_check(app.game != null and app.game.editor_preview and not editor.exchange_dialog.visible, "Кнопка испытания открывает настоящую пробу")
	app.game.round_completed.emit(false, 4, 0)
	_check(not editor.draft.is_author_completed(), "Поражение не даёт отметку")
	for tick in 90:
		await physics_frame
	_check(app.game.slingshot.launch_from_pull(Vector2(-70, 78)), "Настоящий бросок автора")
	var activated := false
	for tick in 1800:
		await physics_frame
		if not activated and app.game._flight_time >= 0.65 / Slingshot.FLIGHT_SPEED_SCALE:
			activated = true
			app.game.use_ability()
		if app.game.state == GameRound.RoundState.WON:
			break
	_check(app.game.state == GameRound.RoundState.WON and editor.draft.is_author_completed(), "Победа в физической пробе отмечает авторский двор")
	_check(LevelLibrary.load_level(path).is_author_completed() and not editor.is_dirty(), "Отметка сохранённого двора записывается без изменения раскладки")
	app.game.return_to_menu()
	await _settle()
	_check(editor.visible and editor._status.text.contains(tr("Пройден автором")), "После пробы редактор показывает результат")
	_check(app.profile.results.is_empty(), "Проба не меняет рекорды кампании")
	var music: WeakRef = weakref((app.get_node("BackgroundMusic") as AudioStreamPlayer).get_stream_playback())
	app.queue_free()
	await _settle()
	var deadline := Time.get_ticks_msec() + 1000
	while music.get_ref() != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout


func _settle() -> void:
	for frame in 5:
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
