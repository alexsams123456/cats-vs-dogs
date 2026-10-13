extends SceneTree
## Реальное движение, ограничения патруля и завершение последнего броска.

const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const GAME_SCENE := preload("res://scenes/main.tscn")
const MOVING_KINDS: Array[StringName] = [&"jumper", &"rover", &"runner"]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_motion()
	await _test_varied_motion()
	for kind in MOVING_KINDS:
		await _test_obstacles(false, kind)
		await _test_obstacles(true, kind)
		await _test_platform(kind)
		await _test_shelter_and_impact(kind)
		await _test_round(kind)
	await _test_campaign_motion()
	if "--capture-patrol" in OS.get_cmdline_user_args():
		await _capture_input()
	await create_timer(0.3).timeout
	# Fixed-fps headless time outruns the audio mixer; let its fade finish.
	OS.delay_msec(150)
	print("Dog patrol checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_motion() -> void:
	var world := Node2D.new()
	root.add_child(world)
	_floor(world, Vector2(800, 640), Vector2(1000, 40))
	var dog := _dog(world, &"jumper", Vector2(750, 595))
	var scout := _dog(world, &"scout", Vector2(950, 595))
	var armored := _dog(world, &"armored", Vector2(1100, 595))
	var disabled := _dog(world, &"jumper", Vector2(550, 595), 0.0)
	var minimum_x := dog.position.x
	var maximum_x := dog.position.x
	var saw_left: bool = false
	var saw_right: bool = false
	for tick in 420:
		await physics_frame
		if not is_instance_valid(dog):
			break
		minimum_x = minf(minimum_x, dog.position.x)
		maximum_x = maxf(maximum_x, dog.position.x)
		saw_left = saw_left or dog.linear_velocity.x < -25.0
		saw_right = saw_right or dog.linear_velocity.x > 25.0
	_check(is_instance_valid(dog) and not dog.is_destroyed, "Ходьба не поражает собственную собаку")
	_check(saw_left and saw_right and maximum_x - minimum_x > 70.0, "Шустрик физически ходит в обе стороны")
	_check(minimum_x >= 695.0 and maximum_x <= 805.0, "Патруль остаётся около исходной позиции")
	_check(absf(dog.rotation) < 0.2, "Шустрик сохраняет вертикальную позу при ходьбе")
	_check(absf(scout.position.x - 950.0) < 2.0 and absf(armored.position.x - 1100.0) < 2.0, "Остальные виды не патрулируют")
	_check(absf(disabled.position.x - 550.0) < 2.0, "Нулевой радиус отключает патруль")
	if is_instance_valid(dog):
		var before := dog.position
		paused = true
		await create_timer(0.2, true).timeout
		_check(dog.position.is_equal_approx(before), "Пауза останавливает физическое движение")
		paused = false
		dog.apply_frost(0.65)
		before = dog.position
		await create_timer(0.4).timeout
		_check(dog.position.is_equal_approx(before) and dog.freeze, "Заморозка останавливает патруль")
		await create_timer(0.8).timeout
		_check(not dog.freeze and dog.position.distance_to(before) > 5.0, "После оттаивания патруль возобновляется")
		dog.apply_central_impulse(Vector2(0, -150))
		await create_timer(0.12).timeout
		_check(dog.linear_velocity.y < -20.0 and not dog.is_patrol_motion(), "Внешний толчок не считается спокойной ходьбой")
	world.queue_free()
	await _settle()


func _test_varied_motion() -> void:
	var world := Node2D.new()
	root.add_child(world)
	_floor(world, Vector2(800, 640), Vector2(1600, 40))
	var rover := _dog(world, &"rover", Vector2(550, 595))
	var runner := _dog(world, &"runner", Vector2(1050, 595))
	var rover_min: float = 550.0
	var rover_max: float = 550.0
	var runner_min: float = 1050.0
	var runner_max: float = 1050.0
	var rover_speed: float = 0.0
	var runner_speed: float = 0.0
	var stop_ticks: int = 0
	var longest_stop: int = 0
	var rest_count: int = 0
	for tick in 480:
		await physics_frame
		rover_min = minf(rover_min, rover.position.x)
		rover_max = maxf(rover_max, rover.position.x)
		runner_min = minf(runner_min, runner.position.x)
		runner_max = maxf(runner_max, runner.position.x)
		rover_speed = maxf(rover_speed, absf(rover.linear_velocity.x))
		runner_speed = maxf(runner_speed, absf(runner.linear_velocity.x))
		if tick > 60:
			if absf(runner.linear_velocity.x) < 1.0:
				stop_ticks += 1
				longest_stop = maxi(longest_stop, stop_ticks)
			else:
				if stop_ticks >= 20:
					rest_count += 1
				stop_ticks = 0
	_check(not rover.is_destroyed and not runner.is_destroyed, "Новые виды не поражаются от собственной ходьбы")
	_check(rover_max - rover_min > 55.0 and runner_max - runner_min > 85.0, "Оба новых вида физически ходят в обе стороны")
	_check(rover_min >= 508.0 and rover_max <= 592.0 and runner_min >= 988.0 and runner_max <= 1112.0, "Каждый вид сохраняет свой диапазон движения")
	_check(rover_speed > 25.0 and runner_speed > rover_speed * 2.0, "Рывок заметно быстрее Дозора")
	_check(longest_stop >= 30 and rest_count >= 2, "Рывок несколько раз отдыхает и снова начинает бежать")
	_check(rover.jumps_used == 0 and runner.jumps_used == 0, "Движение новых видов не тратит прыжки Шустрика")
	var before := [rover.position, runner.position]
	paused = true
	await create_timer(0.2, true).timeout
	_check(rover.position == before[0] and runner.position == before[1], "Пауза останавливает оба новых вида")
	paused = false
	for dog in [rover, runner]:
		dog.apply_frost(0.65)
	before = [rover.position, runner.position]
	await create_timer(0.4).timeout
	_check(rover.position == before[0] and runner.position == before[1], "Заморозка останавливает оба новых вида")
	await create_timer(1.8).timeout
	_check(not rover.freeze and not runner.freeze and rover.position.distance_to(before[0]) > 5.0 and runner.position.distance_to(before[1]) > 5.0, "Оба новых вида возобновляют ходьбу после оттаивания")
	world.queue_free()
	await _settle()


func _test_obstacles(edge: bool, kind: StringName) -> void:
	var world := Node2D.new()
	root.add_child(world)
	_floor(world, Vector2(800, 640), Vector2(100 if edge else 1000, 40))
	if not edge:
		_floor(world, Vector2(742, 575), Vector2(20, 90))
	var dog := _dog(world, kind, Vector2(800, 595))
	var minimum_x: float = 800.0
	var maximum_x: float = 800.0
	for tick in 360:
		await physics_frame
		if not is_instance_valid(dog):
			break
		minimum_x = minf(minimum_x, dog.position.x)
		maximum_x = maxf(maximum_x, dog.position.x)
	_check(is_instance_valid(dog) and absf(dog.position.y - 595.0) < 4.0, "Патруль не падает и не разрушает себя: " + ("край" if edge else "стена"))
	_check(minimum_x > (760.0 if edge else 780.0) and maximum_x < (840.0 if edge else 800.0 + dog._patrol_distance() + 8.0), "Разворот перед краем/препятствием: " + String(kind))
	_check(maximum_x - minimum_x > 15.0, "Препятствие не блокирует движение в свободную сторону")
	world.queue_free()
	await _settle()


func _test_platform(kind: StringName) -> void:
	var world := Node2D.new()
	root.add_child(world)
	_floor(world, Vector2(800, 640), Vector2(1000, 40))
	var platform := load("res://scenes/actors/wooden_block.tscn").instantiate() as WoodenBlock
	platform.size = Vector2(200, 20)
	platform.position = Vector2(800, 520)
	platform.freeze = true
	world.add_child(platform)
	var dog := _dog(world, kind, Vector2(800, 485))
	await create_timer(2.0).timeout
	_check(absf(dog.position.x - 800.0) < 2.0 and not dog.is_patrol_motion(), "На отдельном перекрытии нет ходьбы: " + String(kind))
	world.queue_free()
	await _settle()


func _test_shelter_and_impact(kind: StringName) -> void:
	var world := Node2D.new()
	root.add_child(world)
	_floor(world, Vector2(800, 640), Vector2(1000, 40))
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.position = Vector2(800, 558)
	house.freeze = true
	world.add_child(house)
	var dog := _dog(world, kind, Vector2(800, 595))
	dog.enter_shelter(house)
	var before := dog.position
	await create_timer(1.8).timeout
	_check(dog.position.is_equal_approx(before) and not dog.is_patrol_motion(), "Собака в конуре не ходит")
	house.destroy()
	await create_timer(1.6).timeout
	_check(is_instance_valid(dog) and not dog.is_sheltered() and absf(dog.position.x - before.x) > 5.0, "Освобождённая собака начинает ходить: " + String(kind))
	# Disable only evasion to isolate real collision damage to a walking target.
	dog.jumps_used = DogTarget.MAX_JUMPS
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.find_cat(&"classic")
	cat.position = dog.position + Vector2(-150, 0)
	cat.gravity_scale = 0.0
	world.add_child(cat)
	cat.launch(Vector2(600, 0))
	await create_timer(0.5).timeout
	_check(not is_instance_valid(dog), "Настоящее попадание сбивает движущуюся цель")
	world.queue_free()
	await _settle()


func _test_round(kind: StringName) -> void:
	var level := LevelDefinition.new()
	level.shots = 1
	level.dog_positions = PackedVector2Array([Vector2(1000, 595)])
	level.dog_kinds = PackedStringArray([String(kind)])
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = level
	root.add_child(game)
	current_scene = game
	await create_timer(1.3).timeout
	game.slingshot.launch_from_pull(Vector2(80, 15))
	for tick in 900:
		await physics_frame
		if game.state != GameRound.RoundState.FLYING:
			break
	_check(game.state == GameRound.RoundState.LOST, "Промах последнего кота завершает раунд при живом патруле")
	var dog := game.actors.get_child(0) as DogTarget
	_check(dog != null and not dog.patrol_enabled, "После результата самостоятельная ходьба прекращается")
	game.background_music.stop()
	game.queue_free()
	await _settle()


func _test_campaign_motion() -> void:
	var moving_levels: int = 0
	var seen_kinds: Array[StringName] = []
	for level in CampaignCatalog.LEVELS:
		var has_motion: bool = false
		for kind in level.dog_kinds:
			if StringName(kind) in MOVING_KINDS:
				has_motion = true
				if not StringName(kind) in seen_kinds:
					seen_kinds.append(StringName(kind))
		if has_motion:
			moving_levels += 1
	_check(seen_kinds.size() == 3 and moving_levels > 3 and moving_levels < CampaignCatalog.LEVELS.size(), "Все три вида встречаются в кампании с промежутками")
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = CampaignCatalog.LEVELS[0]
	root.add_child(game)
	current_scene = game
	var dog: DogTarget
	for actor in game.actors.get_children():
		if actor is DogTarget and actor.definition.id == &"rover":
			dog = actor
	_check(dog != null, "Первый уровень содержит Дозора")
	if dog == null:
		game.queue_free()
		await _settle()
		return
	var minimum_x := dog.position.x
	var maximum_x := dog.position.x
	for tick in 360:
		await physics_frame
		minimum_x = minf(minimum_x, dog.position.x)
		maximum_x = maxf(maximum_x, dog.position.x)
	_check(dog.definition.id == &"rover" and maximum_x - minimum_x > 25.0, "Дозор заметно ходит уже в первом уровне")
	_check(game.state == GameRound.RoundState.READY and game.dogs_left == 2, "Ожидание в первом уровне не поражает цели")
	game.queue_free()
	await _settle()


func _capture_input() -> void:
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	for size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = size
		for touch in [false, true]:
			await _capture_round(size, touch, "01_first_throw")
			await _capture_round(size, touch, "16_frozen_patrol")


func _capture_round(size: Vector2i, touch: bool, level_id: String) -> void:
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = load("res://levels/campaign/%s.tres" % level_id)
	root.add_child(game)
	current_scene = game
	# Window switches during capture may trigger the game's focus pause.
	root.grab_focus()
	game.set_paused(false)
	await create_timer(1.4).timeout
	await _save(level_id + "-walking", size, touch)
	await create_timer(0.5).timeout
	await _save(level_id + "-later", size, touch)
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	for pressed in [true, false]:
		var point := anchor if pressed else anchor + Vector2(-85, 36)
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
	_check(game.state == GameRound.RoundState.FLYING, "Бросок в подвижном дворе: %s, %s, %s" % [level_id, size, "касание" if touch else "мышь"])
	await create_timer(0.8).timeout
	await _save(level_id + "-flight", size, touch)
	game.set_paused(true)
	var positions: Array[Vector2] = []
	for actor in game.actors.get_children():
		if actor is DogTarget:
			positions.append(actor.position)
	await create_timer(0.25, true).timeout
	var index: int = 0
	for actor in game.actors.get_children():
		if actor is DogTarget:
			_check(actor.position.is_equal_approx(positions[index]), "Пауза двора удерживает собаку")
			index += 1
	await _save(level_id + "-pause", size, touch)
	game.set_paused(false)
	game.queue_free()
	await _settle()


func _save(label: String, size: Vector2i, touch: bool) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/dog-patrol-%s-%dx%d-%s.png" % [label, size.x, size.y, "touch" if touch else "mouse"]
	_check(root.get_texture().get_image().save_png(path) == OK, "Снимок сохранён: " + label)


func _floor(world: Node, point: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = point
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)


func _dog(world: Node, kind: StringName, point: Vector2, distance: float = 48.0) -> DogTarget:
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(kind)
	dog.position = point
	dog.patrol_distance = distance
	world.add_child(dog)
	return dog


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
