extends SceneTree
## Грузы: настоящие броски, цепное разрушение, ввод редактора и хранение.

const MAIN := preload("res://scenes/main.tscn")
const APP := preload("res://scenes/app.tscn")
const YARD := preload("res://levels/weight_yard.tres")
const WEIGHT := preload("res://scenes/actors/hanging_weight.tscn")
const CAT := preload("res://scenes/actors/cat_projectile.tscn")

var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _paths: Array[String] = []
var _playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_capture = "--capture-special-objects" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	_test_data()
	_test_storage()
	await _test_rope()
	await _test_blast()
	await _test_editor()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		await _test_round(dimensions)
	for path in _paths:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(path) == OK, "Удалён собственный файл проверки")
	var deadline := Time.get_ticks_msec() + 1000
	while not _music_released() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(_music_released(), "Удалённые сцены освободили музыкальные потоки")
	print("Special object checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_data() -> void:
	var legacy := LevelDefinition.new()
	legacy.dog_positions = PackedVector2Array([Vector2(800, 595)])
	_check(legacy.is_valid() and legacy.weight_positions.is_empty(), "Старый уровень не получает грузов")
	var level := YARD.duplicate(true) as LevelDefinition
	_check(level.is_valid() and level.weight_positions.size() == 2, "Шаблон содержит два груза")
	level.weight_positions[0] = Vector2(INF, 0)
	_check(not level.is_valid(), "Бесконечные координаты отклоняются")
	level.weight_positions.resize(LevelDefinition.MAX_OBJECTS + 1)
	level.weight_positions.fill(Vector2(800, 330))
	_check(not level.is_valid(), "Ограничение количества грузов действует на загрузку")
	level.weight_positions.resize(LevelDefinition.MAX_OBJECTS)
	_check(level.is_valid(), "Предельное количество грузов допустимо")


func _test_storage() -> void:
	var saved := LevelLibrary.save_level(YARD)
	_check(saved.error == OK, "Грузы сохраняются в ресурс")
	if saved.error == OK:
		_paths.append(saved.path)
		var restored := LevelLibrary.load_level(saved.path)
		_check(restored != null and restored.weight_positions == YARD.weight_positions, "Загрузка возвращает позиции грузов")
		if restored != null:
			restored.weight_positions[0] = Vector2(600, 400)
			_check(LevelLibrary.load_level(saved.path).weight_positions == YARD.weight_positions, "Изменение копии не меняет сохранённые данные")
	var path := "user://weight_draft_test_%d.json" % Time.get_ticks_usec()
	_paths.append(path)
	var store := EditorDraftStore.new(path)
	_check(store.save_draft(YARD, "", true) == OK, "Черновик с грузами записывается")
	var restored_draft := store.load_draft()
	_check(not restored_draft.is_empty() and restored_draft.level.weight_positions == YARD.weight_positions, "Восстановление черновика сохраняет грузы")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document.level.erase("weight_positions")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	var old_draft := store.load_draft()
	_check(not old_draft.is_empty() and old_draft.level.weight_positions.is_empty(), "Старый JSON-черновик открывается без грузов")
	document.level.weight_positions = [["bad", 330]]
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_check(store.load_draft().is_empty(), "Некорректный JSON груза отклоняется")


func _test_rope() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var weight := WEIGHT.instantiate() as HangingWeight
	weight.position = Vector2(800, 330)
	world.add_child(weight)
	var releases: Array[int] = [0]
	weight.released.connect(func() -> void: releases[0] += 1)
	await _ticks(65)
	_check(weight.suspended and weight.position == Vector2(800, 330), "Груз не оседает до разрыва")
	weight.rope.receive_hit(179)
	_check(weight.suspended, "Слабое касание не разрывает верёвку")
	paused = true
	weight.rope.receive_hit(1000)
	await process_frame
	_check(weight.suspended, "На паузе крепление не принимает удар")
	paused = false
	var cat := CAT.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.find_cat(&"classic")
	cat.position = Vector2(700, 225)
	world.add_child(cat)
	cat.launch(Vector2(1600, 0))
	await _ticks(12)
	_check(not weight.suspended and not weight.freeze and releases[0] == 1, "Быстрый кот физически пересекает верёвку и освобождает груз")
	weight.rope.receive_hit(1000)
	_check(releases[0] == 1, "Повторный удар не вызывает второго освобождения")
	var before := weight.position
	paused = true
	await _ticks(12)
	_check(weight.position == before, "Пауза останавливает падение")
	paused = false
	await _ticks(12)
	_check(weight.position.y > before.y + 20, "Снятие паузы продолжает падение")
	weight.receive_hit(10000)
	_check(not weight.is_destroyed, "Груз сохраняется после сильного удара")
	world.queue_free()
	await _layout()


func _test_blast() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var weight := WEIGHT.instantiate() as HangingWeight
	weight.position = Vector2(800, 330)
	world.add_child(weight)
	var cat := CAT.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.find_cat(&"bomb")
	cat.position = Vector2(700, 330)
	world.add_child(cat)
	cat.launch(Vector2(10, 0))
	_check(cat.activate_ability(), "Искра активирует настоящий взрыв около груза")
	await _ticks(3)
	_check(not weight.suspended and not weight.freeze, "Взрыв разрывает крепление")
	world.queue_free()
	await _layout()


func _test_editor() -> void:
	var app := APP.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _layout()
	_click(app.campaign.editor_button, true)
	await _layout()
	var editor := app.editor
	_check(editor != null, "Редактор открывается касанием из меню")
	if editor == null:
		app.queue_free()
		return
	editor.open_level("res://levels/weight_yard.tres")
	_check(editor.draft.weight_positions == YARD.weight_positions, "Шаблон грузов доступен редактору")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		await _layout()
		var button := editor.tool_buttons[LevelCanvas.Tool.HANGING_WEIGHT]
		var scroll := button.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(button)
		await _layout()
		_check(scroll.get_global_rect().encloses(button.get_global_rect()), "Инструмент доступен в окне %s" % dimensions)
		var touch := dimensions.x != 1280
		_click(button, touch)
		var point := editor.canvas.global_position + editor.canvas.world_to_local(Vector2(600, 330))
		_pointer(point, true, touch)
		_pointer(point, false, touch)
		await _layout()
		_check(editor.draft.weight_positions.size() == 3 and editor.canvas.selected_kind == 2, "Мышь/касание создаёт один груз")
		await _snapshot("editor", dimensions)
		editor.undo()
		_check(editor.draft.weight_positions == YARD.weight_positions, "Отмена удаляет добавленный груз")
		editor.redo()
		_check(editor.draft.weight_positions.size() == 3, "Возврат восстанавливает груз")
		editor.canvas.selected_kind = 2
		editor.canvas.selected_index = 2
		editor._begin_edit()
		editor.canvas.move_selected(Vector2(1240, 100))
		editor._finish_edit()
		var bounds := Rect2(editor.canvas.selected_position() + HangingWeightVisual.BOUNDS.position, HangingWeightVisual.BOUNDS.size)
		_check(LevelCanvas.BUILD_AREA.encloses(bounds), "При перемещении ограничены и груз и вся верёвка")
		editor.undo()
		var start := editor.canvas.global_position + editor.canvas.world_to_local(Vector2(600, 330))
		_pointer(start, true, touch)
		_drag(editor.canvas.global_position + editor.canvas.world_to_local(Vector2(620, 360)), touch)
		_pointer(editor.canvas.global_position + editor.canvas.world_to_local(Vector2(620, 360)), false, touch)
		await _layout()
		_check(editor.draft.weight_positions[2] == Vector2(620, 360), "Мышь/касание переносит груз вместе с верёвкой")
		editor.canvas.delete_selected()
		_check(editor.draft.weight_positions == YARD.weight_positions, "Удаление сохраняет остальные грузы")
		editor.undo()
		_check(editor.draft.weight_positions[2] == Vector2(620, 360), "Отмена удаления возвращает груз")
		editor.undo()
		editor.undo()
		editor.undo()
		_check(editor.draft.weight_positions == YARD.weight_positions, "История возвращается к шаблону")
	app.queue_free()
	await _layout()


func _test_round(dimensions: Vector2i) -> void:
	var game := MAIN.instantiate() as GameRound
	game.level = YARD.duplicate(true) as LevelDefinition
	root.add_child(game)
	current_scene = game
	_playbacks.append(weakref(game.background_music.get_stream_playback()))
	await _ticks(90)
	var weights: Array[HangingWeight] = []
	for actor in game.actors.get_children():
		if actor is HangingWeight:
			weights.append(actor)
	_check(weights.size() == 2 and game.dogs_left == 2, "В бою загружены грузы и живые цели")
	await _snapshot("ready", dimensions)
	var touch := dimensions.x != 1280
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	var end := anchor + Vector2(-70, 78)
	_pointer(anchor, true, touch)
	_drag(end, touch)
	_pointer(end, false, touch)
	_check(game.shots_left == 3 and game.state == GameRound.RoundState.FLYING, "Настоящий жест запускает ровно одного кота")
	while game._flight_time < 0.65 / Slingshot.FLIGHT_SPEED_SCALE and game.state == GameRound.RoundState.FLYING:
		await physics_frame
	game.use_ability()
	await _ticks(25)
	await _snapshot("falling", dimensions)
	for tick in 480:
		if game.state != GameRound.RoundState.FLYING:
			break
		await physics_frame
	_check(not weights[0].suspended and not weights[1].suspended, "Бросок рогаткой разрывает обе верёвки")
	_check(game.state == GameRound.RoundState.WON and game.dogs_left == 0, "Падающие грузы обрушают перекрытия и поражают обе цели")
	_check(game.level.weight_positions == YARD.weight_positions, "Физика не меняет ресурс уровня")
	await _snapshot("result", dimensions)
	game.queue_free()
	await _layout()


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
	await process_frame


func _layout() -> void:
	for frame in 5:
		await process_frame


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _drag(point: Vector2, touch: bool) -> void:
	if touch:
		var event := InputEventScreenDrag.new()
		event.position = point
		event.index = 0
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _click(button: BaseButton, touch: bool) -> void:
	_pointer(button.get_global_rect().get_center(), true, touch)
	_pointer(button.get_global_rect().get_center(), false, touch)


func _snapshot(label: String, dimensions: Vector2i) -> void:
	if not _capture:
		return
	await _layout()
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/weights-%s-%dx%d.png" % [label, dimensions.x, dimensions.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Сохранён кадр " + path)


func _music_released() -> bool:
	for playback in _playbacks:
		if playback.get_ref() != null:
			return false
	return true


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
