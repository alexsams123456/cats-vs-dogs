class_name CatProjectile
extends RigidBody2D
## A cat stays frozen in the sling until launch() assigns its initial velocity.

signal ability_used
signal ability_availability_changed
signal meow_requested

const RADIUS: float = 23.0
const TRAIL_LIFETIME: float = 0.55
const MEOW_INTERVAL: float = 0.68
const MAX_MEOWS: int = 5
const SPEECH_FONT := preload("res://assets/fonts/interface_font.tres")

@export var definition: CharacterDefinition
@export_range(100.0, 300.0, 5.0) var blast_radius: float = 190.0
@export_range(1.0, 2.0, 0.05) var wave_duration: float = 1.5
@export_range(1.5, 3.5, 0.1) var wave_frequency: float = 2.0
@export_range(1000.0, 18000.0, 100.0) var wave_acceleration: float = 10000.0

var was_launched: bool = false
var ability_spent: bool = false
var visual_time: float = 0.0
var expression: StringName = &"idle"
var meow_count: int = 0
var projectile_scale: float = 1.0
var flight_speed_scale: float = 1.0
var _visual_phase: float = 0.0
var _aiming: bool = false
var _has_contacted: bool = false
var _air_voice_time: float = 0.0
var _mouth_time_left: float = 0.0
var _hit_time_left: float = 0.0
var _speech_style: StyleBoxFlat
var _flight_age: float = 0.0
var _wave_normal: Vector2 = Vector2.UP
var _wave_finished: bool = false
var _blast_origin: Vector2 = Vector2.ZERO
var _trail_points: Array[Vector2] = []
var _trail_times: Array[float] = []
var impact_motion := preload("res://scripts/actors/impact_motion.gd").new()

@onready var ability: CatAbility = $Ability


func _ready() -> void:
	if HeroVisual.use_atlas and definition != null:
		HeroVisual.ATLAS.prepare(definition)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_physics_process(false)
	_visual_phase = float(get_instance_id() % 997) * 0.061
	_speech_style = StyleBoxFlat.new()
	_speech_style.bg_color = Color("fff9ed")
	_speech_style.border_color = Color("ddc7a9")
	_speech_style.set_border_width_all(1)
	_speech_style.set_corner_radius_all(8)


func _process(delta: float) -> void:
	var previous_time := visual_time
	var previous_expression := expression
	visual_time += delta
	_mouth_time_left = maxf(0.0, _mouth_time_left - delta)
	_hit_time_left = maxf(0.0, _hit_time_left - delta)
	if _is_airborne():
		_air_voice_time += delta
		if meow_count < MAX_MEOWS and _air_voice_time >= MEOW_INTERVAL * meow_count:
			_request_meow()
	_refresh_expression()
	if expression != previous_expression or HeroVisual.needs_redraw(previous_time, visual_time):
		queue_redraw()


func set_aiming(value: bool) -> void:
	_aiming = value and not was_launched
	_refresh_expression()
	queue_redraw()


func set_flight_speed_scale(value: float) -> void:
	# Scaling velocity by s needs gravity scaled by s² to keep the same arc.
	gravity_scale *= (value / flight_speed_scale) ** 2
	flight_speed_scale = value


func launch(velocity: Vector2) -> void:
	# Aiming follows the pointer directly; flight is smoothed between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()
	_aiming = false
	was_launched = true
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = -velocity.x * 0.002
	impact_motion.seed(linear_velocity, angular_velocity)
	_wave_normal = velocity.normalized().orthogonal()
	if _kind() == &"zigzag":
		set_physics_process(true)
	_request_meow()


func _request_meow() -> void:
	if meow_count >= MAX_MEOWS or _has_contacted or freeze or is_queued_for_deletion():
		return
	meow_count += 1
	_mouth_time_left = 0.45
	expression = &"meow"
	meow_requested.emit()
	queue_redraw()


