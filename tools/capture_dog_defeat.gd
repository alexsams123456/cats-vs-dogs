extends SceneTree
## Графическая проверка поражения собак; пригодна для --write-movie --fixed-fps 30.

const APP_SCENE := preload("res://scenes/app.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const PHASE_TIMES: Array[float] = [0.08, 0.30, 0.55, 0.85]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для снимков поражения собак нужен графический запуск без --headless.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute("res://.artifacts") != OK:
		push_error("Не удалось создать папку .artifacts.")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var app := APP_SCENE.instantiate() as GameApp
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	await create_timer(0.2).timeout
	for kind: StringName in [&"scout", &"armored", &"jumper"]:
		await _capture_kind(app, kind, kind == &"armored", kind == &"scout", false)
	for width: int in [1600, 960]:
		root.size = Vector2i(width, 720)
		await _capture_kind(app, &"scout", width == 960, false, width == 960)
	paused = false
	app.queue_free()
	await process_frame
	print("Dog defeat previews: %d passed, %d failed. Images: .artifacts/defeat-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _capture_kind(app: GameApp, kind: StringName, touch: bool, check_pause: bool, check_restart: bool) -> void:
	app.selected_cat_id = &"classic"
	app.selected_dog_id = kind
	app.start_editor_game(_demo_level())
	await process_frame
	await process_frame
	var game := app.game
	if not _verify(is_instance_valid(game), "Открылся бой: " + kind):
		return
	game.set_paused(false)
	await create_timer(0.85).timeout
	game.set_paused(false)
	var dog := _first_dog(game)
	var cat := game.slingshot.loaded_projectile
	if not _verify(is_instance_valid(dog) and is_instance_valid(cat), "В бою есть цель и кот: " + kind):
		return
	await _save_image("%s-ready" % kind)
	var shots := game.shots_left
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_pointer(anchor, true, touch)
	_pointer(anchor + Vector2(-95, 20), false, touch)
	if not _verify(cat.was_launched and game.shots_left == shots - 1, "%s: %s запускает одного кота" % [kind, "касание" if touch else "мышь"]):
		return
	# После настоящего жеста задаём воспроизводимую траекторию столкновения.
	# Это проверка ввода и физического попадания, а не баланса прицеливания.
	cat.position = dog.position + Vector2(-140, 0)
	cat.gravity_scale = 0.0
	cat.linear_velocity = Vector2(620 if kind == &"armored" else 1600, 0)
	cat.angular_velocity = 0.0
	if kind == &"armored":
		var shield_timeout := create_timer(1.0)
		while is_instance_valid(dog) and dog.shield_active and shield_timeout.time_left > 0.0:
			await process_frame
		if not _verify(is_instance_valid(dog) and not dog.is_destroyed and not dog.shield_active, "Первое физическое попадание снимает только щит"):
			return
		_verify(_find_effect(game) == null and game.dogs_left == 2, "Снятие щита не запускает поражение")
		cat.queue_free()
		await _save_image("armored-shield")
		await create_timer(0.32).timeout
		if not _verify(is_instance_valid(dog) and not dog.is_destroyed, "Бульдог пережил снятие щита"):
			return
		cat = CAT_SCENE.instantiate() as CatProjectile
		cat.definition = game.cat_definition
		cat.position = dog.position + Vector2(110, 0)
		cat.gravity_scale = 0.0
		game.actors.add_child(cat)
		cat.launch(Vector2(-1600, 0))
	var effect := await _wait_effect(game)
	if not _verify(is_instance_valid(effect), "Физическое попадание создаёт эффект: " + kind):
		return
	if is_instance_valid(cat):
		cat.queue_free()
	_verify(not is_instance_valid(dog) or dog.is_destroyed, "Модель поражённой собаки удаляется: " + kind)
	_verify(game.dogs_left == 1, "Счётчик целей уменьшается сразу: " + kind)
	for phase_time: float in PHASE_TIMES:
		var phase_timeout := create_timer(1.0, true)
		while is_instance_valid(effect) and effect.elapsed < phase_time and phase_timeout.time_left > 0.0:
			await process_frame
		if not _verify(is_instance_valid(effect) and effect.elapsed >= phase_time, "%s: эффект достиг фазы %.2f с" % [kind, phase_time]):
			return
		await _save_image("%s-%03dms" % [kind, roundi(phase_time * 1000.0)])
		if check_pause and is_equal_approx(phase_time, 0.30):
			game.set_paused(true)
			var paused_time: float = effect.elapsed
			await _save_image("scout-paused")
			await create_timer(0.35, true).timeout
			_verify(paused and is_equal_approx(effect.elapsed, paused_time), "Пауза останавливает анимацию поражения")
			game.set_paused(false)
			await process_frame
			await process_frame
			_verify(effect.elapsed > paused_time, "Продолжение возобновляет анимацию поражения")
	if check_restart:
		_verify(is_instance_valid(effect), "Перед перезапуском эффект ещё виден")
		var old_game_id := game.get_instance_id()
		_restart_key()
		await process_frame
		await process_frame
		_verify(not is_instance_valid(effect), "Перезапуск удаляет незавершённый эффект")
		_verify(is_instance_valid(app.game) and app.game.get_instance_id() != old_game_id and _find_effect(app.game) == null, "Новый раунд начинается без старых эффектов")
		await _save_image("scout-restarted")
	else:
		await create_timer(0.4).timeout
		_verify(not is_instance_valid(effect), "Эффект удаляется после завершения: " + kind)


func _demo_level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.title = "Последний кульбит"
	level.shots = 4
	# Вторая цель сохраняет активный раунд для проверки паузы.
	level.dog_positions = PackedVector2Array([Vector2(790, 595), Vector2(1180, 595)])
	return level


func _first_dog(game: GameRound) -> DogTarget:
	for actor in game.actors.get_children():
		if actor is DogTarget:
			return actor as DogTarget
	return null


func _find_effect(game: GameRound) -> HeroHitEcho:
	for actor in game.actors.get_children():
		if actor is HeroHitEcho:
			return actor as HeroHitEcho
	return null


func _wait_effect(game: GameRound) -> HeroHitEcho:
	var timeout := create_timer(1.0)
	while timeout.time_left > 0.0:
		var effect := _find_effect(game)
		if effect != null:
			return effect
		await process_frame
	return null


func _save_image(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := "res://.artifacts/defeat-%s-%dx%d.png" % [stage, root.size.x, root.size.y]
	_verify(picture.save_png(path) == OK, "Сохранён снимок " + path)


func _pointer(position: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)


func _restart_key() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_R
		event.pressed = pressed
		root.push_input(event, true)


func _verify(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
	return condition
