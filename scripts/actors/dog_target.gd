class_name DogTarget
extends DestructibleBody

signal defeated
signal bark_requested
signal idle_bark_requested
signal bark_interrupted

const RADIUS: float = 25.0
const JUMP_PROXIMITY: float = 260.0
const JUMP_COOLDOWN: float = 1.8
const MAX_JUMPS: int = 2
const MAX_BARKS_PER_CAT: int = 2
const BARK_PROXIMITY: float = 550.0

@export var definition: CharacterDefinition
@export_range(0.1, 10.0) var bark_cooldown_seconds: float = 0.9
@export_range(0.0, 120.0) var patrol_distance: float = 48.0
@export_range(0.0, 100.0) var patrol_speed: float = 55.0

var shield_active: bool = false
var jumps_used: int = 0
var frost_time_left: float = 0.0
var _freeze_before_frost: bool = false
var visual_time: float = 0.0
var expression: StringName = &"idle"
var shelter: DogHouse
var _sheltered_layer: int = 0
var _sheltered_mask: int = 0
var _sheltered_z_index: int = 0
var _visual_phase: float = 0.0
var _surprise_time_left: float = 0.0
var _alert_time_left: float = 0.0
var _alert_scan_left: float = 0.0
var _jump_cooldown_left: float = 0.0
var _jump_ground_grace_left: float = 0.0
var _bark_cooldown_left: float = 0.0
var _bark_time_left: float = 0.0
var _last_barked_cat_id: int = 0
var _barks_for_cat: int = 0
var _idle_bark_delay_left: float = 0.0
var patrol_enabled: bool = true
var _patrol_origin_x: float = 0.0
var _patrol_direction: float = -1.0
var _patrol_driving: bool = false
var _patrol_recovery_left: float = 0.0


func _ready() -> void:
	shield_active = _kind() == &"armored"
	_visual_phase = float(get_instance_id() % 997) * 0.061
	_idle_bark_delay_left = 0.7 + fmod(_visual_phase, 1.2)
	_patrol_origin_x = global_position.x
	if _kind() == &"jumper" and patrol_distance > 0.0 and patrol_speed > 0.0:
		can_sleep = false
	queue_redraw()


func is_sheltered() -> bool:
	# Keep protection until deferred destruction finishes, including the entire blast.
	return is_instance_valid(shelter)


func enter_shelter(house: DogHouse) -> void:
	if is_sheltered() or not is_instance_valid(house):
		return
	shelter = house
	_sheltered_layer = collision_layer
	_sheltered_mask = collision_mask
	_sheltered_z_index = z_index
	freeze = true
	collision_layer = 0
	collision_mask = 0
	z_index = house.z_index + 1
	_follow_shelter()
	house.destroyed.connect(leave_shelter)
	house.tree_exiting.connect(leave_shelter, CONNECT_ONE_SHOT)


func leave_shelter() -> void:
	if not is_sheltered():
		return
	_follow_shelter()
	var exit_velocity := shelter.linear_velocity
	if shelter.destroyed.is_connected(leave_shelter):
		shelter.destroyed.disconnect(leave_shelter)
	if shelter.tree_exiting.is_connected(leave_shelter):
		shelter.tree_exiting.disconnect(leave_shelter)
	shelter = null
	collision_layer = _sheltered_layer
	collision_mask = _sheltered_mask
	z_index = _sheltered_z_index
	freeze = false
	linear_velocity = exit_velocity
	_patrol_origin_x = global_position.x
	_patrol_recovery_left = 0.5
	sleeping = false
	_surprise_time_left = 0.45
	queue_redraw()


func _follow_shelter() -> void:
	global_position = shelter.to_global(shelter.dog_offset())
	global_rotation = shelter.global_rotation


func _process(delta: float) -> void:
	var previous_time := visual_time
	var previous_expression := expression
	visual_time += delta
	_surprise_time_left = maxf(0.0, _surprise_time_left - delta)
	_alert_time_left = maxf(0.0, _alert_time_left - delta)
	_bark_time_left = maxf(0.0, _bark_time_left - delta)
	_bark_cooldown_left = maxf(0.0, _bark_cooldown_left - delta)
	_alert_scan_left -= delta
	if _alert_scan_left <= 0.0:
		_alert_scan_left = 0.12
		_update_alert()
	_idle_bark_delay_left -= delta
	if _idle_bark_delay_left <= 0.0:
		_idle_bark_delay_left = 4.0 + fmod(_visual_phase, 4.0)
		if _alert_time_left <= 0.0 and _bark_time_left <= 0.0 and frost_time_left <= 0.0 and not is_destroyed and not is_queued_for_deletion():
			idle_bark_requested.emit()
	if _surprise_time_left > 0.0:
		expression = &"hit"
	elif _bark_time_left > 0.0:
		expression = &"bark"
	elif _alert_time_left > 0.0:
		expression = &"alert"
	else:
		expression = &"idle"
	if expression != previous_expression or HeroVisual.needs_redraw(previous_time, visual_time):
		queue_redraw()