func _is_airborne() -> bool:
	return (
		was_launched and not _has_contacted and not freeze and not sleeping
		and not is_queued_for_deletion() and linear_velocity.length() > 60.0
	)


func _refresh_expression() -> void:
	if _hit_time_left > 0.0:
		expression = &"hit"
	elif _aiming:
		expression = &"aim"
	elif _mouth_time_left > 0.0 and not _has_contacted:
		expression = &"meow"
	elif _is_airborne():
		expression = &"fly"
	else:
		expression = &"idle"


func has_contacted() -> bool:
	return _has_contacted


func can_activate_ability() -> bool:
	if not was_launched or ability_spent or is_queued_for_deletion() or not is_inside_tree():
		return false
	if get_tree().paused or freeze:
		return false
	if _kind() == &"bomb":
		return true
	return not _has_contacted and ability != null and ability.can_activate()


func activate_ability() -> bool:
	if not can_activate_ability():
		return false
	ability_spent = true
	ability_used.emit()
	ability_availability_changed.emit()
	if _kind() == &"bomb":
		_blast_origin = global_position
		_detonate.call_deferred()
	else:
		ability.activate()
	return true


func make_fragment() -> void:
	ability_spent = true
	projectile_scale = 0.72
	mass = 1.0
	var shape := CircleShape2D.new()
	shape.radius = RADIUS * projectile_scale
	$CollisionShape2D.shape = shape
	queue_redraw()


func trajectory_offset(time: float, initial_velocity: Vector2) -> Vector2:
	if _kind() != &"zigzag":
		return Vector2.ZERO
	# sin(a) * sin(b) = (cos(a-b) - cos(a+b)) / 2; integrate twice.
	var elapsed := maxf(time, 0.0) * flight_speed_scale
	var powered_time := minf(elapsed, wave_duration)
	var low_frequency := TAU * wave_frequency - PI / wave_duration
	var high_frequency := TAU * wave_frequency + PI / wave_duration
	var displacement := wave_acceleration * 0.5 * (
		(1.0 - cos(low_frequency * powered_time)) / (low_frequency * low_frequency)
		- (1.0 - cos(high_frequency * powered_time)) / (high_frequency * high_frequency)
	)
	var sideways_speed := wave_acceleration * 0.5 * (
		sin(low_frequency * powered_time) / low_frequency
		- sin(high_frequency * powered_time) / high_frequency
	)
	return initial_velocity.normalized().orthogonal() * (
		displacement + sideways_speed * (elapsed - powered_time)
	)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	impact_motion.capture(state)
	if not was_launched:
		return
	if state.get_contact_count() > 0:
		# Frozen targets skip their own force integration but remain vulnerable.
		for index in state.get_contact_count():
			var dog := state.get_contact_collider_object(index) as DogTarget
			if dog != null and dog.frost_time_left > 0.0:
				var impact := maxf(ability.last_speed, state.get_contact_impulse(index).length() / mass) / flight_speed_scale
				dog.receive_hit(impact)
		if not _has_contacted:
			_has_contacted = true
			_mouth_time_left = 0.0
			_hit_time_left = 0.38
			expression = &"hit"
			ability_availability_changed.emit()
			ability.stop_on_contact()
		_wave_finished = true
		if _kind() == &"bomb":
			activate_ability()
	if _kind() == &"zigzag" and not _wave_finished and _flight_age < wave_duration:
		# A temporary transverse force changes the real trajectory, never the transform.
		var envelope := sin(PI * _flight_age / wave_duration)
		var wave := sin(_flight_age * TAU * wave_frequency) * envelope
		state.apply_central_force(_wave_normal * wave * wave_acceleration * mass * flight_speed_scale ** 2)
	ability.integrate(state)


