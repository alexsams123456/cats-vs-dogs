extends SceneTree
## Physical effects, activation boundaries and cleanup for the ten cat abilities.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const BLOCK_SCENE := preload("res://scenes/actors/wooden_block.tscn")
const ACTIVE_IDS: Array[StringName] = [
	&"classic", &"bomb", &"splitter", &"heavy", &"wind", &"magnet", &"frost", &"ghost", &"homing",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# These checks concern physics; voice playback is covered by the audio suites.
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX"), true)
	await _test_activation_gates()
	await _test_contact_lock()
	await _test_dash_and_dive()
	await _test_blast_coverage()
	await _test_splitter_round()
	await _test_wind()
	await _test_magnet()
	await _test_frost()
	await _test_frozen_impacts()
	await _test_frozen_round_settling()
	await _test_ghost()
	await _test_ghost_expiry_inside_block()
	await _test_homing()
	print("Cat ability checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_activation_gates() -> void:
	for id: StringName in ACTIVE_IDS:
		var arena := _arena()
		var cat := _cat(arena, id, Vector2(400, 300))
		if id == &"homing":
			_dog(arena, Vector2(650, 200))
		var emissions: Array[int] = [0]
		cat.ability_used.connect(func() -> void: emissions[0] += 1)
		_check(not cat.can_activate_ability() and not cat.activate_ability(), "%s cannot activate in the sling" % id)
		cat.launch(Vector2(250, 0))
		paused = true
		_check(not cat.activate_ability() and not cat.ability_spent, "%s cannot spend its ability while paused" % id)
		paused = false
		_check(cat.can_activate_ability() and cat.activate_ability(), "%s activates after launch" % id)
		_check(cat.ability_spent and not cat.activate_ability() and emissions[0] == 1, "%s activates and emits only once" % id)
		await _clear(arena)


func _test_contact_lock() -> void:
	var arena := _arena()
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(1000, 500)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2200, 20)
	collision.shape = shape
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	var cats: Array[CatProjectile] = []
	for id: StringName in ACTIVE_IDS:
		if id == &"bomb":
			continue
		var cat := _cat(arena, id, Vector2(180 + 200 * cats.size(), 410))
		cat.launch(Vector2(0, 300))
		cats.append(cat)
	await create_timer(0.35).timeout
	for cat: CatProjectile in cats:
		_check(cat._has_contacted and not cat.can_activate_ability() and not cat.activate_ability(), "%s loses its unused ability on physical contact" % cat.definition.id)
	await _clear(arena)


func _test_dash_and_dive() -> void:
	var arena := _arena()
	var dash := _cat(arena, &"classic", Vector2(200, 200))
	var dive := _cat(arena, &"heavy", Vector2(200, 400))
	var velocity := Vector2(850, -300)
	var initial_mass := dive.mass
	dash.launch(velocity)
	dive.launch(velocity)
	dash.activate_ability()
	dive.activate_ability()
	await physics_frame
	await physics_frame
	_check(dash.linear_velocity.length() > velocity.length() * 1.6 and dash.linear_velocity.normalized().dot(velocity.normalized()) > 0.98, "Dash visibly accelerates an already fast shot along its flight direction")
	_check(dive.linear_velocity.y > velocity.length() * 1.4 and absf(dive.linear_velocity.x) < velocity.x * 0.2 and dive.mass > initial_mass * 1.5, "Heavy cat turns a fast rising shot into a substantially heavier vertical dive")
	var fast_cat := _cat(arena, &"classic", Vector2(200, 600))
	fast_cat.launch(Vector2(2000, 0))
	fast_cat.activate_ability()
	_check(fast_cat.linear_velocity.x >= 2000.0, "Dash never slows a shot that already exceeds its boost speed")
	await _clear(arena)


func _test_blast_coverage() -> void:
	var arena := _arena()
	var cat := _cat(arena, &"bomb", Vector2(400, 300))
	var target := _dog(arena, Vector2(580, 300))
	var distant := _dog(arena, Vector2(680, 300))
	cat.launch(Vector2(850, -300))
	cat.activate_ability()
	await _frames()
	_check(not is_instance_valid(target), "Blast reaches a dog several body widths away from a fast flying cat")
	_check(is_instance_valid(distant) and not distant.is_destroyed, "Stronger blast retains a finite radius")
	await _clear(arena)


func _test_splitter_round() -> void:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.cat_definition = CharacterCatalog.find_cat(&"splitter")
	root.add_child(game)
	current_scene = game
	var original := game.slingshot.loaded_projectile
	var original_mass := original.mass
	game.slingshot.launch_from_pull(Vector2(70, 10))
	var original_speed := original.linear_velocity.length()
	game.use_ability()
	await _frames()
	var kittens: Array[CatProjectile] = []
	for actor: Node in game.actors.get_children():
		if actor is CatProjectile:
			kittens.append(actor)
	_check(kittens.size() == 3 and kittens.has(original), "Split keeps the original and adds two kittens to the current Actors")
	var all_small_and_spent := true
	var minimum_y := INF
	var maximum_y := -INF
	var combined_mass := 0.0
	for kitten: CatProjectile in kittens:
		var shape := kitten.get_node("CollisionShape2D").shape as CircleShape2D
		all_small_and_spent = all_small_and_spent and shape.radius < CatProjectile.RADIUS and kitten.was_launched and kitten.ability_spent and not kitten.activate_ability()
		minimum_y = minf(minimum_y, kitten.linear_velocity.y)
		maximum_y = maxf(maximum_y, kitten.linear_velocity.y)
		combined_mass += kitten.mass
	_check(all_small_and_spent and maximum_y - minimum_y > original_speed * 0.55, "Small kittens fan out broadly from a real shot and cannot split again")
	_check(combined_mass > original_mass * 1.5, "The three kittens retain enough combined mass to strike separate structures")
	_check(game.shots_left == 3, "Splitting consumes only the original shot")
	await create_timer(0.1).timeout
	_check(kittens.all(func(kitten: CatProjectile) -> bool: return is_instance_valid(kitten) and kitten.get_parent() == game.actors), "All kittens remain in the active round during the shot")
	game._finish_shot()
	await _frames()
	_check(kittens.all(func(kitten: Variant) -> bool: return not is_instance_valid(kitten)), "Finishing the shot removes every kitten")
	_check(game.state == GameRound.RoundState.READY and is_instance_valid(game.slingshot.loaded_projectile), "Next shot loads normally after splitting")
	await _clear(game)


func _test_wind() -> void:
	var arena := _arena()
	var other_arena := _arena()
	var cat := _cat(arena, &"wind", Vector2(400, 300))
	var block := _block(arena, Vector2(490, 300))
	var outer_block := _block(arena, Vector2(630, 300))
	var dog := _dog(arena, Vector2(400, 190))
	var distant := _block(arena, Vector2(1000, 300))
	var unrelated := _block(other_arena, Vector2(490, 300))
	unrelated.collision_layer = 0
	unrelated.collision_mask = 0
	cat.launch(Vector2(850, -300))
	cat.activate_ability()
	await physics_frame
	await physics_frame
	_check(block.linear_velocity.x > 350.0 and block.linear_velocity.y < -250.0 and dog.linear_velocity.x > 350.0, "Wind gives nearby wood and dogs a strong forward and upward push")
	_check(outer_block.linear_velocity.length() > 250.0, "Wind meaningfully moves a block beyond the nearest cluster")
	_check(distant.linear_velocity.length() < 1.0 and unrelated.linear_velocity.length() < 1.0, "Wind is local to its radius and Actors parent")
	await _clear(arena)
	await _clear(other_arena)


func _test_magnet() -> void:
	var arena := _arena()
	var cat := _cat(arena, &"magnet", Vector2(400, 300))
	var block := _block(arena, Vector2(580, 300))
	var distant := _block(arena, Vector2(400, 1100))
	var dog := _dog(arena, Vector2(400, 180))
	block.collision_layer = 0
	block.collision_mask = 0
	cat.launch(Vector2(850, -300))
	cat.activate_ability()
	await create_timer(0.15).timeout
	_check(block.linear_velocity.x < -140.0, "Magnet pulls nearby wood strongly during an ordinary fast shot")
	_check(distant.linear_velocity.length() < 1.0 and dog.linear_velocity.length() < 1.0, "Magnet ignores distant wood and dogs")
	paused = true
	await process_frame
	var paused_time := cat.ability.time_left
	var paused_position := block.position
	await create_timer(0.12).timeout
	_check(cat.ability.time_left == paused_time and block.position == paused_position, "Pause stops magnetic force and its countdown")
	paused = false
	await create_timer(cat.ability.magnet_duration + 0.1).timeout
	block.position = cat.position + Vector2(160, 0)
	block.linear_velocity = Vector2.ZERO
	await create_timer(0.2).timeout
	_check(block.linear_velocity.length() < 1.0, "Magnetic force ends after its limited duration")
	await _clear(arena)


func _test_frost() -> void:
	var arena := _arena()
	var cat := _cat(arena, &"frost", Vector2(400, 300))
	var dog := _dog(arena, Vector2(500, 300))
	var outer_dog := _dog(arena, Vector2(620, 300))
	var already_frozen := _dog(arena, Vector2(400, 430))
	already_frozen.freeze = true
	var distant := _dog(arena, Vector2(700, 300))
	var block := _block(arena, Vector2(300, 300))
	cat.launch(Vector2(850, -300))
	cat.activate_ability()
	await _frames()
	_check(dog.freeze and outer_dog.freeze and already_frozen.freeze and not distant.freeze and not block.freeze, "Frost reaches dogs across a wider cluster while retaining its radius and target restrictions")
	var frost_time := dog.frost_time_left
	paused = true
	await create_timer(0.15).timeout
	_check(is_equal_approx(dog.frost_time_left, frost_time), "Pause stops the frost countdown")
	paused = false
	cat.queue_free()
	await _frames()
	_check(dog.freeze, "Frost keeps its duration after the caster is removed")
	await create_timer(2.5).timeout
	_check(not dog.freeze and already_frozen.freeze, "Frost restores each dog's previous freeze state after expiry")
	var vulnerable := _dog(arena, Vector2(200, 300))
	vulnerable.apply_frost(2.4)
	vulnerable.receive_hit(700.0)
	await _frames()
	_check(not is_instance_valid(vulnerable), "Frozen dogs remain vulnerable to impacts and free safely")
	await _clear(arena)


func _test_frozen_impacts() -> void:
	var arena := _arena()
	var cat_target := _dog(arena, Vector2(500, 200))
	var block_target := _dog(arena, Vector2(500, 500))
	cat_target.apply_frost(2.4)
	block_target.apply_frost(2.4)
	var cat := _cat(arena, &"classic", Vector2(300, 200))
	cat.launch(Vector2(650, 0))
	var block := _block(arena, Vector2(300, 500))
	block.spawn_grace_seconds = 0.0
	block.linear_velocity = Vector2(650, 0)
	await create_timer(0.45).timeout
	_check(not is_instance_valid(cat_target), "A real flying cat defeats a frozen dog through physical contact")
	_check(not is_instance_valid(block_target), "A real moving block defeats a frozen dog through physical contact")
	await _clear(arena)


func _test_ghost() -> void:
	var arena := _arena()
	var cat := _cat(arena, &"ghost", Vector2(350, 300))
	var wall := _block(arena, Vector2(480, 300))
	wall.freeze = true
	var late_wall := _block(arena, Vector2(1200, 300))
	late_wall.freeze = true
	var existing := _block(arena, Vector2(750, 500))
	var dog := _dog(arena, Vector2(700, 500))
	cat.add_collision_exception_with(existing)
	cat.launch(Vector2(850, 0))
	cat.activate_ability()
	await _frames()
	_check(cat.get_collision_exceptions().has(wall) and not cat.get_collision_exceptions().has(dog), "Ghost excludes wood collisions while retaining dog collisions")
	await create_timer(0.65).timeout
	_check(cat.position.x > 530.0 and not cat._has_contacted, "Ghost physically passes through a wooden wall")
	await create_timer(maxf(cat.ability.time_left - 0.05, 0.0)).timeout
	_check(cat.position.x > late_wall.position.x + 40.0 and not cat._has_contacted, "Ghost crosses a second wall near the end of its extended flight window")
	await create_timer(0.15).timeout
	_check(not cat.get_collision_exceptions().has(wall) and cat.get_collision_exceptions().has(existing), "Ghost expiry restores wood collisions and preserves existing exceptions")
	var departing := _cat(arena, &"ghost", Vector2(100, 100))
	departing.launch(Vector2(10, 0))
	departing.activate_ability()
	await _frames()
	departing.queue_free()
	await _frames()
	_check(is_instance_valid(wall) and wall.get_collision_exceptions().is_empty(), "Removing a ghost leaves no stale collision exclusions on wood")
	await _clear(arena)


func _test_frozen_round_settling() -> void:
	var level := LevelDefinition.new()
	level.shots = 1
	level.dog_positions = PackedVector2Array([Vector2(600, 250)])
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = level
	game.cat_definition = CharacterCatalog.find_cat(&"frost")
	root.add_child(game)
	current_scene = game
	var cat := game.slingshot.loaded_projectile
	game.slingshot.launch_from_pull(Vector2(60, 20))
	cat.freeze = true
	cat.linear_velocity = Vector2.ZERO
	cat.angular_velocity = 0.0
	var dog: DogTarget
	for actor: Node in game.actors.get_children():
		if actor is DogTarget:
			dog = actor
	dog.apply_frost(2.4)
	await create_timer(1.4).timeout
	_check(game.shots_left == 0 and game.state == GameRound.RoundState.FLYING and dog.frost_time_left > 0.0, "A motionless frozen dog keeps the final shot open until thawing")
	await create_timer(2.0).timeout
	_check(game.state == GameRound.RoundState.WON and game.dogs_left == 0, "A dog falling after thawing can still win the final shot")
	await _clear(game)


func _test_ghost_expiry_inside_block() -> void:
	var arena := _arena()
	var cat := _cat(arena, &"ghost", Vector2(300, 300))
	var wall := _block(arena, Vector2(500, 300), Vector2(260, 240))
	wall.rotation = 0.2
	wall.freeze = true
	var distant := _block(arena, Vector2(850, 700))
	distant.freeze = true
	cat.launch(Vector2(150, 0))
	cat.activate_ability()
	var expiry_time := cat.ability.ghost_duration + 0.15
	await create_timer(expiry_time).timeout
	_check(cat.get_collision_exceptions().has(wall) and not cat.get_collision_exceptions().has(distant), "Expired ghost keeps only the currently intersecting block excluded")
	_check(not cat._has_contacted and absf(cat.position.x - (300.0 + 150.0 * expiry_time)) < 12.0 and absf(cat.position.y - 300.0) < 1.0, "Ghost expiration inside a rotated thick wall does not teleport or push the cat")
	var late_block := _block(arena, Vector2(900, 100))
	await create_timer(1.75).timeout
	_check(cat.position.x > 700.0 and not cat._has_contacted and not cat.get_collision_exceptions().has(wall), "Ghost restores collision after safely leaving the thick wall")
	_check(not cat.get_collision_exceptions().has(late_block) and not cat.ability.is_physics_processing(), "Safe exit adds no new exclusions and stops processing once clear")
	await _clear(arena)


func _test_homing() -> void:
	var arena := _arena()
	var other_arena := _arena()
	var cat := _cat(arena, &"homing", Vector2(400, 300))
	var velocity := Vector2(850, 0)
	cat.launch(velocity)
	_check(not cat.activate_ability() and not cat.ability_spent, "Homing without targets keeps the unused ability")
	var unrelated := _dog(other_arena, Vector2(410, 400))
	unrelated.collision_layer = 0
	unrelated.collision_mask = 0
	_check(not cat.activate_ability() and not cat.ability_spent, "Homing ignores dogs belonging to another arena")
	var target := _dog(arena, Vector2(570, 0))
	var farther := _dog(arena, Vector2(1000, 650))
	target.freeze = true
	farther.freeze = true
	cat.collision_layer = 0
	cat.collision_mask = 0
	cat.activate_ability()
	# Измеряем поворот после 12 физических шагов, а не таймера отрисовки.
	for tick in 12:
		await physics_frame
	var target_direction := (target.position - cat.position).normalized()
	_check(absf(cat.linear_velocity.angle_to(target_direction)) < 0.35 and cat.linear_velocity.length() > velocity.length() * 0.98, "Homing sharply redirects a fast shot toward the nearest dog without sacrificing speed")
	target.queue_free()
	farther.queue_free()
	await create_timer(cat.ability.homing_duration + 0.1).timeout
	var final_velocity := cat.linear_velocity
	var late_target := _dog(arena, cat.position + Vector2(0, 200))
	late_target.freeze = true
	await create_timer(0.2).timeout
	_check(cat.linear_velocity.distance_to(final_velocity) < 1.0, "Homing safely loses removed targets and stops steering after expiry")
	await _clear(arena)
	await _clear(other_arena)


func _arena() -> Node2D:
	var arena := Node2D.new()
	root.add_child(arena)
	return arena


func _cat(parent: Node, id: StringName, at: Vector2) -> CatProjectile:
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.find_cat(id)
	cat.position = at
	cat.gravity_scale = 0.0
	parent.add_child(cat)
	return cat


func _dog(parent: Node, at: Vector2) -> DogTarget:
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(&"scout")
	dog.position = at
	dog.gravity_scale = 0.0
	parent.add_child(dog)
	return dog


func _block(parent: Node, at: Vector2, size: Vector2 = Vector2(34, 140)) -> WoodenBlock:
	var block := BLOCK_SCENE.instantiate() as WoodenBlock
	block.position = at
	block.size = size
	block.gravity_scale = 0.0
	parent.add_child(block)
	return block


func _clear(node: Node) -> void:
	node.queue_free()
	await _frames()


func _frames() -> void:
	await process_frame
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