func _update_alert() -> void:
	if is_destroyed or is_queued_for_deletion() or frost_time_left > 0.0 or not can_process():
		return
	for actor: Node in get_parent().get_children():
		var cat := actor as CatProjectile
		if cat == null or not cat.was_launched or cat.is_queued_for_deletion():
			continue
		var incoming := global_position - cat.global_position
		if incoming.length() < BARK_PROXIMITY and cat.linear_velocity.dot(incoming.normalized()) > 100.0:
			_alert_time_left = 0.24
			_request_bark(cat.get_instance_id())
			return


func _request_bark(cat_id: int) -> void:
	if _bark_cooldown_left > 0.0 or _bark_time_left > 0.0:
		return
	if _last_barked_cat_id != cat_id:
		_last_barked_cat_id = cat_id
		_barks_for_cat = 0
	if _barks_for_cat >= MAX_BARKS_PER_CAT:
		return
	_barks_for_cat += 1
	_bark_cooldown_left = bark_cooldown_seconds
	bark_requested.emit()
	# Отказ из-за mute/лимита голосов не становится отложенным хором.
	if _bark_time_left <= 0.0:
		_barks_for_cat = MAX_BARKS_PER_CAT


func show_bark(duration: float) -> void:
	if is_destroyed or is_queued_for_deletion():
		return
	_bark_time_left = duration
	if _surprise_time_left <= 0.0:
		expression = &"bark"
	queue_redraw()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_patrol_recovery_left = maxf(0.0, _patrol_recovery_left - delta)
	if is_sheltered():
		_follow_shelter()
		return
	if frost_time_left > 0.0:
		frost_time_left = maxf(0.0, frost_time_left - delta)
		if frost_time_left == 0.0 and not is_destroyed:
			freeze = _freeze_before_frost
			sleeping = false
	_jump_cooldown_left = maxf(0.0, _jump_cooldown_left - delta)
	_jump_ground_grace_left = maxf(0.0, _jump_ground_grace_left - delta)
	if _kind() != &"jumper" or is_destroyed or freeze or _age < spawn_grace_seconds:
		return
	if jumps_used >= MAX_JUMPS or _jump_cooldown_left > 0.0:
		return
	if absf(linear_velocity.y) > 35.0 or get_contact_count() == 0:
		return
	for actor: Node in get_parent().get_children():
		var cat := actor as CatProjectile
		if cat == null or not cat.was_launched or cat.is_queued_for_deletion():
			continue
		var incoming: Vector2 = global_position - cat.global_position
		if incoming.length() > JUMP_PROXIMITY:
			continue
		if cat.linear_velocity.dot(incoming.normalized()) < 150.0:
			continue
		jumps_used += 1
		_jump_cooldown_left = JUMP_COOLDOWN
		_jump_ground_grace_left = 0.9
		_surprise_time_left = 0.42
		expression = &"hit"
		sleeping = false
		apply_central_impulse(Vector2(0, -285.0) * mass)
		_show_burst(34.0, _accent_color(), 0.3, Vector2(0, RADIUS))
		return


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	_patrol_driving = false
	_update_patrol(state)
	super._integrate_forces(state)


func _update_patrol(state: PhysicsDirectBodyState2D) -> void:
	if _kind() != &"jumper" or not patrol_enabled or patrol_distance <= 0.0 or patrol_speed <= 0.0:
		return
	if is_destroyed or freeze or is_sheltered() or _age < spawn_grace_seconds:
		return
	# An impact or an evasive jump keeps its real momentum until it settles.
	if absf(state.linear_velocity.y) > 35.0 or absf(state.linear_velocity.x) > patrol_speed + 35.0 or absf(state.angular_velocity) > 3.0:
		_patrol_recovery_left = 0.5
	if _patrol_recovery_left > 0.0 or state.get_contact_count() == 0:
		return
	var origin := state.transform.origin
	# Patrol only solid ground. Moving structural supports keep ordinary physics.
	if not _patrol_has_ground(origin):
		return
	if (origin.x - _patrol_origin_x) * _patrol_direction >= patrol_distance:
		_patrol_direction *= -1.0
	if not _patrol_path_clear(origin, _patrol_direction):
		_patrol_direction *= -1.0
	var target_speed := patrol_speed * _patrol_direction if _patrol_path_clear(origin, _patrol_direction) else 0.0
	var velocity := state.linear_velocity
	velocity.x = move_toward(velocity.x, target_speed, 1200.0 * state.step)
	state.linear_velocity = velocity
	# The round body walks instead of rolling; knockback is handled above.
	state.angular_velocity = clampf(-state.transform.get_rotation() * 12.0, -2.0, 2.0)
	_patrol_driving = true


