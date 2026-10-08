extends SceneTree
## Compare real pre-change and slowed flights at equal positions along the arc.

const CAT := preload("res://scenes/actors/cat_projectile.tscn")
const SLING := preload("res://scenes/gameplay/slingshot.tscn")
const CATALOG := preload("res://scripts/data/character_catalog.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX"), true)
	for pull: Vector2 in [Vector2(-74.2462, 74.2462), Vector2(-90, 30), Vector2(-35, 55)]:
		await _compare_arc(pull, false)
	await _compare_arc(Vector2(-90, 30), true)
	await _check_fragments()
	await _check_ability_speeds()
	await _check_impact()
	print("Flight speed checks: %d passed, %d failed" % [_checks - _failures, _failures])
	await create_timer(0.3).timeout
	quit(1 if _failures else 0)


func _compare_arc(pull: Vector2, zigzag: bool) -> void:
	var sling := SLING.instantiate() as Slingshot
	sling.position = Vector2(235, 460)
	root.add_child(sling)
	var original := CAT.instantiate() as CatProjectile
	var slowed := CAT.instantiate() as CatProjectile
	for cat: CatProjectile in [original, slowed]:
		cat.collision_mask = 0
		if zigzag:
			cat.definition = CATALOG.find_cat(&"zigzag")
		root.add_child(cat)
		cat.meow_count = CatProjectile.MAX_MEOWS
	sling.load_projectile(slowed)
	# Loading again must not quarter gravity a second time.
	sling.load_projectile(slowed)
	_check(is_equal_approx(slowed.gravity_scale, 0.25), "Only the cat's gravity is quartered, once")
	_check(sling.launch_from_pull(pull), "The real sling launches the slowed cat")
	original.position = sling.position + pull
	original.launch(-pull * 10.0)
	_check(slowed.linear_velocity.distance_to(original.linear_velocity * 0.5) < 0.01, "Launch velocity is exactly halved")
	var old_points: Array[Vector2] = []
	var maximum_error := 0.0
	var old_landing_tick := 0
	var new_landing_tick := 0
	var old_range := 0.0
	var new_range := 0.0
	for tick in range(1, 601):
		await physics_frame
		await process_frame
		old_points.append(original.position)
		if tick % 2 == 0 and tick <= 120:
			maximum_error = maxf(maximum_error, slowed.position.distance_to(old_points[tick / 2 - 1]))
		if old_landing_tick == 0 and original.position.y + CatProjectile.RADIUS >= 620.0:
			old_landing_tick = tick
			old_range = original.position.x
		if new_landing_tick == 0 and slowed.position.y + CatProjectile.RADIUS >= 620.0:
			new_landing_tick = tick
			new_range = slowed.position.x
		if old_landing_tick > 0 and new_landing_tick > 0:
			break
	_check(maximum_error < (15.0 if zigzag else 9.0), "Real arcs coincide within physics-step sampling: %.2f px" % maximum_error)
	_check(old_landing_tick > 0 and absi(new_landing_tick - old_landing_tick * 2) <= 3, "Flight takes twice as long")
	_check(absf(new_range - old_range) < 18.0, "Landing range is preserved within physics sampling: %.2f px" % absf(new_range - old_range))
	_check(original.trajectory_offset(0.7, -pull * 10.0).distance_to(slowed.trajectory_offset(1.4, -pull * 5.0)) < 0.01, "Aim wave keeps its original shape")
	for actor: Node in [original, slowed, sling]:
		actor.queue_free()
	await process_frame


func _check_fragments() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var sling := SLING.instantiate() as Slingshot
	world.add_child(sling)
	var cat := CAT.instantiate() as CatProjectile
	cat.definition = CATALOG.find_cat(&"splitter")
	world.add_child(cat)
	cat.meow_count = CatProjectile.MAX_MEOWS
	sling.load_projectile(cat)
	sling.launch_from_pull(Vector2(-90, 30))
	var speed := cat.linear_velocity.length()
	_check(cat.activate_ability(), "Splitter activates during the slowed flight")
	await process_frame
	var fragments := 0
	for actor: Node in world.get_children():
		if actor is CatProjectile:
			fragments += 1
			_check(is_equal_approx(actor.gravity_scale, 0.25) and is_equal_approx(actor.flight_speed_scale, 0.5), "Every fragment inherits slowed gravity and ability time")
			_check(absf(actor.linear_velocity.length() - speed) < 5.0, "Splitting does not double the speed")
	_check(fragments == 3, "Splitter creates exactly three slowed cats")
	world.queue_free()
	await process_frame


func _check_ability_speeds() -> void:
	for kind: StringName in [&"classic", &"heavy", &"ghost", &"homing"]:
		var world := Node2D.new()
		root.add_child(world)
		var dog := preload("res://scenes/actors/dog_target.tscn").instantiate() as DogTarget
		dog.position = Vector2(900, 300)
		dog.freeze = true
		world.add_child(dog)
		var cat := CAT.instantiate() as CatProjectile
		cat.definition = CATALOG.find_cat(kind)
		world.add_child(cat)
		cat.set_flight_speed_scale(0.5)
		cat.launch(Vector2(450, -150))
		_check(cat.activate_ability(), "Slowed %s activates" % kind)
		if kind == &"classic":
			_check(is_equal_approx(cat.linear_velocity.length(), 800.0), "Dash also moves at half its original speed")
		elif kind == &"heavy":
			_check(is_equal_approx(cat.linear_velocity.y, 725.0), "Dive also moves at half its original speed")
		else:
			var duration := cat.ability.time_left
			for tick in 30:
				await physics_frame
			_check(absf(duration - cat.ability.time_left - 0.25) < 0.02, "Ghost and homing duration follows slowed flight")
		world.queue_free()
		await process_frame


func _check_impact() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var block := preload("res://scenes/actors/wooden_block.tscn").instantiate() as WoodenBlock
	block.position = Vector2(450, 300)
	world.add_child(block)
	block.gravity_scale = 0.0
	block.spawn_grace_seconds = 0.0
	block.impact_threshold = 700.0
	var impacts: Array[float] = []
	block.impact_received.connect(func(strength: float) -> void: impacts.append(strength))
	var cat := CAT.instantiate() as CatProjectile
	cat.position = Vector2(300, 300)
	world.add_child(cat)
	cat.set_flight_speed_scale(0.5)
	cat.gravity_scale = 0.0
	cat.launch(Vector2(450, 0))
	for tick in 45:
		await physics_frame
	_check(not impacts.is_empty() and impacts[0] >= 700.0, "A slowed real collision keeps the original material damage")
	var rope := preload("res://scripts/gameplay/breakable_rope.gd").new() as BreakableRope
	world.add_child(rope)
	cat.linear_velocity = Vector2(100, 0)
	rope._on_body_entered(cat)
	_check(rope.is_broken, "Slowed cat still breaks a rope at the original launch power")
	world.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
