extends SceneTree
## Пружины: физические контакты, пауза, редактор и перенос данных.

const SPRING := preload("res://scenes/actors/spring_pad.tscn")
const CAT := preload("res://scenes/actors/cat_projectile.tscn")
const BLOCK := preload("res://scenes/actors/wooden_block.tscn")
const WEIGHT := preload("res://scenes/actors/hanging_weight.tscn")
const EDITOR := preload("res://scenes/editor/level_editor.tscn")
const MAIN := preload("res://scenes/main.tscn")
const YARD := preload("res://levels/spring_yard.tres")

var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _music_playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_capture = "--capture-springs" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	GameLocalization.apply_locale("ru")
	_test_data()
	await _test_physics()
	await _test_editor()
	await _test_round()
	var deadline := Time.get_ticks_msec() + 1000
	while not _music_released() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(_music_released(), "Пробные бои освободили аудиопотоки")
	print("Spring checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_data() -> void:
	var level := YARD.duplicate(true) as LevelDefinition
	_check(level.is_valid(), "Демонстрационный двор корректен")
	var data := LevelData.to_dictionary(level)
	data.erase("spring_positions")
	_check(LevelData.from_dictionary(data).spring_positions.is_empty(), "Старые уровни открываются без пружин")
	_check(not LevelData.to_dictionary(LevelData.from_dictionary(data), false).has("spring_positions"), "Пустые пружины не меняют прежние отпечатки прохождения")
	for invalid: Variant in [true, [["x", 602]], [[620, 603]], [[400, 602]], [[620]], null]:
		data["spring_positions"] = invalid
		_check(LevelData.from_dictionary(data) == null, "Повреждённые пружины отклоняются: " + str(invalid))
	var overflowing := level.duplicate(true) as LevelDefinition
	overflowing.spring_positions.resize(LevelDefinition.MAX_OBJECTS + 1)
	overflowing.spring_positions.fill(Vector2(620, 602))
	_check(not overflowing.is_valid(), "Лимит числа пружин проверяется")
	overflowing.spring_positions = PackedVector2Array([Vector2(INF, 602)])
	_check(not overflowing.is_valid(), "Бесконечные координаты отклоняются")
	level.record_author_completion(1, &"classic", &"scout")
	var restored := LevelExchange.decode(LevelExchange.encode(level))
	_check(restored != null and restored.spring_positions == level.spring_positions and restored.is_author_completed(), "Обмен сохраняет пружины и отметку прохождения")
	level.spring_positions[0].x += 10
	_check(not level.is_author_completed(), "Перенос пружины сбрасывает отметку прохождения")
	var path := "user://spring-test-%d.cvdlevel" % Time.get_ticks_usec()
	_check(LevelExchange.write_file(level, path) == OK and LevelExchange.read_file(path).spring_positions == level.spring_positions, "Файл обмена сохраняет пружины")
	DirAccess.remove_absolute(path)
	path = "user://spring-draft-%d.json" % Time.get_ticks_usec()
	var store := EditorDraftStore.new(path)
	_check(store.save_draft(level, "", true) == OK and store.load_draft().level.spring_positions == level.spring_positions, "Восстановление черновика сохраняет пружины")
	DirAccess.remove_absolute(path)
	var saved := LevelLibrary.save_level(level)
	_check(saved.error == OK and LevelLibrary.load_level(saved.path).spring_positions == level.spring_positions, "Библиотека сохраняет пружины")
	DirAccess.remove_absolute(saved.path)
	var bodies := LevelLayoutReview.objects(level)
	_check(bodies.filter(func(body: Dictionary) -> bool: return body.kind == 3).size() == 2, "Проверка построек учитывает пружины")
	var same_place := BuildingTemplates.at_position(0, Vector2(620, 602))
	var occupied := LevelDefinition.new()
	occupied.spring_positions.append(same_place.block_positions[0])
	_check(not BuildingTemplates.placement_error(occupied, same_place).is_empty(), "Постройка не размещается поверх пружины")


func _test_physics() -> void:
	for kind in ["cat", "block", "weight"]:
		var world := Node2D.new()
		root.add_child(world)
		var spring := SPRING.instantiate() as SpringPad
		spring.position = Vector2(650, 550)
		world.add_child(spring)
		var body: RigidBody2D
		if kind == "cat":
			var cat := CAT.instantiate() as CatProjectile
			cat.definition = CharacterCatalog.find_cat(&"classic")
			body = cat
		elif kind == "block":
			var block := BLOCK.instantiate() as WoodenBlock
			block.size = Vector2(40, 40)
			body = block
		else:
			body = WEIGHT.instantiate() as HangingWeight
		body.position = Vector2(650, 430)
		world.add_child(body)
		var activations: Array[int] = [0]
		spring.activated.connect(func(_body: RigidBody2D) -> void: activations[0] += 1)
		if body is HangingWeight:
			await _ticks(20)
			_check(activations[0] == 0 and body.freeze, "Подвешенный груз не запускается")
			body.rope.receive_hit(1000)
			await _ticks(2)
		if body is CatProjectile:
			body.set_flight_speed_scale(0.6)
			body.launch(Vector2(0, 220))
		else:
			body.linear_velocity = Vector2(0, 220)
		for tick in 90:
			await _ticks(1)
			if activations[0] > 0:
				break
		_check(activations[0] == 1 and body.linear_velocity.y < -200, "Реальный контакт подбрасывает " + kind)
		if body is CatProjectile:
			_check(absf(body.linear_velocity.y + spring.launch_speed * 0.6) < 30, "Скорость кота учитывает замедленный полёт")
		var before := body.position
		var animation := spring._animation_left
		paused = true
		await _ticks(10)
		_check(body.position == before and spring._animation_left == animation, "Пауза останавливает подброс и анимацию: " + kind)
		paused = false
		await _ticks(3)
		_check(body.position.y < before.y, "После паузы подброс продолжается: " + kind)
		await _ticks(300)
		_check(activations[0] == 1 and (not is_instance_valid(body) or body.linear_velocity.length() < 35), "Повторное падение не создаёт бесконечные подскоки: " + kind)
		world.queue_free()
		await _ticks(2)
	# Боковой пролёт и движение снизу не должны давать подброс.
	var world := Node2D.new()
	root.add_child(world)
	var spring := SPRING.instantiate() as SpringPad
	world.add_child(spring)
	spring.position = Vector2(650, 550)
	var cat := CAT.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.find_cat(&"classic")
	cat.position = Vector2(650, 495)
	world.add_child(cat)
	cat.launch(Vector2(400, -200))
	await _ticks(12)
	_check(spring._launched.is_empty(), "Поднимающийся кот не запускается повторно")
	world.queue_free()
	await _ticks(2)


func _test_editor() -> void:
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = window_size
		if _capture:
			DisplayServer.window_set_size(window_size)
		var editor := EDITOR.instantiate() as LevelEditor
		editor.recovery_path = ""
		root.add_child(editor)
		await _ticks(5)
		await _choose_spring(editor, false)
		await _pointer(editor.canvas, Vector2(620, 600), false, true)
		_check(editor.draft.spring_positions == PackedVector2Array([Vector2(620, 600)]), "Мышь размещает пружину: " + str(window_size))
		_check(editor.canvas.selected_kind == 3 and editor.canvas.tool == LevelCanvas.Tool.SELECT, "Пружина выбрана после размещения")
		editor.undo()
		_check(editor.draft.spring_positions.is_empty(), "Отмена удаляет пружину")
		editor.redo()
		_check(editor.draft.spring_positions.size() == 1, "Повтор возвращает пружину")
		await _choose_spring(editor, true)
		await _pointer(editor.canvas, Vector2(1100, 600), true, true)
		_check(editor.draft.spring_positions.size() == 2, "Касание размещает вторую пружину")
		await _pointer(editor.canvas, Vector2(1100, 600), true, false)
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = editor.canvas.global_position + editor.canvas.world_to_local(Vector2(1000, 540))
		root.push_input(drag, true)
		await _ticks(2)
		var cancel := InputEventScreenTouch.new()
		cancel.index = 0
		cancel.canceled = true
		cancel.position = drag.position
		root.push_input(cancel, true)
		await _ticks(2)
		_check(editor.draft.spring_positions[1] == Vector2(1100, 600), "Отмена касания возвращает пружину")
		editor.canvas.selected_kind = 3
		editor.canvas.selected_index = 1
		editor.canvas.move_selected(Vector2(9999, 9999))
		_check(editor.draft.spring_positions[1] == Vector2(1192, 602), "Пружина остаётся в пределах поля")
		if _capture:
			await _capture_frame("editor", window_size)
		editor.canvas.delete_selected()
		_check(editor.draft.spring_positions.size() == 1, "Удаление пружины")
		editor.undo()
		_check(editor.draft.spring_positions.size() == 2, "Отмена удаления пружины")
		editor.queue_free()
		await _ticks(3)


func _test_round() -> void:
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = window_size
		if _capture:
			DisplayServer.window_set_size(window_size)
		var game := MAIN.instantiate() as GameRound
		game.level = YARD.duplicate(true) as LevelDefinition
		game.level.shots = 1
		game.editor_preview = true
		root.add_child(game)
		_music_playbacks.append(weakref(game.background_music.get_stream_playback()))
		await _ticks(5)
		var springs := game.actors.get_children().filter(func(body: Node) -> bool: return body is SpringPad)
		_check(springs.size() == 2, "Пробный бой создаёт пружины из уровня")
		if _capture:
			await _capture_frame("round", window_size)
		await _shoot(game, window_size.x == 1600)
		_check(game.shots_left == 0 and game.state == GameRound.RoundState.FLYING, "Мышь/касание запускает последний бросок")
		for tick in 200:
			await _ticks(1)
			if not springs[0]._launched.is_empty():
				break
		_check(not springs[0]._launched.is_empty(), "Кот из рогатки попадает на пружину")
		if _capture:
			await _capture_frame("bounce", window_size)
		for tick in 800:
			await _ticks(1)
			if game.state in [GameRound.RoundState.WON, GameRound.RoundState.LOST]:
				break
		_check(game.state == GameRound.RoundState.WON and game.dogs_left == 0, "Подброс даёт победу на последнем броске")
		await _ticks(40)
		if _capture:
			await _capture_frame("victory", window_size)
		game.queue_free()
		await _ticks(12)


func _choose_spring(editor: LevelEditor, touch: bool) -> void:
	var button := editor.tool_buttons[LevelCanvas.Tool.SPRING]
	var scroll := button.get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(button)
	await _ticks(4)
	var position := button.get_global_rect().get_center()
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = true
		root.push_input(event, true)
		event = InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		root.push_input(event, true)
		event = InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		root.push_input(event, true)
	await _ticks(3)
	_check(editor.canvas.tool == LevelCanvas.Tool.SPRING, "Кнопка пружины доступна мышью/касанием")


func _shoot(game: GameRound, touch: bool) -> void:
	var transform := game.slingshot.get_global_transform_with_canvas()
	var start := transform * Vector2.ZERO
	var end := transform * Vector2(-100, 10)
	if touch:
		var press := InputEventScreenTouch.new()
		press.position = start
		press.pressed = true
		root.push_input(press, true)
		await _ticks(2)
		var drag := InputEventScreenDrag.new()
		drag.position = end
		root.push_input(drag, true)
		await _ticks(2)
		var release := InputEventScreenTouch.new()
		release.position = end
		root.push_input(release, true)
	else:
		var press := InputEventMouseButton.new()
		press.position = start
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press, true)
		await _ticks(2)
		var drag := InputEventMouseMotion.new()
		drag.position = end
		drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(drag, true)
		await _ticks(2)
		var release := InputEventMouseButton.new()
		release.position = end
		release.button_index = MOUSE_BUTTON_LEFT
		root.push_input(release, true)
	await _ticks(2)


func _pointer(canvas: LevelCanvas, point: Vector2, touch: bool, release: bool) -> void:
	var position := canvas.global_position + canvas.world_to_local(point)
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = true
		root.push_input(event, true)
		await _ticks(2)
		if release:
			event = InputEventScreenTouch.new()
			event.index = 0
			event.position = position
			root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		root.push_input(event, true)
		await _ticks(2)
		if release:
			event = InputEventMouseButton.new()
			event.position = position
			event.button_index = MOUSE_BUTTON_LEFT
			root.push_input(event, true)
	await _ticks(3)


func _capture_frame(screen: String, window_size: Vector2i) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/spring-%s-%dx%d.png" % [screen, window_size.x, window_size.y])


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _music_released() -> bool:
	for playback in _music_playbacks:
		if playback.get_ref() != null:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
