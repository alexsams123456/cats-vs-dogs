extends SceneTree
## Преждевременная радость: настоящий промах, поздний испуг и исход физического броска.

const DOG := preload("res://scenes/actors/dog_target.tscn")
const CAT := preload("res://scenes/actors/cat_projectile.tscn")
const BLOCK := preload("res://scenes/actors/wooden_block.tscn")
const HOUSE := preload("res://scenes/actors/dog_house.tscn")
const WEIGHT := preload("res://scenes/actors/hanging_weight.tscn")
const MAIN := preload("res://scenes/main.tscn")

var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _music_playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_capture = "--capture-gloat" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	GameLocalization.apply_locale("ru")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var was_muted := AudioServer.is_bus_mute(sfx_bus)
	AudioServer.set_bus_mute(sfx_bus, false)
	await _test_pause_and_physics_clock()
	await _test_physics_and_protection()
	await _test_voice_budget(sfx_bus)
	await _test_interruptions()
	await _test_delayed_notice()
	await _test_airborne_companion()
	await _test_round_miss_once()
	await _test_round_hit()
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		await _test_late_victory(window_size, window_size.x == 1600)
	AudioServer.set_bus_mute(sfx_bus, was_muted)
	var deadline := Time.get_ticks_msec() + 1000
	while not _music_released() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(_music_released(), "Пробные бои освободили аудиопотоки")
	print("Dog gloat checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_pause_and_physics_clock() -> void:
	var world := _world()
	var dog := _dog(world)
	var requests: Array[int] = [0]
	dog.bark_requested.connect(func() -> void: requests[0] += 1)
	dog.start_gloating()
	_check(dog.is_gloating() and dog.expression == &"gloat", "Собака сразу начинает радоваться и просит победный лай")
	await _ticks(20)
	dog.start_gloating()
	_check(requests[0] == 1, "Повторный запрос активной радости не повторяет лай")
	paused = true
	var visual_time := dog.visual_time
	var position := dog.position
	await _ticks(120)
	_check(dog.is_gloating() and dog.expression == &"gloat" and dog.visual_time == visual_time, "Пауза дольше всей сценки сохраняет радость и её позу")
	_check(dog.position == position, "Пауза сохраняет положение радующейся собаки")
	paused = false
	await _ticks(60)
	_check(dog.is_gloating(), "После паузы продолжается оставшаяся часть сценки")
	await _ticks(25)
	_check(not dog.is_gloating(), "Радость заканчивается без продления от повторного запроса")
	dog.start_gloating()
	dog.set_physics_process(false)
	await _ticks(110)
	_check(dog.is_gloating() and dog.expression == &"gloat", "Кадры отрисовки не расходуют физический таймер радости")
	dog.set_physics_process(true)
	await _ticks(105)
	_check(not dog.is_gloating(), "Физические шаги завершают сценку после возобновления")
	world.queue_free()
	await _ticks(3)


func _test_physics_and_protection() -> void:
	for kind: StringName in [&"scout", &"armored", &"jumper"]:
		var world := _world()
		var dog := _dog(world, kind, Vector2(600, 300))
		var control := _dog(world, kind, Vector2(600, 700))
		dog.linear_velocity = Vector2(45, 0)
		control.linear_velocity = dog.linear_velocity
		dog.angular_velocity = 0.25
		control.angular_velocity = dog.angular_velocity
		var collision := dog.get_node("CollisionShape2D") as CollisionShape2D
		var original_collision := collision.transform
		var original_mass := dog.mass
		var original_shield := dog.shield_active
		dog.start_gloating()
		await _ticks(40)
		_check((dog.position - control.position).is_equal_approx(Vector2(0, -400)) and dog.linear_velocity.is_equal_approx(control.linear_velocity), "Танец сохраняет настоящую траекторию: " + String(kind))
		_check(is_equal_approx(dog.rotation, control.rotation) and is_equal_approx(dog.angular_velocity, control.angular_velocity), "Танец сохраняет вращение физического тела: " + String(kind))
		_check(dog.scale == Vector2.ONE and collision.transform == original_collision and dog.mass == original_mass, "Жесты меняют рисунок без изменения коллизии и массы")
		_check(dog.shield_active == original_shield and dog.jumps_used == 0, "Радость не расходует щит или прыжки")
		world.queue_free()
		await _ticks(3)
	var world := _world()
	var house := HOUSE.instantiate() as DogHouse
	house.position = Vector2(600, 300) - house.dog_offset()
	house.freeze = true
	house.collision_layer = 0
	house.collision_mask = 0
	world.add_child(house)
	var dog := _dog(world)
	dog.enter_shelter(house)
	dog.start_gloating()
	await _ticks(10)
	_check(dog.is_gloating() and dog.is_sheltered(), "Собака может хвастаться в целой будке")
	dog.receive_hit(1000)
	_check(dog.is_gloating() and not dog.is_destroyed, "Радость сохраняет настоящую защиту будки")
	dog.leave_shelter()
	_check(not dog.is_gloating() and not dog.is_sheltered(), "Выход из будки прекращает радость")
	world.queue_free()
	await _ticks(3)


func _test_voice_budget(sfx_bus: int) -> void:
	var world := _world()
	var voices: Array[DogVoice] = []
	for index in 12:
		var dog := _dog(world, &"scout", Vector2(600 + index * 60, 300))
		voices.append(dog.get_node("Voice") as DogVoice)
		dog.start_gloating()
	_check(_total_plays(voices) == DogVoice.MAX_VOICES, "Хвастливый хор сохраняет общий лимит двух голосов")
	await _ticks(40)
	_check(_total_plays(voices) == DogVoice.MAX_VOICES, "Отклонённые победные голоса не играют с задержкой")
	world.queue_free()
	await _ticks(3)
	world = _world()
	var dog := _dog(world)
	var voice := dog.get_node("Voice") as DogVoice
	AudioServer.set_bus_mute(sfx_bus, true)
	dog.start_gloating()
	await _ticks(8)
	_check(dog.is_gloating() and dog.expression == &"gloat" and voice.play_count == 0, "Mute сохраняет визуальную радость и блокирует победный лай")
	AudioServer.set_bus_mute(sfx_bus, false)
	await _ticks(30)
	_check(voice.play_count == 0, "Включение звука не повторяет уже отклонённый лай")
	dog.stop_gloating()
	dog.start_gloating()
	_check(voice.play_count == 1 and voice.playing, "Следующая сценка использует существующий голос после mute")
	paused = true
	await _ticks(6)
	_check(voice.stream_paused, "Пауза приостанавливает победный лай")
	paused = false
	world.queue_free()
	await _ticks(3)


func _test_interruptions() -> void:
	var world := _world()
	var dog := _dog(world, &"armored")
	dog.start_gloating()
	dog.receive_hit(dog.impact_threshold - 1.0)
	_check(dog.is_gloating() and dog.shield_active, "Слабое касание не выдаётся за настоящее попадание")
	dog.apply_frost(0.3)
	_check(not dog.is_gloating() and dog.frost_time_left > 0.0, "Заморозка немедленно прерывает сценку")
	dog.start_gloating()
	_check(not dog.is_gloating(), "Замороженная собака не начинает радоваться")
	await _ticks(24)
	dog.start_gloating()
	_check(dog.is_gloating(), "Оттаявшая собака может начать новую сценку")
	dog.receive_hit(700)
	_check(not dog.is_gloating() and dog.expression == &"hit" and not dog.shield_active and not dog.is_destroyed, "Настоящее попадание прерывает радость и расходует щит")
	dog.start_gloating()
	_check(not dog.is_gloating(), "Испуганная после попадания собака не начинает хвастаться")
	await _ticks(35)
	dog.start_gloating()
	dog.destroy()
	_check(not dog.is_gloating() and dog.is_destroyed, "Уничтожение сразу прекращает радость")
	dog.start_gloating()
	_check(not dog.is_gloating(), "Поражённая собака не начинает новую сценку")
	world.queue_free()
	await _ticks(3)


func _test_delayed_notice() -> void:
	for kind: String in ["block", "weight", "cat"]:
		var world := _world()
		var dog := _dog(world, &"armored")
		var body: RigidBody2D
		if kind == "block":
			var block := BLOCK.instantiate() as WoodenBlock
			block.size = Vector2(60, 30)
			body = block
		elif kind == "weight":
			body = WEIGHT.instantiate() as HangingWeight
		else:
			var cat := CAT.instantiate() as CatProjectile
			cat.definition = CharacterCatalog.find_cat(&"classic")
			body = cat
		body.position = dog.position + Vector2(0, -145)
		body.gravity_scale = 0.0
		body.linear_damp = 0.0
		body.collision_layer = 0
		body.collision_mask = 0
		world.add_child(body)
		if body is HangingWeight:
			body.rope.receive_hit(1000)
			await _ticks(2)
		if body is CatProjectile:
			body.launch(Vector2(0, 75))
		else:
			body.linear_velocity = Vector2(0, 75)
		dog.start_gloating()
		await _ticks(20)
		_check(dog.is_gloating() and dog.expression == &"gloat", "Собака сначала не замечает приближение: " + kind)
		await _ticks(15)
		_check(not dog.is_gloating() and dog.expression == &"hit", "После победного лая собака поздно замечает опасность: " + kind)
		_check(dog.shield_active and not dog.is_destroyed, "Предчувствие опасности само не наносит урон")
		world.queue_free()
		await _ticks(3)
	var world := _world()
	var dog := _dog(world)
	var block := BLOCK.instantiate() as WoodenBlock
	block.position = dog.position + Vector2(0, -80)
	block.size = Vector2(150, 30)
	block.freeze = true
	block.collision_layer = 0
	block.collision_mask = 0
	world.add_child(block)
	dog.start_gloating()
	await _ticks(40)
	_check(dog.is_gloating(), "Неподвижная опора рядом не вызывает испуг")
	block.freeze = false
	block.gravity_scale = 0.0
	block.linear_velocity = Vector2(0, -80)
	await _ticks(12)
	_check(dog.is_gloating(), "Удаляющийся блок не прерывает радость")
	world.queue_free()
	await _ticks(3)


func _test_airborne_companion() -> void:
	var game := _game(1)
	await _ticks(8)
	var dog := _first_dog(game)
	await _shoot(game, false, Vector2(60, 10))
	var primary := _launched_cat(game)
	var companion := CAT.instantiate() as CatProjectile
	companion.definition = CharacterCatalog.find_cat(&"classic")
	companion.position = Vector2(650, 220)
	companion.gravity_scale = 0.0
	companion.linear_damp = 0.0
	companion.collision_layer = 0
	companion.collision_mask = 0
	game.actors.add_child(companion)
	companion.launch(Vector2(50, 0))
	var contacted: bool = false
	for tick in 180:
		await _ticks(1)
		if is_instance_valid(primary) and primary.has_contacted():
			contacted = true
			break
	_check(contacted, "Основной кот действительно касается земли при наличии летящего напарника")
	await _ticks(45)
	_check(game.state == GameRound.RoundState.FLYING and not companion.has_contacted() and companion.position.x < dog.position.x and not dog.is_gloating(), "Контакт основного кота не объявляет промах, пока другой кот ещё летит слева от целей")
	companion.queue_free()
	var saw_gloat := await _wait_for_gloat(game, dog)
	_check(saw_gloat, "После удаления последнего летящего напарника собака может праздновать промах")
	game.queue_free()
	await _ticks(12)


func _test_round_miss_once() -> void:
	var game := _game(2)
	await _ticks(5)
	var dog := _first_dog(game)
	var celebrations: Array[int] = [0]
	dog.bark_requested.connect(func() -> void:
		if dog.is_gloating():
			celebrations[0] += 1
	)
	await _shoot(game, false, Vector2(60, 10))
	_check(game.shots_left == 1 and game.state == GameRound.RoundState.FLYING, "Реальный жест мыши запускает первый бросок")
	await _ticks(15)
	_check(not dog.is_gloating(), "Собака не объявляет промах, пока кот ещё летит")
	var saw_gloat := await _wait_for_gloat(game, dog)
	_check(saw_gloat, "Настоящий промах после контакта с землёй запускает радость")
	for tick in 700:
		await _ticks(1)
		if game.state != GameRound.RoundState.FLYING:
			break
	_check(game.state == GameRound.RoundState.READY and celebrations[0] == 1, "Первый промах даёт одну сценку и следующего кота")
	_check(not dog.is_gloating(), "Подготовка следующего броска прекращает сценку")
	await _shoot(game, true, Vector2(60, 10))
	saw_gloat = await _wait_for_gloat(game, dog)
	_check(saw_gloat and celebrations[0] == 2, "Новый бросок может вызвать одну новую сценку")
	for tick in 700:
		await _ticks(1)
		if game.state != GameRound.RoundState.FLYING:
			break
	_check(game.state == GameRound.RoundState.LOST and celebrations[0] == 2 and not dog.is_gloating(), "Последний промах заканчивает раунд без повторного празднования")
	game.queue_free()
	await _ticks(12)


func _test_round_hit() -> void:
	var game := _game(1, &"armored")
	await _ticks(55)
	var dog := _first_dog(game)
	var hits: Array[int] = [0]
	var celebrations: Array[int] = [0]
	dog.impact_received.connect(func(_strength: float) -> void: hits[0] += 1)
	dog.bark_requested.connect(func() -> void:
		if dog.is_gloating():
			celebrations[0] += 1
	)
	await _shoot(game, false, Vector2(-80, 10))
	var cat := _launched_cat(game)
	_check(cat != null, "Бросок для проверки попадания создал настоящего кота")
	if cat != null:
		# Траектория воспроизводима; урон всё равно приходит от физического контакта.
		cat.position = dog.position + Vector2(-130, 0)
		cat.gravity_scale = 0.0
		cat.linear_velocity = Vector2(250, 0)
		cat.reset_physics_interpolation()
	for tick in 45:
		await _ticks(1)
		if hits[0] > 0:
			break
	_check(hits[0] > 0 and is_instance_valid(dog) and not dog.shield_active, "Настоящий кот снимает щит физическим попаданием")
	if is_instance_valid(cat):
		cat.queue_free()
	if is_instance_valid(dog):
		# Изолируем запрет радости после попадания от следующего отскока кота.
		dog.freeze = true
	await _ticks(65)
	_check(celebrations[0] == 0 and (not is_instance_valid(dog) or not dog.is_gloating()), "После настоящего попадания выжившая собака не празднует промах")
	game.queue_free()
	await _ticks(12)


func _test_late_victory(window_size: Vector2i, touch: bool) -> void:
	root.size = window_size
	if _capture:
		DisplayServer.window_set_size(window_size)
	var game := _game(1)
	var block := BLOCK.instantiate() as WoodenBlock
	block.size = Vector2(110, 45)
	block.material_id = &"stone"
	block.position = Vector2(950, 305)
	block.freeze = true
	game.actors.add_child(block)
	await _ticks(8)
	var dog := _first_dog(game)
	await _shoot(game, touch, Vector2(60, 10))
	_check(game.shots_left == 0 and game.state == GameRound.RoundState.FLYING, "Последний кот запущен мышью/касанием: " + str(window_size))
	var saw_gloat := await _wait_for_gloat(game, dog)
	_check(saw_gloat, "Промах последнего кота вызывает сценку: " + str(window_size))
	if saw_gloat:
		await _ticks(10)
		if _capture:
			await _save("gloat", window_size)
			if window_size.x == 1280:
				await _save_detail(game, "gloat", window_size)
		await _pause_input()
		var pose := dog.visual_time
		var before := dog.position
		await _ticks(100)
		_check(paused and dog.is_gloating() and dog.visual_time == pose and dog.position == before, "Настоящая кнопка паузы сохраняет танец: " + str(window_size))
		if _capture:
			await _save("pause", window_size)
		await _pause_input()
		_check(not paused and dog.is_gloating(), "Продолжение сохраняет остаток сценки")
	# Отпускаем тяжёлую балку: испуг не должен завершить физическую попытку.
	block.freeze = false
	block.sleeping = false
	var saw_startled: bool = false
	for tick in 90:
		await _ticks(1)
		if is_instance_valid(dog) and dog.expression == &"hit" and not dog.is_gloating():
			saw_startled = true
			break
		if game.state == GameRound.RoundState.WON:
			break
	_check(saw_startled and game.state == GameRound.RoundState.FLYING and game.dogs_left == 1, "Падающая балка вызывает запоздалый испуг до попадания: " + str(window_size))
	if _capture and saw_startled:
		await _save("startled", window_size)
		if window_size.x == 1280:
			await _save_detail(game, "startled", window_size)
	for tick in 180:
		await _ticks(1)
		if game.state in [GameRound.RoundState.WON, GameRound.RoundState.LOST]:
			break
	_check(game.state == GameRound.RoundState.WON and game.dogs_left == 0 and game.shots_left == 0, "Реальное позднее обрушение даёт победу последним котом: " + str(window_size))
	game.queue_free()
	await _ticks(12)


func _world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	return world


func _dog(world: Node2D, kind: StringName = &"scout", point: Vector2 = Vector2(600, 300)) -> DogTarget:
	var dog := DOG.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(kind)
	dog.position = point
	dog.gravity_scale = 0.0
	dog.collision_layer = 0
	dog.collision_mask = 0
	world.add_child(dog)
	# Изолируем победный лай от обычного приветствия в автономных сценариях.
	dog._idle_bark_delay_left = 1000.0
	return dog


func _game(shots: int, kind: StringName = &"scout") -> GameRound:
	var level := LevelDefinition.new()
	level.title = "Рано радуешься"
	level.shots = shots
	level.cat_sequence.resize(shots)
	level.cat_sequence.fill("classic")
	level.dog_positions = PackedVector2Array([Vector2(950, 595)])
	level.dog_kinds = PackedStringArray([String(kind)])
	var game := MAIN.instantiate() as GameRound
	game.level = level
	game.editor_preview = true
	root.add_child(game)
	_music_playbacks.append(weakref(game.background_music.get_stream_playback()))
	return game


func _first_dog(game: GameRound) -> DogTarget:
	for actor: Node in game.actors.get_children():
		if actor is DogTarget:
			return actor
	return null


func _launched_cat(game: GameRound) -> CatProjectile:
	for actor: Node in game.actors.get_children():
		if actor is CatProjectile and actor.was_launched:
			return actor
	return null


func _wait_for_gloat(game: GameRound, dog: DogTarget) -> bool:
	for tick in 240:
		await _ticks(1)
		if dog.is_gloating():
			return true
		if game.state != GameRound.RoundState.FLYING:
			break
	return false


func _shoot(game: GameRound, touch: bool, pull: Vector2) -> void:
	var transform := game.slingshot.get_global_transform_with_canvas()
	var start := transform * Vector2.ZERO
	var end := transform * pull
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


func _pause_input() -> void:
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	root.push_input(event, true)
	event = InputEventAction.new()
	event.action = &"pause"
	root.push_input(event, true)
	await _ticks(2)


func _save(label: String, window_size: Vector2i) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/dog-gloat-%s-%dx%d.png" % [label, window_size.x, window_size.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Снимок сохранён: " + label)


func _save_detail(game: GameRound, label: String, window_size: Vector2i) -> void:
	var position := game.camera.position
	var zoom := game.camera.zoom
	game.camera.position = Vector2(950, 510)
	game.camera.zoom = Vector2(2, 2)
	game.camera.force_update_scroll()
	await _save(label + "-detail", window_size)
	game.camera.position = position
	game.camera.zoom = zoom
	game.camera.force_update_scroll()


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _total_plays(voices: Array[DogVoice]) -> int:
	var total: int = 0
	for voice in voices:
		total += voice.play_count
	return total


func _music_released() -> bool:
	for playback in _music_playbacks:
		if playback.get_ref() != null:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