func _patrol_has_ground(origin: Vector2) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(origin, origin + Vector2(0, RADIUS + 12.0), 1, [get_rid()])
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.normal.y < -0.7


func _patrol_path_clear(origin: Vector2, direction: float) -> bool:
	var ahead := origin + Vector2(direction * (RADIUS + 12.0), 0)
	if not _patrol_has_ground(ahead):
		return false
	var ray := PhysicsRayQueryParameters2D.create(origin, ahead, 13, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(ray).is_empty()


func is_patrol_motion() -> bool:
	return _patrol_driving and patrol_enabled and not freeze and not is_destroyed and absf(linear_velocity.y) < 22.0 and absf(linear_velocity.x) <= patrol_speed + 1.0 and absf(angular_velocity) < 3.0


func apply_frost(duration: float) -> void:
	if is_destroyed or is_sheltered() or is_queued_for_deletion() or duration <= 0.0:
		return
	if frost_time_left <= 0.0:
		_freeze_before_frost = freeze
	frost_time_left = maxf(frost_time_left, duration)
	_bark_time_left = 0.0
	bark_interrupted.emit()
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	queue_redraw()


func receive_hit(strength: float) -> void:
	if is_sheltered() or not _can_receive_hit(strength):
		return
	if shield_active:
		shield_active = false
		_hit_cooldown_left = hit_cooldown_seconds
		impact_received.emit(strength)
		_surprise_time_left = 0.45
		expression = &"hit"
		queue_redraw()
		_show_burst.call_deferred(48.0, _accent_color(), 0.32, Vector2.ZERO)
		return
	super.receive_hit(strength)


func _show_defeat_effect() -> void:
	if not is_inside_tree() or get_parent().is_queued_for_deletion():
		return
	var echo := HeroHitEcho.new()
	echo.definition = definition
	echo.position = position
	echo.initial_rotation = rotation
	echo.drift_velocity = linear_velocity
	echo.visual_time = visual_time
	echo.phase = _visual_phase
	echo.z_index = 2
	get_parent().add_child(echo)


func _ignore_contact(collider: Object) -> bool:
	# A hop must not defeat its owner on landing; incoming cats/blocks still hurt.
	return (
		_jump_ground_grace_left > 0.0
		and collider is StaticBody2D
		and (collider.collision_layer & 1) != 0
	)


func _show_burst(radius: float, color: Color, lifetime: float, offset: Vector2) -> void:
	if not is_inside_tree():
		return
	var world := get_parent() as Node2D
	if world == null:
		return
	var burst := AbilityBurst.new()
	burst.position = world.to_local(global_position + offset)
	burst.radius = radius
	burst.color = color
	burst.lifetime = lifetime
	world.add_child(burst)


func _kind() -> StringName:
	return definition.id if definition != null else &"scout"


func _accent_color() -> Color:
	return definition.accent_color if definition != null else Color("72949a")


func _on_destroyed() -> void:
	# A single visual survives every defeat path; the physical target leaves now.
	_show_defeat_effect()
	defeated.emit()


func _draw() -> void:
	var fur := definition.fur_color if definition != null else Color("e9dfc3")
	var ear := definition.accent_color if definition != null else Color("95715a")
	var breath := sin(visual_time * 2.3 + _visual_phase) * 0.026
	var visual_scale := Vector2(1.0 + breath, 1.0 - breath)
	if expression == &"hit":
		visual_scale *= Vector2(0.95, 1.06)
	var tilt := sin(visual_time * 1.6 + _visual_phase) * 0.028
	draw_set_transform(Vector2(0, breath * 10.0), tilt, visual_scale)
	HeroVisual.paint(self, &"dog", _kind(), fur, ear, visual_time, _visual_phase, expression, shield_active)
	draw_set_transform(Vector2.ZERO)
	if frost_time_left > 0.0:
		draw_circle(Vector2.ZERO, RADIUS + 4.0, Color(0.5, 0.88, 1.0, 0.28))
		draw_arc(Vector2.ZERO, RADIUS + 5.0, 0.0, TAU, 32, Color("a2eeff"), 2.5, true)
		for index in range(6):
			var ray := Vector2.from_angle(float(index) * TAU / 6.0)
			draw_line(ray * 16.0, ray * 29.0, Color("d4faff"), 2.0, true)
