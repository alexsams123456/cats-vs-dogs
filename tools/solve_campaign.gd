extends SceneTree
## Воспроизводимые прохождения рогаткой. Никаких подмен скорости, целей или столкновений.
## tools/check.ps1 использует --fixed-fps 60 без привязки к реальному времени.
## Один кадр на физический тик сохраняет порядок отложенных разрушений и запусков.

const MAIN := preload("res://scenes/main.tscn")
## Для каждого выстрела: натяжение x/y в мировых пикселях, время попытки способности.
## -1 означает бросок без ручной активации; автоматические способности работают как в игре.
## Если кот уже столкнулся с постройкой, недоступная способность не заменяет обычный удар.
const ROUTES := {
	# Earlier dash targets the far pavilion directly, before the cat turns down
	# toward the ground. A later dash relied on an incidental rubble ricochet.
	"01_first_throw": [[-82.22, 36.61, -1.0], [-99.86, 32.45, 0.35]],
	"02_air_trick": [[-85.6, 27.81, 0.75], [-74.25, 74.25, 0.7]],
	"03_little_shelter": [[-70.26, 78.03, -1.0], [-78.03, 70.26, -1.0], [-90.93, 52.5, 0.65]],
	"04_glass_bridge": [[-99.86, 32.45, -1.0], [-78.03, 70.26, -1.0], [-95.92, 42.71, 0.65], [-90.93, 52.5, 0.65], [-90.93, 52.5, 0.65]],
	"05_restless_yard": [[-72.81, 52.9, 0.4], [-72.81, 52.9, -1.0], [-95.92, 42.71, -1.0], [-78.03, 70.26, -1.0], [-99.86, 32.45, 0.6], [-84.95, 61.72, -1.0]],
	"06_last_fort": [[-99.86, 32.45, -1.0], [-52.9, 72.81, 0.6], [-99.86, 32.45, -1.0], [-84.95, 61.72, 0.65], [-99.86, 32.45, 0.4], [-90.93, 52.5, 0.55], [-90.93, 52.5, 0.65], [-90.93, 52.5, 0.65]],
}

var _checks: int = 0
var _failures: int = 0
var _music_playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 120
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX"), true)
	for level_id: String in ROUTES:
		var level := load("res://levels/campaign/%s.tres" % level_id) as LevelDefinition
		await _check_stability(level)
		for attempt in 2:
			await _replay(level_id, level, ROUTES[level_id], attempt)
			if level_id == "04_glass_bridge" and attempt == 0:
				# После обрушения переиспользованные RID меняют порядок контактов новой постройки.
				await _check_stability(level)
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
			bodies.append({"body": weakref(actor), "hits": actor.hits_left, "position": actor.position})
	for tick in 600:
		await physics_frame
	_check(game.dogs_left == level.dog_positions.size(), level.title + ": все собаки переживают 10 s ожидания")
	for record in bodies:
		var body := (record["body"] as WeakRef).get_ref() as WoodenBlock
		var intact: bool = is_instance_valid(body) and not body.is_destroyed and body.hits_left == record["hits"]
		_check(intact, level.title + ": строение не получает урон до первого выстрела")
		if intact:
			# Малые зубцы могут усесться на несколько пикселей шире несущих балок.
			var settle_margin: float = 16.0 if body.size.x * body.size.y < 1600.0 else 8.0
			_check(body.position.distance_to(record["position"]) < settle_margin, level.title + ": элементы сохраняют исходную опору")
			_check(body.linear_velocity.length() < 16.0, level.title + ": элементы успокаиваются до первого выстрела")
	await _remove(game)


func _replay(level_id: String, level: LevelDefinition, route: Array, attempt: int) -> void:
	var game := _round(level)
	for tick in 66:
		await physics_frame
	var used := 0
	for planned_shot: Array in route:
		if game.state == GameRound.RoundState.WON:
			break
		_check(game.state == GameRound.RoundState.READY, level.title + ": следующий кот готов")
		if game.state != GameRound.RoundState.READY:
			break
		var shot := _aim_for_remaining_target(game, planned_shot)
		_check(game.slingshot.launch_from_pull(Vector2(shot[0], shot[1])), level.title + ": настоящий запуск из рогатки")
		used += 1
		var activated := false
		for tick in 1800:
			await physics_frame
			if game.state != GameRound.RoundState.FLYING:
				break
			if not activated and shot[2] >= 0.0 and game._flight_time + 0.0001 >= shot[2]:
				var cat := game._active_cat
				var available := is_instance_valid(cat) and cat.can_activate_ability()
				activated = true
				if available:
					game.use_ability()
					_check(is_instance_valid(cat) and cat.ability_spent, level.title + ": доступная способность действительно сработала")
				else:
					_check(level.tutorial != &"ability" and (not is_instance_valid(cat) or cat._has_contacted or cat.ability_spent), level.title + ": раннее столкновение оставляет обычный бросок")
	_check(game.state == GameRound.RoundState.WON, level.title + ": маршрут побеждает")
	if game.state != GameRound.RoundState.WON:
		for actor in game.actors.get_children():
			if actor is DogTarget and not actor.is_destroyed:
				print("Remaining ", level_id, " target=", actor.position, " shelter_hp=", actor.shelter.hits_left if actor.is_sheltered() else 0)
	_check(used <= level.par_shots, level.title + ": маршрут укладывается в три звезды")
	print("Route ", level_id, " attempt=", attempt + 1, " shots=", used, " won=", game.state == GameRound.RoundState.WON)
	await _remove(game)


func _aim_for_remaining_target(game: GameRound, planned_shot: Array) -> Array:
	if game.slingshot.loaded_projectile.definition.id != &"homing":
		return planned_shot
	# После обвала цель может остаться в ближней будке или на дальней стороне.
	# Следопыт выбирает ближайшую собаку сам; меняется только обычный жест и момент E.
	var nearest_x := INF
	for actor in game.actors.get_children():
		if actor is DogTarget and not actor.is_destroyed:
			nearest_x = minf(nearest_x, actor.position.x)
	return [-99.86, 32.45, 0.15] if nearest_x < 900.0 else [-90.93, 52.5, 0.65]


func _round(level: LevelDefinition) -> GameRound:
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
