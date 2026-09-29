extends SceneTree
## Солнце читает игру, но не меняет ввод, физику, счётчики и общий RNG.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const APP_SCENE := preload("res://scenes/app.tscn")
const BACKDROP := preload("res://scripts/world/backdrop.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	AudioServer.set_bus_mute(0, true)
	_test_face()
	for touch: bool in [false, true]:
		await _test_round(touch)
	await _test_loss_and_restart()
	await _test_environments()
	await create_timer(0.3).timeout
	print("Sun observer checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_face() -> void:
	var face := SunFace.new()
	root.add_child(face)
	face.focus_on(Vector2(-700, 400))
	face.advance(0.5)
	_check(face.gaze.x < -0.1 and face.gaze.y > 0.1, "Зрачки поворачиваются к объекту слева и ниже солнца")
	var before := face.gaze
	face.focus_on(Vector2(700, -400))
	_check(face.gaze.is_equal_approx(before), "Смена цели не перескакивает через плавное движение глаз")
	face.advance(0.5)
	_check(face.gaze.x > 0.1 and face.gaze.y < -0.1 and face.gaze.length() <= 1.001, "Взгляд меняет направление и остаётся в пределах глаз")
	face.set_mood(&"focused")
	face.react(&"surprised", 0.4)
	_check(face.emotion == &"surprised", "Событие временно меняет выражение лица")
	face.advance(0.6)
	_check(face.emotion == &"focused", "Временная эмоция возвращается к текущему настроению")
	face.react(&"delighted", 1.0)
	face.reset()
	_check(face.emotion == &"happy" and face.mood == &"happy", "Сброс очищает прошлую эмоцию")
	_check(_only_visual(face), "Лицо не принимает ввод и не содержит физических узлов")
	face.free()


func _test_round(touch: bool) -> void:
	var game := await _new_game()
	var face := _face(game)
	var label := "касание" if touch else "мышь"
	_check(face.emotion == &"happy", "Солнце улыбается в начале: " + label)
	var shots := game.shots_left
	var transform := game.slingshot.get_global_transform_with_canvas()
	var anchor := transform.origin
	var pulled := transform * Vector2(-70, 30)
	_pointer(anchor, true, touch)
	_drag(pulled, touch)
	await _settle()
	_check(game.slingshot.is_dragging and face.mood == &"focused", "Солнце сосредоточено при настоящем натяжении: " + label)
	_check(face.gaze.x < 0.0 and face.gaze.y > 0.0, "Во время прицеливания солнце смотрит на кота")
	_pointer(pulled if touch else anchor, false, touch, touch)
	await _settle()
	_check(game.shots_left == shots and game.state == GameRound.RoundState.READY, "Отмена жеста сохраняет выстрел: " + label)
	_check(face.mood == &"happy", "Отмена прицеливания возвращает улыбку: " + label)
	_pointer(anchor, true, touch)
	_drag(pulled, touch)
	var cat := game.slingshot.loaded_projectile
	_pointer(pulled, false, touch)
	_check(cat.was_launched and game.shots_left == shots - 1, "Наблюдатель не дублирует запуск: " + label)
	_check(cat.linear_velocity.distance_to(Vector2(70, -30) * game.slingshot.launch_speed) < 0.1, "Выражение солнца не меняет скорость запуска")
	await _settle()
	_check(face.mood == &"focused", "Солнце следит за полётом")
	_test_isolation(game, cat, face)
	await _test_pause(game, face)
	var deadline := Time.get_ticks_msec() + 4000
	while is_instance_valid(cat) and not cat.has_contacted() and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	_check(is_instance_valid(cat) and cat.has_contacted(), "Кот действительно столкнулся с землёй")
	_check(face.emotion == &"surprised", "Физическое столкновение удивляет солнце: " + label)
	game._finish_shot()
	await _settle()
	_check(face.emotion == &"happy" and game.state == GameRound.RoundState.READY, "Новый кот очищает реакцию на прошлый бросок")
	_check(game.slingshot.launch_from_pull(Vector2(-70, 30)), "Следующий бросок запускается штатной рогаткой")
	await _settle()
	var dogs := _dogs(game)
	dogs[0].receive_hit(900.0)
	await _settle()
	_check(game.dogs_left == 1 and face.emotion == &"delighted", "Поражение одной цели радует солнце и сохраняет раунд")
	dogs[1].receive_hit(900.0)
	await _settle()
	_check(game.state == GameRound.RoundState.WON and face.mood == &"delighted", "Последняя поражённая цель вызывает устойчивую радость победы")
	face.advance(3.0)
	_check(face.emotion == &"delighted", "Радость победы не заканчивается вместе с короткой реакцией")
	await _dispose(game)


func _test_isolation(game: GameRound, cat: CatProjectile, face: SunFace) -> void:
	var position := cat.global_position
	var velocity := cat.linear_velocity
	var angular_velocity := cat.angular_velocity
	var shots := game.shots_left
	var targets := game.dogs_left
	seed(498012)
	var expected := PackedInt64Array([randi(), randi(), randi()])
	seed(498012)
	for index in 20:
		face.focus_on(Vector2(float(index) * 80.0, 480.0))
		face.react(&"surprised", 0.2)
		face.advance(0.1)
	_check(PackedInt64Array([randi(), randi(), randi()]) == expected, "Мимика не расходует общий игровой генератор случайных чисел")
	_check(cat.global_position == position and cat.linear_velocity == velocity and cat.angular_velocity == angular_velocity, "Многократная анимация не меняет физическое тело кота")
	_check(game.shots_left == shots and game.dogs_left == targets, "Анимация не меняет счётчики раунда")
	face.advance(1.0)


func _test_pause(game: GameRound, face: SunFace) -> void:
	game.set_paused(true)
	var frozen := [face.animation_time, face.gaze, face.emotion]
	await create_timer(0.08, true).timeout
	_check([face.animation_time, face.gaze, face.emotion] == frozen, "Пауза останавливает время, взгляд и мимику солнца")
	game.set_paused(false)
	await create_timer(0.05).timeout
	_check(face.animation_time > float(frozen[0]), "После паузы наблюдение возобновляется")


func _test_loss_and_restart() -> void:
	var app := APP_SCENE.instantiate() as GameApp
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _settle()
	var level := _level()
	level.shots = 1
	app.start_editor_game(level)
	await _settle()
	var game := app.game
	game.set_paused(false)
	var face := _face(game)
	game.slingshot.launch_from_pull(Vector2(-70, 30))
	game._finish_shot()
	await _settle()
	_check(game.state == GameRound.RoundState.LOST and face.emotion == &"sad", "Исчерпание котов вызывает сочувствующую грусть")
	face.advance(3.0)
	_check(face.emotion == &"sad", "Поражение сохраняет настроение после истечения коротких реакций")
	var old_face: WeakRef = weakref(face)
	game.restart()
	await _settle()
	_check(old_face.get_ref() == null, "Перезапуск освобождает прежнее солнце и его реакции")
	_check(app.game.state == GameRound.RoundState.READY and _face(app.game).emotion == &"happy", "Новая попытка начинает с улыбки")
	app.game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	face = _face(app.game)
	var clock := face.animation_time
	await create_timer(0.08, true).timeout
	_check(paused and is_equal_approx(face.animation_time, clock), "Потеря фокуса останавливает солнце вместе с игрой")
	paused = false
	app.queue_free()
	await _settle()


func _test_environments() -> void:
	for biome: StringName in LevelDefinition.BIOMES:
		var backdrop := BACKDROP.new()
		backdrop.set_biome(biome)
		root.add_child(backdrop)
		var face := (backdrop.get_node("AmbientLife") as AmbientLife).sun_face
		_check(face.visible == (biome != &"glacier"), "Лицо есть только у солнца; ледниковая луна сохранена: " + String(biome))
		_check(_only_visual(face), "Фон не перехватывает игровое управление: " + String(biome))
		backdrop.queue_free()
		await _settle()
		var canvas := LevelCanvas.new()
		canvas.size = Vector2(960, 720)
		canvas.draft = _level()
		canvas.draft.biome = String(biome)
		root.add_child(canvas)
		face = (canvas._backdrop.get_node("AmbientLife") as AmbientLife).sun_face
		var frozen := [face.animation_time, face.gaze, face.emotion]
		await create_timer(0.05).timeout
		_check([face.animation_time, face.gaze, face.emotion] == frozen, "Солнце редактора остаётся неподвижным: " + String(biome))
		canvas.queue_free()
		await _settle()


func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.shots = 3
	level.dog_positions = PackedVector2Array([Vector2(860, 595), Vector2(1070, 595)])
	return level


func _new_game() -> GameRound:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = _level()
	root.add_child(game)
	current_scene = game
	await _settle()
	return game


func _face(game: GameRound) -> SunFace:
	return (game.get_node("Backdrop/AmbientLife") as AmbientLife).sun_face


func _dogs(game: GameRound) -> Array[DogTarget]:
	var result: Array[DogTarget] = []
	for actor in game.actors.get_children():
		if actor is DogTarget:
			result.append(actor)
	return result


func _only_visual(node: Node) -> bool:
	if node is CollisionObject2D or node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input():
		return false
	for child in node.get_children():
		if not _only_visual(child):
			return false
	return true


func _dispose(game: GameRound) -> void:
	paused = false
	game.queue_free()
	await _settle()


func _settle() -> void:
	for frame in 4:
		await process_frame


func _pointer(point: Vector2, pressed: bool, touch: bool, canceled: bool = false) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 4
		event.pressed = pressed
		event.canceled = canceled
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
		event.index = 4
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
