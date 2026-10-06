extends SceneTree
## Принятые удары, бюджет FX, пауза, звук и неизменность физического результата.

const MAIN := preload("res://scenes/main.tscn")
const BLOCK := preload("res://scenes/actors/wooden_block.tscn")
const DOG := preload("res://scenes/actors/dog_target.tscn")

var _checks: int = 0
var _failures: int = 0
var _playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus := AudioServer.get_bus_index(&"SFX")
	var was_muted := AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, false)
	await _test_sources()
	await _test_feedback(bus)
	await _test_sound_priority()
	for enabled in [false, true]:
		await _test_real_throw(enabled)
	AudioServer.set_bus_mute(bus, was_muted)
	var deadline := Time.get_ticks_msec() + 1000
	while _music_alive() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(not _music_alive(), "Удаление раундов освобождает музыку")
	print("Impact feedback checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_sources() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var block := _block(world)
	var events: Array[float] = []
	block.impact_received.connect(func(strength: float) -> void: events.append(strength))
	block.receive_hit(block.impact_threshold - 1.0)
	_check(events.is_empty(), "Слабое касание не сообщает о принятом ударе")
	block.receive_hit(800.0)
	block.receive_hit(10000.0)
	_check(events == [800.0] and block.hits_left == 2, "Принятый удар сообщает силу один раз, повторный контакт подавлен")
	await _ticks(17)
	block.receive_hit(10000.0)
	_check(events == [800.0, 10000.0], "Смертельный удар сообщает силу до удаления тела")
	var dog := DOG.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(&"armored")
	dog.freeze = true
	world.add_child(dog)
	var shield_hits: Array[float] = []
	dog.impact_received.connect(func(strength: float) -> void: shield_hits.append(strength))
	dog.receive_hit(1000.0)
	dog.receive_hit(1000.0)
	_check(shield_hits == [1000.0] and not dog.is_destroyed and not dog.shield_active, "Щит даёт один ударный отклик без ложного поражения")
	var silent := _block(world)
	silent.impact_received.connect(func(strength: float) -> void: events.append(strength))
	silent.destroy()
	_check(events.size() == 2, "Удаление за границей или вручную не становится попаданием")
	world.queue_free()
	await process_frame


func _test_feedback(bus: int) -> void:
	var level := LevelDefinition.new()
	level.dog_positions = PackedVector2Array([Vector2(1150, 595)])
	var game := _game(level)
	var feedback := game.get_node("ImpactFeedback") as ImpactFeedback
	var audio := WorldAudio.new()
	game.add_child(audio)
	var impacts: Array[Dictionary] = []
	var sounds: Array[StringName] = []
	feedback.impact_presented.connect(func(point: Vector2, intensity: float, material_id: StringName) -> void: impacts.append({"point": point, "intensity": intensity, "material": material_id}))
	audio.effect_played.connect(func(effect: StringName) -> void: sounds.append(effect))
	await process_frame
	await _ticks(60)
	_check(impacts.is_empty() and game.camera.offset == Vector2.ZERO, "Ожидание перед броском не трясёт камеру и не создаёт FX")
	game.state = GameRound.RoundState.FLYING
	var weak := _block(game.actors)
	weak.receive_hit(600.0)
	await process_frame
	_check(impacts.is_empty(), "Обычный принятый удар остаётся без усиленного отклика")
	var first := _block(game.actors)
	var second := _block(game.actors)
	await process_frame
	seed(413)
	var expected_random := randi()
	seed(413)
	first.receive_hit(800.0)
	second.receive_hit(1400.0)
	await process_frame
	await process_frame
	_check(randi() == expected_random, "FX не меняет последовательность игрового RNG")
	_check(impacts.size() == 1 and impacts[0].intensity > 0.7, "Одновременные контакты объединяются с силой самого мощного")
	_check(sounds.count(&"impact") == 1, "Отклик добавляет один низкий звук через SFX")
	_check(feedback.get_child_count() == 1 and feedback.get_child(0) is ImpactBurst, "Отклик создаёт отдельный декоративный узел")
	_check(first.freeze and first.linear_velocity == Vector2.ZERO and first.hits_left == 2 and second.hits_left == 1, "Отклик сохраняет скорости, режим тела и рассчитанный урон")
	var before := impacts.size()
	for index in 40:
		var body := _block(game.actors)
		body.receive_hit(10000.0)
	await process_frame
	_check(impacts.size() == before, "Обвал не создаёт сорок одновременных вспышек")
	var burst := feedback.get_child(0) as ImpactBurst
	var elapsed := burst.elapsed
	var camera_offset := game.camera.offset
	paused = true
	first.impact_received.emit(1500.0)
	await create_timer(0.06, true).timeout
	_check(impacts.size() == before and burst.elapsed == elapsed and game.camera.offset == camera_offset, "Пауза останавливает вспышку и камеру и подавляет новые отклики")
	paused = false
	await create_timer(0.45).timeout
	_check(feedback.get_child_count() == 0 and game.camera.offset == Vector2.ZERO, "Через короткое время FX удаляется, камера точно возвращается")
	AudioServer.set_bus_mute(bus, true)
	game.state = GameRound.RoundState.FLYING
	var muted := _block(game.actors)
	muted.receive_hit(1000.0)
	await process_frame
	await process_frame
	_check(impacts.size() == before + 1 and sounds.count(&"impact") == 1, "Без звука сохраняется визуальный отклик, SFX не запускается")
	AudioServer.set_bus_mute(bus, false)
	game.camera.zoom = Vector2(2, 2)
	var home := game.camera.position
	game.camera.punch(1.0, Vector2.RIGHT)
	_check((game.camera.offset * game.camera.zoom).length() <= game.camera.max_impact_pixels + 0.01 and game.camera.position == home, "Толчок ограничен экранными пикселями и не меняет центр камеры")
	game.camera.force_update_scroll()
	var pointer := root.get_visible_rect().get_center()
	var world_anchor := game.camera.get_canvas_transform().affine_inverse() * pointer
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = pointer
	wheel.pressed = true
	root.push_input(wheel, true)
	var after_anchor := game.camera.get_canvas_transform().affine_inverse() * pointer
	_check(world_anchor.distance_to(after_anchor) < 0.1, "Zoom во время толчка сохраняет точку мира под курсором")
	game.camera.reset_view()
	_check(game.camera.offset == Vector2.ZERO and game.camera.zoom == Vector2.ONE, "Сброс обзора сразу убирает остаточный толчок")
	feedback.max_bursts = 1
	feedback.impact_interval = 0.0
	await create_timer(0.1).timeout
	game.state = GameRound.RoundState.FLYING
	game._flight_time = 0.0
	game._still_time = 0.0
	var budget_before := impacts.size()
	for index in 8:
		var body := _block(game.actors)
		body.receive_hit(1500.0)
		await process_frame
		await process_frame
	_check(impacts.size() >= budget_before + 4 and feedback.get_child_count() <= 1, "Бюджет декоративных узлов действует при непрерывных ударах")
	await _dispose(game)


func _test_sound_priority() -> void:
	var level := LevelDefinition.new()
	level.dog_positions = PackedVector2Array([Vector2(1150, 595)])
	var game := _game(level)
	var audio := WorldAudio.new()
	game.add_child(audio)
	await process_frame
	await process_frame
	for index in 3:
		game.slingshot.launched.emit(game.slingshot.loaded_projectile)
	var voices := 0
	for player: AudioStreamPlayer in audio.get_children():
		voices += 1 if player.playing else 0
	_check(voices == WorldAudio.MAX_VOICES, "Проверка сильного звука начинается с занятых шести каналов")
	var before := audio.play_count
	var feedback := game.get_node("ImpactFeedback") as ImpactFeedback
	feedback.impact_presented.emit(Vector2(700, 400), 1.0, &"metal")
	_check(audio.play_count == before + 1 and audio.get_child_count() == WorldAudio.MAX_VOICES, "Сильный удар слышен при занятых каналах без создания новых игроков")
	audio.play_victory()
	before = audio.play_count
	feedback.impact_presented.emit(Vector2(700, 400), 1.0, &"metal")
	_check(audio.play_count == before, "Поздний сильный удар не перебивает сигнал победы")
	await _dispose(game)


func _test_real_throw(enabled: bool) -> void:
	var game := _game(CampaignCatalog.LEVELS[6])
	var feedback := game.get_node("ImpactFeedback") as ImpactFeedback
	if not enabled:
		feedback.process_mode = Node.PROCESS_MODE_DISABLED
	var count: Array[int] = [0]
	feedback.impact_presented.connect(func(_point: Vector2, _intensity: float, _material: StringName) -> void: count[0] += 1)
	await _ticks(66)
	_check(game.slingshot.launch_from_pull(Vector2(-70, 78)), "Настоящий бросок запускает обрушение")
	var used := false
	for tick in 900:
		await physics_frame
		if game.state != GameRound.RoundState.FLYING:
			break
		if not used and game._flight_time >= 0.65:
			used = true
			game.use_ability()
	_check(game.state == GameRound.RoundState.WON and game.level.shots - game.shots_left == 1, "Включение/отключение отклика сохраняет победу одним броском")
	_check(count[0] > 0 if enabled else count[0] == 0, "Отклик возникает от реальных столкновений только при включённом компоненте")
	await _dispose(game)


func _game(level: LevelDefinition) -> GameRound:
	paused = false
	var game := MAIN.instantiate() as GameRound
	game.level = level.duplicate(true) as LevelDefinition
	if DisplayServer.get_name() == "headless":
		game.hide()
	root.add_child(game)
	current_scene = game
	return game


func _block(parent: Node) -> WoodenBlock:
	var block := BLOCK.instantiate() as WoodenBlock
	block.material_id = &"metal"
	block.position = Vector2(650, 350)
	block.freeze = true
	parent.add_child(block)
	return block


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _dispose(game: GameRound) -> void:
	_playbacks.append(weakref(game.background_music.get_stream_playback()))
	var reference: WeakRef = weakref(game.get_node("ImpactFeedback"))
	game.queue_free()
	await process_frame
	await process_frame
	_check(reference.get_ref() == null, "Отклик и его декоративные узлы удаляются вместе с раундом")


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