func _physics_process(delta: float) -> void:
	_flight_age += delta * flight_speed_scale
	if _flight_age < wave_duration and not _wave_finished:
		_trail_points.append(global_position)
		_trail_times.append(_flight_age)
	while not _trail_times.is_empty() and _flight_age - _trail_times[0] > TRAIL_LIFETIME:
		_trail_times.remove_at(0)
		_trail_points.remove_at(0)
	queue_redraw()
	if _trail_points.is_empty() and (_wave_finished or _flight_age >= wave_duration):
		set_physics_process(false)


func _detonate() -> void:
	if not is_inside_tree():
		return
	var world := get_parent() as Node2D
	if world == null:
		return
	freeze = true
	collision_layer = 0
	collision_mask = 0
	var burst := AbilityBurst.new()
	burst.position = world.to_local(_blast_origin)
	burst.radius = blast_radius
	burst.kind = &"bomb"
	burst.color = _accent_color()
	world.add_child(burst)
	for actor: Node in world.get_children():
		var body := actor as DestructibleBody
		if body == null or body.is_destroyed:
			continue
		var offset: Vector2 = body.global_position - _blast_origin
		var distance := offset.length()
		if distance > blast_radius:
			continue
		var falloff := 1.0 - distance / blast_radius
		var direction := (offset.normalized() + Vector2.UP * 0.35).normalized()
		body.sleeping = false
		body.apply_central_impulse(direction * (220.0 + 550.0 * falloff) * body.mass)
		body.receive_hit(850.0 * (0.65 + 0.35 * falloff))
	queue_free()


func _kind() -> StringName:
	return definition.id if definition != null else &"classic"


func _accent_color() -> Color:
	return definition.accent_color if definition != null else Color("ffe1ab")


func _draw() -> void:
	var fur := definition.fur_color if definition != null else Color("ed9551")
	var accent := _accent_color()
	for index in _trail_points.size():
		var fade := 1.0 - (_flight_age - _trail_times[index]) / TRAIL_LIFETIME
		var point := to_local(_trail_points[index])
		if index > 0:
			var previous := to_local(_trail_points[index - 1])
			draw_line(previous, point, Color(accent, fade * 0.85), 3.0 + fade * 8.0, true)
			draw_line(previous, point, Color(0.95, 0.9, 1.0, fade * 0.8), 2.0, true)
	var breath := sin(visual_time * 2.5 + _visual_phase) * 0.025
	var visual_scale := Vector2(1.0 + breath, 1.0 - breath) * (RADIUS / 25.0) * projectile_scale
	var tilt := sin(visual_time * 1.8 + _visual_phase) * 0.025
	if expression == &"aim":
		visual_scale *= Vector2(1.06, 0.95)
	elif _is_airborne():
		visual_scale *= Vector2(1.10, 0.93)
	elif expression == &"hit":
		var squash := _hit_time_left / 0.38
		visual_scale *= Vector2(1.0 + squash * 0.13, 1.0 - squash * 0.13)
	# Drawing transforms affect the face only; the circular collision stays intact.
	draw_set_transform(Vector2(0, breath * 10.0), tilt, visual_scale)
	HeroVisual.paint(self, &"cat", _kind(), fur, accent, visual_time, _visual_phase, expression)
	draw_set_transform(Vector2.ZERO)
	if ability != null:
		ability.draw_effect(self)
	if expression == &"meow":
		_draw_meow_bubble()


func _draw_meow_bubble() -> void:
	if _speech_style == null:
		return
	# Keep the caption upright while the physical cat tumbles in flight.
	var anchor := Vector2(25, -53).rotated(-global_rotation)
	draw_set_transform(anchor, -global_rotation)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7, 8), Vector2(-10, 18), Vector2(2, 9),
	]), Color("fff9ed"))
	var caption := tr("Мяу!")
	var width := SPEECH_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var bubble_width := maxf(50.0, width + 16.0)
	draw_style_box(_speech_style, Rect2(-bubble_width * 0.5, -12, bubble_width, 24))
	draw_string(SPEECH_FONT, Vector2(-width * 0.5, 5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("634d46"))
	draw_set_transform(Vector2.ZERO)
