extends SceneTree
## Воспроизводимые прохождения рогаткой. Никаких подмен скорости, целей или столкновений.
## tools/check.ps1 использует --fixed-fps 60 без привязки к реальному времени.
## Один кадр на физический тик сохраняет порядок отложенных разрушений и запусков.

const MAIN := preload("res://scenes/main.tscn")
## Для каждого выстрела: натяжение x/y в мировых пикселях, время попытки способности.
## -1 означает бросок без ручной активации; автоматические способности работают как в игре.
## Если кот уже столкнулся с постройкой, недоступная способность не заменяет обычный удар.
const ROUTES := {
	# Первый урок проходится обычными бросками: способность изучается во втором.
	"01_first_throw": [[-70.0, 31.0, -1.0], [-91.0, 40.0, -1.0]],
	"02_air_trick": [[-73.0, 24.0, 0.55], [-63.0, 63.0, -1.0]],
	"03_little_shelter": [[-60.0, 66.0, -1.0], [-66.0, 60.0, -1.0], [-85.0, 28.0, 0.2]],
	"04_glass_bridge": [[-99.86, 32.45, 0.35], [-78.03, 70.26, -1.0], [-95.92, 42.71, 0.75], [-90.93, 52.5, 0.65], [-90.93, 52.5, 0.65]],
	"05_restless_yard": [[-62.0, 45.0, 0.4], [-62.0, 45.0, -1.0], [-82.0, 36.0, -1.0], [-66.0, 60.0, -1.0], [-85.0, 28.0, 0.6], [-85.0, 28.0, 0.2]],
	"06_last_fort": [[-99.86, 32.45, -1.0], [-52.9, 72.81, 0.6], [-99.86, 32.45, -1.0], [-84.95, 61.72, 0.65], [-99.86, 32.45, 0.4], [-90.93, 52.5, 0.55], [-90.93, 52.5, 0.65], [-90.93, 52.5, 0.65], [-90.93, 52.5, 0.65]],
	"07_falling_gallery": [[-70.0, 78.0, 0.65]],
	"08_double_drop": [[-70.0, 78.0, 0.65]],
	"09_weight_cascade": [[-60.0, 86.0, 0.65]],
	"10_open_passage": [[-85, 28, 0.35], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"11_wind_stairs": [[-70, 55, 0.65], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"12_glass_garden": [[-70, 55, 0.65], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"13_stone_gate": [[-70, 78, 0.8], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"14_magnetic_roof": [[-70, 55, 0.65], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"15_high_watch": [[-74, 74, 0.9], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"16_frozen_patrol": [[-70, 31, 0.6], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"17_shield_line": [[-70, 55, 0.65], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"18_ice_roofs": [[-70, 78, 0.7], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"19_three_shelters": [[-85, 28, -1], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
	"20_last_outpost": [[-70, 55, 0.65], [-85, 28, 0.35], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3], [-85, 28, 0.3]],
}

var _checks: int = 0
var _failures: int = 0
var _music_playbacks: Array[WeakRef] = []
var _capture: bool = false
var _touch: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture = "--capture-balance" in OS.get_cmdline_user_args()
	if _capture:
		_check(DisplayServer.get_name() != "headless", "Снимкам нужен графический запуск")
		if _failures:
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute("res://.artifacts")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 120
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX"), true)
	var level_index := 0
	var selected_level := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			selected_level = argument.trim_prefix("--level=")
	if not selected_level.is_empty() and not ROUTES.has(selected_level):
		push_error("Unknown campaign route: " + selected_level)
		quit(1)
		return
	for level_id: String in ROUTES:
		if not selected_level.is_empty() and level_id != selected_level:
			continue
		if "--chains-only" in OS.get_cmdline_user_args() and not level_id.begins_with("07_") and not level_id.begins_with("08_") and not level_id.begins_with("09_"):
			continue
		if "--new-only" in OS.get_cmdline_user_args() and int(level_id.left(2)) < 10:
			continue
		if _capture:
			root.size = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)][level_index % 3]
			_touch = level_index % 2 == 1 or "--touch" in OS.get_cmdline_user_args()
		var level := load("res://levels/campaign/%s.tres" % level_id) as LevelDefinition
		await _check_stability(level)
		for attempt in (1 if _capture else 4):
			await _replay(level_id, level, ROUTES[level_id], attempt)
			if level_id == "04_glass_bridge" and attempt == 0:
				# После обрушения переиспользованные RID меняют порядок контактов новой постройки.
				await _check_stability(level)
		level_index += 1
	# При --fixed-fps игровой таймер не гарантирует реального такта аудиомикшера.
	var audio_deadline := Time.get_ticks_msec() + 1000
	while not _music_released() and Time.get_ticks_msec() < audio_deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(_music_released(), "Removed campaign rounds release their music playback")
	print("Campaign physics routes: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _check_stability(level: LevelDefinition) -> void:
	var game := _round(level)
	var bodies: Array[Dictionary] = []
	for actor in game.actors.get_children():
		if actor is WoodenBlock:
			bodies.append({"body": weakref(actor), "hits": actor.hits_left, "position": actor.position, "index": bodies.size()})
	for tick in 600:
		await physics_frame
	_check(game.dogs_left == level.dog_positions.size(), level.title + ": все собаки переживают 10 s ожидания")
	for actor in game.actors.get_children():
		if actor is HangingWeight:
			_check(actor.suspended and actor.position in level.weight_positions, level.title + ": груз ждёт попадания в верёвку")
	for record in bodies:
		var body := (record["body"] as WeakRef).get_ref() as WoodenBlock
		var intact: bool = is_instance_valid(body) and not body.is_destroyed and body.hits_left == record["hits"]
		var label := "%s: элемент %d %s" % [level.title, record["index"], record["position"]]
		_check(intact, label + " не получает урон до первого выстрела")
		if intact:
			# Малые зубцы могут усесться на несколько пикселей шире несущих балок.
			var settle_margin: float = 16.0 if body.size.x * body.size.y < 1600.0 else 8.0
			_check(body.position.distance_to(record["position"]) < settle_margin, label + " сохраняет исходную опору")
			_check(body.linear_velocity.length() < 16.0, label + " успокаивается до первого выстрела")
	await _remove(game)


func _replay(level_id: String, level: LevelDefinition, route: Array, attempt: int) -> void:
	var game := _round(level)
	var chain_events: Array[Dictionary] = []
	if not level.weight_positions.is_empty():
		_watch_chain(game, chain_events)
	# Последний прогон проверяет броски после долгого оседания, как при изучении поля.
	for tick in (600 if attempt == 3 else 66):
		await physics_frame
	var results: Array = []
	game.round_completed.connect(func(won: bool, shots_used: int, stars: int) -> void: results.append([won, shots_used, stars]))
	if _capture:
		await _screenshot(level_id, "ready")
	var used := 0
	for planned_shot: Array in route:
		if game.state == GameRound.RoundState.WON:
			break
		_check(game.state == GameRound.RoundState.READY, level.title + ": следующий кот готов")
		if game.state != GameRound.RoundState.READY:
			break
		var shot := _aim_for_remaining_target(game, planned_shot).duplicate()
		# Небольшая погрешность пальца и времени E не должна ломать решение.
		var variation: float = -1.0 if attempt == 1 else (1.0 if attempt == 2 else 0.0)
		shot[0] += variation
		shot[1] += variation
		if shot[2] >= 0.0:
			shot[2] += variation * 0.05
			shot[2] /= Slingshot.FLIGHT_SPEED_SCALE
		_check(_launch(game, Vector2(shot[0], shot[1])), level.title + ": настоящий запуск из рогатки")
		used += 1
		var activated := false
		for tick in 1800:
			await physics_frame
			if game.state != GameRound.RoundState.FLYING:
				break
			if _capture and not chain_events.is_empty() and Engine.get_physics_frames() == chain_events[0].tick + 10:
				await _screenshot(level_id, "falling")
			if not activated and shot[2] >= 0.0 and game._flight_time + 0.0001 >= shot[2]:
				var cat := game._active_cat
				var available := is_instance_valid(cat) and cat.can_activate_ability()
				activated = true
				if available:
					_activate(game)
					_check(is_instance_valid(cat) and cat.ability_spent, level.title + ": доступная способность действительно сработала")
				else:
					_check(level.tutorial != &"ability" and (not is_instance_valid(cat) or cat._has_contacted or cat.ability_spent), level.title + ": раннее столкновение оставляет обычный бросок")
	_check(game.state == GameRound.RoundState.WON, level.title + ": маршрут побеждает")
	if game.state != GameRound.RoundState.WON:
		for actor in game.actors.get_children():
			if actor is DogTarget and not actor.is_destroyed:
				print("Remaining ", level_id, " target=", actor.position, " shelter_hp=", actor.shelter.hits_left if actor.is_sheltered() else 0)
	_check(used <= level.par_shots, level.title + ": маршрут укладывается в три звезды")
	_check(results == [[true, used, 3]], level.title + ": раунд действительно начисляет три звезды")
	if not level.weight_positions.is_empty():
		_check_chain(level_id, level, chain_events)
	if level.tutorial == &"ability":
		_check(game._tutorial_ability_used, level.title + ": учебный приём применён до столкновения")
	print("Route ", level_id, " attempt=", attempt + 1, " shots=", used, " won=", game.state == GameRound.RoundState.WON)
	if _capture:
		await _screenshot(level_id, "result")
	await _remove(game)


func _watch_chain(game: GameRound, events: Array[Dictionary]) -> void:
	var weights: Array[HangingWeight] = []
	for actor in game.actors.get_children():
		if actor is HangingWeight:
			weights.append(actor)
			var index := weights.size() - 1
			actor.rope.body_entered.connect(func(body: Node2D) -> void:
				var upper := body as HangingWeight
				if index > 0 and upper == weights[0] and upper.linear_velocity.length() >= actor.rope.impact_threshold:
					events.append({"kind": "weight_contact", "index": index, "tick": Engine.get_physics_frames()})
			)
			actor.released.connect(func() -> void:
				var upper_drop := weights[0].position.y - game.level.weight_positions[0].y
				events.append({"kind": "weight", "index": index, "tick": Engine.get_physics_frames(), "upper_drop": upper_drop})
			)
		elif actor is WoodenBlock:
			actor.destroyed.connect(func() -> void: events.append({"kind": "block", "tick": Engine.get_physics_frames()}))
		elif actor is DogTarget:
			actor.defeated.connect(func() -> void: events.append({"kind": "dog", "tick": Engine.get_physics_frames()}))


func _check_chain(level_id: String, level: LevelDefinition, events: Array[Dictionary]) -> void:
	var releases: Array[Dictionary] = events.filter(func(event: Dictionary) -> bool: return event.kind == "weight")
	var blocks: Array[Dictionary] = events.filter(func(event: Dictionary) -> bool: return event.kind == "block")
	var dogs: Array[Dictionary] = events.filter(func(event: Dictionary) -> bool: return event.kind == "dog")
	_check(releases.size() == level.weight_positions.size(), level.title + ": бросок освобождает все грузы")
	_check(not releases.is_empty() and not blocks.is_empty() and blocks[0].tick > releases[0].tick, level.title + ": разрушение начинается после падения груза")
	_check(dogs.size() == level.dog_positions.size() and not blocks.is_empty() and dogs[0].tick > blocks[0].tick, level.title + ": обвал предшествует поражению целей")
	if level_id == "09_weight_cascade":
		var contacts: Array[Dictionary] = events.filter(func(event: Dictionary) -> bool: return event.kind == "weight_contact")
		_check(contacts.size() == 1 and releases.size() == 2 and contacts[0].tick <= releases[1].tick, level.title + ": нижнюю верёвку пересекает быстрый верхний груз")
		_check(releases.size() == 2 and releases[0].index == 0 and releases[1].index == 1 and releases[1].tick > releases[0].tick and releases[1].upper_drop > 20.0, level.title + ": падающий верхний груз запускает нижнюю ступень")


func _launch(game: GameRound, pull: Vector2) -> bool:
	if not _capture:
		return game.slingshot.launch_from_pull(pull)
	var transform := game.slingshot.get_global_transform_with_canvas()
	var end := transform * pull
	var before := game.shots_left
	_pointer(transform.origin, true)
	if _touch:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = end
		root.push_input(drag, true)
	else:
		var drag := InputEventMouseMotion.new()
		drag.position = end
		drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(drag, true)
	_pointer(end, false)
	return game.shots_left == before - 1


func _pointer(point: Vector2, pressed: bool) -> void:
	if _touch:
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


func _activate(game: GameRound) -> void:
	if not _capture:
		game.use_ability()
	elif _touch:
		var center := game.hud._ability_button.get_global_rect().get_center()
		_pointer(center, true)
		_pointer(center, false)
	else:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		event.pressed = true
		root.push_input(event, true)
		event = event.duplicate() as InputEventKey
		event.pressed = false
		root.push_input(event, true)


func _screenshot(level_id: String, phase: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/balance-%s-%s.png" % [level_id, phase]
	_check(root.get_texture().get_image().save_png(path) == OK, "Снимок баланса сохранён")


func _aim_for_remaining_target(game: GameRound, planned_shot: Array) -> Array:
	if game.slingshot.loaded_projectile.definition.id != &"homing":
		return planned_shot
	# После обвала цель может остаться в ближней будке или на дальней стороне.
	# Следопыт выбирает ближайшую собаку сам; меняется только обычный жест и момент E.
	var nearest_x := INF
	for actor in game.actors.get_children():
		if actor is DogTarget and not actor.is_destroyed:
			nearest_x = minf(nearest_x, actor.position.x)
	if game.level.title == CampaignCatalog.LEVELS[3].title and nearest_x >= 800.0 and nearest_x < 950.0:
		# Центральную цель под пролётом атакуем сверху через хрупкое стекло.
		return [-60.0, 86.0, 0.9]
	if nearest_x > 1100.0:
		# Отброшенную к краю цель достаёт более высокая дуга над обломками.
		return [-74.0, 74.0, 0.9]
	return [-85.0, 28.0, 0.15] if nearest_x < 900.0 else [-85.0, 28.0, 0.3]


func _round(level: LevelDefinition) -> GameRound:
	# Смена окна во время графической проверки может поставить предыдущую сцену на паузу.
	paused = false
	var game := MAIN.instantiate() as GameRound
	# Полная сцена и все физические тела; headless-прогону не нужна перерисовка.
	if DisplayServer.get_name() == "headless":
		game.hide()
	game.level = level
	root.add_child(game)
	current_scene = game
	return game


func _remove(game: GameRound) -> void:
	_music_playbacks.append(weakref(game.background_music.get_stream_playback()))
	game.queue_free()
	await process_frame
	await process_frame


func _music_released() -> bool:
	for playback: WeakRef in _music_playbacks:
		if playback.get_ref() != null:
			return false
	return true


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
