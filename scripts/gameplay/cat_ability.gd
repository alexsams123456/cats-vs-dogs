class_name CatAbility
extends Node
## One-shot powers and bounded physical effects belong to each projectile.

@export var dash_speed: float = 1600.0
@export var dive_speed: float = 1450.0
@export var wind_radius: float = 260.0
@export var wind_speed: float = 760.0
@export var magnet_radius: float = 290.0
@export var magnet_duration: float = 1.4
@export var magnet_acceleration: float = 2600.0
@export var frost_radius: float = 250.0
@export var frost_duration: float = 2.4
@export var ghost_duration: float = 1.15
@export var homing_duration: float = 1.35
@export var homing_turn_speed: float = 6.0
@export var split_angle: float = 0.34

var time_left: float = 0.0
var last_speed: float = 0.0
var _cat: CatProjectile
var _target: DogTarget
var _ghost_blocks: Array[WoodenBlock] = []
var _effect_age: float = 0.0


func _ready() -> void:
	_cat = get_parent() as CatProjectile
	set_physics_process(false)


func can_activate() -> bool:
	match _kind():
		&"classic", &"splitter", &"heavy", &"wind", &"magnet", &"frost", &"ghost":
			return true
		&"homing":
			return _nearest_dog() != null
	return false


func activate() -> void:
	match _kind():
		&"classic":
			_cat.linear_velocity = _direction() * maxf(dash_speed, _cat.linear_velocity.length())
			_start_effect(0.45)
			_burst(50.0)
		&"splitter":
			_split.call_deferred()
		&"heavy":
			_cat.linear_velocity = Vector2(_cat.linear_velocity.x * 0.15, dive_speed)
			_cat.mass *= 2.0
			_start_effect(0.65)
			_burst(60.0)
		&"wind":
			_gust()
		&"magnet":
			_start_effect(magnet_duration)
		&"frost":
			_freeze_dogs()
		&"ghost":
			_phase_through_wood()
		&"homing":
			_target = _nearest_dog()
			_start_effect(homing_duration)


func integrate(state: PhysicsDirectBodyState2D) -> void:
	last_speed = state.linear_velocity.length()
	if time_left <= 0.0 or _kind() != &"homing":
		return
	if not _valid_target(_target):
		_target = _nearest_dog()
	if _target == null:
		return
	var offset := _target.global_position - _cat.global_position
	if offset.length_squared() < 1.0 or last_speed < 1.0:
		return
	var turn := clampf(state.linear_velocity.angle_to(offset), -homing_turn_speed * state.step, homing_turn_speed * state.step)
	state.linear_velocity = state.linear_velocity.rotated(turn)


func stop_on_contact() -> void:
	if _kind() == &"homing" or _kind() == &"magnet":
		time_left = 0.0
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	_effect_age += delta
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		# Finish crossing an entered obstacle before restoring its collision.
		_restore_wood_collisions(true)
		set_physics_process(not _ghost_blocks.is_empty())
		return
	if _kind() == &"magnet":
		_attract_blocks()


func _exit_tree() -> void:
	_restore_wood_collisions()


func _start_effect(duration: float) -> void:
	time_left = duration
	_effect_age = 0.0
	set_physics_process(true)


func _split() -> void:
	if not is_inside_tree() or _cat.is_queued_for_deletion():
		return
	var scene := load("res://scenes/actors/cat_projectile.tscn") as PackedScene
	var velocity := _cat.linear_velocity
	var normal := _direction().orthogonal()
	_cat.make_fragment()
	for side in [-1.0, 1.0]:
		var fragment := scene.instantiate() as CatProjectile
		fragment.definition = _cat.definition
		fragment.position = _cat.position + normal * side * 42.0
		_cat.get_parent().add_child(fragment)
		fragment.make_fragment()
		# Siblings must not collide while spreading out of their shared origin.
		for actor: Node in _cat.get_parent().get_children():
			if actor is CatProjectile and actor != fragment:
				fragment.add_collision_exception_with(actor)
		fragment.launch(velocity.rotated(side * split_angle))
	_burst(72.0)


