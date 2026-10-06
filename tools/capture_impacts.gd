extends SceneTree
## Настоящие броски мышью/касанием; снимки ударов и результата, отдельный образец материалов.

const MAIN := preload("res://scenes/main.tscn")
const DIMENSIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0
var _playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для просмотра попаданий нужен графический запуск")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	if not "--materials-only" in OS.get_cmdline_user_args():
		for index in DIMENSIONS.size():
			root.size = DIMENSIONS[index]
			await _round(index)
	await _materials()
	var deadline := Time.get_ticks_msec() + 1000
	while _music_alive() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(not _music_alive(), "Удаление сцен освобождает музыкальные потоки")
	print("Impact graphic checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _round(index: int) -> void:
	paused = false
	var game := MAIN.instantiate() as GameRound
	game.level = CampaignCatalog.LEVELS[6 + index].duplicate(true) as LevelDefinition
	root.add_child(game)
	current_scene = game
	var audio := WorldAudio.new()
	game.add_child(audio)
	var feedback := game.get_node("ImpactFeedback") as ImpactFeedback
	var impacts: Array[Dictionary] = []
	var sounds: Array[StringName] = []
	feedback.impact_presented.connect(func(point: Vector2, intensity: float, material: StringName) -> void: impacts.append({"point": point, "intensity": intensity, "material": material}))
	audio.effect_played.connect(func(effect: StringName) -> void: sounds.append(effect))
	for tick in 600:
		await physics_frame
	_check(impacts.is_empty() and game.dogs_left == 2, "Без броска нет вспышек и поражения целей")
	await _shot("ready", index)
	var hud_rect := game.hud._pause_button.get_global_rect()
	var touch := index != 0
	var transform := game.slingshot.get_global_transform_with_canvas()
	var pull := Vector2(-60, 86) if index == 2 else Vector2(-70, 78)
	_pointer(transform.origin, true, touch)
	_drag(transform * pull, touch)
	_pointer(transform * pull, false, touch)
	_check(game.state == GameRound.RoundState.FLYING and game.shots_left == 3, "Жест мыши/касания запускает одного кота")
	var activated := false
	var captured := false
	for tick in 1800:
		await physics_frame
		if not activated and game._flight_time >= 0.65 and game.state == GameRound.RoundState.FLYING:
			activated = true
			if touch:
				var center := game.hud._ability_button.get_global_rect().get_center()
				_pointer(center, true, true)
				_pointer(center, false, true)
			else:
				for pressed in [true, false]:
					var event := InputEventKey.new()
					event.physical_keycode = KEY_E
					event.pressed = pressed
					root.push_input(event, true)
		if not captured and not impacts.is_empty():
			captured = true
			await _shot("impact", index)
			_check((game.camera.offset * game.camera.zoom).length() <= game.camera.max_impact_pixels + 0.1, "Даже сильнейший удар ограничен шестью экранными пикселями")
			for step in 4:
				await physics_frame
			await _shot("fragments", index)
		if game.state != GameRound.RoundState.FLYING:
			break
	_check(captured and sounds.count(&"impact") > 0, "Настоящие столкновения создают вспышку и низкий звук")
	_check(game.hud._pause_button.get_global_rect().is_equal_approx(hud_rect), "Удар камеры не двигает кнопки HUD")
	_check(game.state == GameRound.RoundState.WON and game.dogs_left == 0, "Обвал сохраняет настоящую победу одним броском")
	await _shot("result", index)
	print("Impact replay ", game.level.title, ": ", impacts.size(), " visual impacts, ", sounds.count(&"impact"), " low sounds")
	_playbacks.append(weakref(game.background_music.get_stream_playback()))
	game.queue_free()
	for frame in 5:
		await process_frame


func _materials() -> void:
	root.size = Vector2i(960, 720)
	for frame in 5:
		await process_frame
	var stage_size := root.get_visible_rect().size
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var background := Polygon2D.new()
	background.polygon = PackedVector2Array([Vector2.ZERO, Vector2(stage_size.x, 0), stage_size, Vector2(0, stage_size.y)])
	background.color = Color("347967")
	world.add_child(background)
	for index in BlockMaterials.IDS.size():
		var burst := ImpactBurst.new()
		burst.material_id = BlockMaterials.IDS[index]
		burst.position = Vector2(stage_size.x * (0.2 + index * 0.2), stage_size.y * 0.48)
		burst.elapsed = 0.065
		burst.process_mode = Node.PROCESS_MODE_DISABLED
		world.add_child(burst)
		burst.queue_redraw()
		var label := Label.new()
		label.position = burst.position + Vector2(-70, 110)
		label.text = TranslationServer.translate(BlockMaterials.get_definition(burst.material_id).display_name)
		label.add_theme_font_size_override("font_size", 28)
		world.add_child(label)
	await _shot("materials", 2)
	world.queue_free()
	await process_frame


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)


func _drag(point: Vector2, touch: bool) -> void:
	if touch:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = point
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _shot(phase: String, index: int) -> void:
	await RenderingServer.frame_post_draw
	var dimensions := DIMENSIONS[index]
	var path := "res://.artifacts/impact-%s-%dx%d.png" % [phase, dimensions.x, dimensions.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Кадр эффекта сохранён")


func _music_alive() -> bool:
	for reference in _playbacks:
		if reference.get_ref() != null:
			return true
	return false


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("FAIL: " + message)
