extends SceneTree
## Постоянная нагрузка этажей не является ударом; снаряды и падение всё ещё разрушают.

const BLOCK_SCENE := preload("res://scenes/actors/wooden_block.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(900, 640)
	var floor_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1200, 40)
	floor_shape.shape = rectangle
	floor_body.add_child(floor_shape)
	arena.add_child(floor_body)
	var support := _block(arena, Vector2(900, 570), Vector2(100, 100), &"glass")
	var weight := _block(arena, Vector2(900, 470), Vector2(100, 100), &"metal")
	weight.mass = 30.0
	var blocks: Array[WoodenBlock] = [support, weight]
	for tick in 240:
		await physics_frame
	for block in blocks:
		_check(is_instance_valid(block) and not block.is_destroyed and is_zero_approx(block.damage_ratio()), "A loaded structure remains intact after spawn grace")
	if is_instance_valid(support):
		_check(support.position.distance_to(Vector2(900, 570)) < 3.0, "The support remains in place under the weight: %s" % support.position)
		var cat := CAT_SCENE.instantiate() as CatProjectile
		cat.position = Vector2(600, 570)
		cat.gravity_scale = 0.0
		arena.add_child(cat)
		cat.launch(Vector2(1100, 0))
		for tick in 75:
			await physics_frame
		_check(not is_instance_valid(support) or support.is_destroyed, "A real fast impact still breaks the loaded glass support")
	var falling := _block(arena, Vector2(1250, 260), Vector2(40, 40), &"glass")
	for tick in 110:
		await physics_frame
	_check(not is_instance_valid(falling) or falling.is_destroyed, "An actual fall still shatters glass on the ground")
	var returning := _block(arena, Vector2(400, 600), Vector2(40, 40), &"metal")
	for tick in 90:
		await physics_frame
	for attempt in 2:
		if not is_instance_valid(returning):
			_check(false, "Metal survives long enough for the second independent collision")
			break
		var hits_before: int = returning.hits_left
		returning.sleeping = false
		returning.apply_central_impulse(Vector2(0, -650) * returning.mass)
		for tick in 110:
			await physics_frame
		_check(not is_instance_valid(returning) or returning.hits_left < hits_before, "A new landing on the same floor causes damage again after separation")
	arena.queue_free()
	await process_frame
	await process_frame
	await _test_heavy_shelter_impact()
	print("Structural load checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_heavy_shelter_impact() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.material_id = &"metal"
	house.house_type = &"barrel"
	house.position = Vector2(900, 300)
	house.gravity_scale = 0.0
	arena.add_child(house)
	for tick in 60:
		await physics_frame
	var hits_before: int = house.hits_left
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.position = Vector2(600, 300)
	cat.gravity_scale = 0.0
	arena.add_child(cat)
	cat.launch(Vector2(1100, 0))
	for tick in 50:
		await physics_frame
	_check(not is_instance_valid(house) or house.hits_left < hits_before, "A light fast cat damages a heavy shelter even when the solver stops it")
	arena.queue_free()
	await process_frame
	await create_timer(0.2).timeout


func _block(arena: Node2D, at: Vector2, size: Vector2, material: StringName) -> WoodenBlock:
	var block := BLOCK_SCENE.instantiate() as WoodenBlock
	block.position = at
	block.size = size
	block.material_id = material
	arena.add_child(block)
	return block


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