func _gust() -> void:
	_start_effect(0.55)
	var forward := _direction()
	var gust := (forward + Vector2.UP * 0.65).normalized()
	for actor: Node in _cat.get_parent().get_children():
		var body := actor as DestructibleBody
		if body == null or body.is_destroyed or body.is_queued_for_deletion():
			continue
		var distance := _cat.global_position.distance_to(body.global_position)
		if distance > wind_radius:
			continue
		var strength := wind_speed * lerpf(1.0, 0.4, distance / wind_radius)
		body.sleeping = false
		body.apply_central_impulse(gust * strength * body.mass)
	_burst(wind_radius)


func _attract_blocks() -> void:
	for actor: Node in _cat.get_parent().get_children():
		var block := actor as WoodenBlock
		if block == null or block.is_destroyed or block.is_queued_for_deletion():
			continue
		var offset := _cat.global_position - block.global_position
		var distance := offset.length()
		if distance < 1.0 or distance > magnet_radius:
			continue
		var falloff := 1.0 - distance / magnet_radius
		block.sleeping = false
		block.apply_central_force(offset.normalized() * magnet_acceleration * falloff * block.mass)


func _freeze_dogs() -> void:
	_start_effect(0.55)
	for actor: Node in _cat.get_parent().get_children():
		var dog := actor as DogTarget
		if _valid_target(dog) and _cat.global_position.distance_to(dog.global_position) <= frost_radius:
			dog.apply_frost(frost_duration)
	_burst(frost_radius)


func _phase_through_wood() -> void:
	var existing := _cat.get_collision_exceptions()
	for actor: Node in _cat.get_parent().get_children():
		var block := actor as WoodenBlock
		if block == null or block.is_destroyed or existing.has(block):
			continue
		_cat.add_collision_exception_with(block)
		_ghost_blocks.append(block)
	_start_effect(ghost_duration)


func _restore_wood_collisions(only_clear: bool = false) -> void:
	for index in range(_ghost_blocks.size() - 1, -1, -1):
		var block := _ghost_blocks[index]
		if is_instance_valid(_cat) and is_instance_valid(block):
			if only_clear and _overlaps_block(block):
				continue
			_cat.remove_collision_exception_with(block)
		_ghost_blocks.remove_at(index)


func _overlaps_block(block: WoodenBlock) -> bool:
	var local_center := block.to_local(_cat.global_position)
	var half_size := block.size * 0.5
	var nearest := local_center.clamp(-half_size, half_size)
	var radius := CatProjectile.RADIUS * _cat.projectile_scale + 2.0
	return local_center.distance_squared_to(nearest) <= radius * radius


func _nearest_dog() -> DogTarget:
	var nearest: DogTarget
	var nearest_distance := INF
	for actor: Node in _cat.get_parent().get_children():
		var dog := actor as DogTarget
		if not _valid_target(dog):
			continue
		var distance := _cat.global_position.distance_squared_to(dog.global_position)
		if distance < nearest_distance:
			nearest = dog
			nearest_distance = distance
	return nearest


func _valid_target(dog: Variant) -> bool:
	return is_instance_valid(dog) and not dog.is_destroyed and not dog.is_queued_for_deletion()


func _direction() -> Vector2:
	return _cat.linear_velocity.normalized() if _cat.linear_velocity.length_squared() > 1.0 else Vector2.RIGHT


func _kind() -> StringName:
	return _cat.definition.id if _cat.definition != null else &"classic"


func _burst(radius: float) -> void:
	var burst := AbilityBurst.new()
	burst.position = _cat.position
	burst.radius = radius
	burst.kind = _kind()
	burst.direction = _direction()
	burst.color = _cat.definition.accent_color if _cat.definition != null else Color("ffe1ab")
	_cat.get_parent().add_child(burst)


func draw_effect(canvas: CatProjectile) -> void:
	if time_left <= 0.0 and _ghost_blocks.is_empty():
		return
	var tint := canvas.definition.accent_color if canvas.definition != null else Color("ffe1ab")
	match _kind():
		&"magnet":
			for index in range(3):
				var progress := fposmod(_effect_age * 1.8 + float(index) / 3.0, 1.0)
				var radius := lerpf(magnet_radius, 34.0, progress)
				var ink := Color(tint, sin(progress * PI) * 0.7)
				canvas.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(ink, ink.a * 0.6), 3.0, true)
				for spoke in range(6):
					var ray := Vector2.from_angle(float(spoke) * TAU / 6.0 + _effect_age * 0.35)
					var tip := ray * radius
					canvas.draw_line(tip, tip + ray.rotated(0.5) * 18.0, ink, 3.5, true)
					canvas.draw_line(tip, tip + ray.rotated(-0.5) * 18.0, ink, 3.5, true)
		&"ghost":
			for index in range(3, 0, -1):
				var center := canvas.to_local(canvas.global_position - _direction() * float(index) * 28.0)
				canvas.draw_circle(center, CatProjectile.RADIUS + 6.0, Color(tint, 0.22 - float(index) * 0.04))
				canvas.draw_arc(center, CatProjectile.RADIUS + 6.0, 0.0, TAU, 32, Color(tint, 0.6 - float(index) * 0.12), 2.5, true)
			canvas.draw_circle(Vector2.ZERO, CatProjectile.RADIUS + 12.0, Color(tint, 0.18))
			canvas.draw_arc(Vector2.ZERO, CatProjectile.RADIUS + 18.0, _effect_age * 5.0, _effect_age * 5.0 + PI * 1.4, 32, Color(tint, 0.9), 4.0, true)
		&"homing":
			if _valid_target(_target):
				var target_position := canvas.to_local(_target.global_position)
				var radius := 42.0 + sin(_effect_age * 10.0) * 4.0
				canvas.draw_arc(target_position, radius, 0.0, TAU, 32, Color(tint, 0.9), 3.5, true)
				for index in range(4):
					var ray := Vector2.from_angle(float(index) * PI * 0.5)
					canvas.draw_line(target_position + ray * (radius - 8.0), target_position + ray * (radius + 12.0), Color(tint, 0.95), 3.5, true)
				var distance := target_position.length()
				for step in range(1, int(distance / 30.0)):
					var point := target_position.normalized() * (float(step) * 30.0 + fposmod(_effect_age * 90.0, 30.0))
					if point.length() < distance - radius:
						canvas.draw_circle(point, 2.5, Color(tint, 0.65))
			_draw_speed_trail(canvas, tint, 75.0)
		&"classic", &"heavy":
			_draw_speed_trail(canvas, tint, 150.0 if _kind() == &"classic" else 180.0)
		&"wind", &"frost":
			var radius := CatProjectile.RADIUS + 16.0 + sin(_effect_age * 12.0) * 4.0
			canvas.draw_arc(Vector2.ZERO, radius, _effect_age * 3.0, _effect_age * 3.0 + TAU * 0.8, 40, Color(tint, 0.8), 4.0, true)


func _draw_speed_trail(canvas: CatProjectile, tint: Color, length: float) -> void:
	var backward := canvas.to_local(canvas.global_position - _direction()).normalized()
	var normal := backward.orthogonal()
	canvas.draw_line(backward * 22.0, backward * length, Color(tint, 0.4), 17.0, true)
	canvas.draw_line(backward * 25.0, backward * length * 0.85, Color(tint.lightened(0.6), 0.85), 5.0, true)
	for side in [-1.0, 1.0]:
		var offset: Vector2 = normal * side * 24.0
		canvas.draw_line(offset + backward * 16.0, offset + backward * length * 0.68, Color(tint, 0.65), 3.5, true)
