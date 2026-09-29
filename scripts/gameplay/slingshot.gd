class_name Slingshot
extends Node2D
## Drag begins after GUI handling; an active pointer owns its release anywhere.

signal launched(projectile: CatProjectile)
signal tension_started

@export var max_pull: float = 105.0
@export var launch_speed: float = 8.5

const GRAB_RADIUS: float = 54.0
const MIN_PULL: float = 10.0
const NO_POINTER: int = -2
const MOUSE_POINTER: int = -1

var loaded_projectile: CatProjectile
var is_dragging: bool = false
var _enabled: bool = true
var _pointer_index: int = NO_POINTER
var _pull: Vector2 = Vector2.ZERO
var _tension_reported: bool = false


func load_projectile(projectile: CatProjectile) -> void:
	cancel_drag()
	loaded_projectile = projectile
	projectile.freeze = true
	projectile.linear_velocity = Vector2.ZERO
	projectile.angular_velocity = 0.0
	projectile.global_rotation = 0.0
	projectile.global_position = global_position
	projectile.set_aiming(false)
	queue_redraw()


func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		cancel_drag()
	queue_redraw()


func cancel_drag() -> void:
	is_dragging = false
	_tension_reported = false
	_pointer_index = NO_POINTER
	_pull = Vector2.ZERO
	if is_instance_valid(loaded_projectile):
		loaded_projectile.global_position = global_position
		loaded_projectile.set_aiming(false)
	queue_redraw()


func launch_from_pull(pull: Vector2) -> bool:
	if not _enabled or not is_instance_valid(loaded_projectile):
		return false
	var clamped_pull := pull.limit_length(max_pull)
	if clamped_pull.length() < MIN_PULL:
		cancel_drag()
		return false
	var projectile := loaded_projectile
	projectile.global_position = global_position + clamped_pull
	loaded_projectile = null
	is_dragging = false
	_tension_reported = false
	_pointer_index = NO_POINTER
	_pull = Vector2.ZERO
	projectile.launch(-clamped_pull * launch_speed)
	queue_redraw()
	launched.emit(projectile)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not _enabled or is_dragging or not is_instance_valid(loaded_projectile):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_begin_drag(event.position, MOUSE_POINTER)
	elif event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			_try_begin_drag(event.position, event.index)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not is_dragging:
		return
	if _pointer_index == MOUSE_POINTER:
		if event is InputEventMouseMotion:
			_update_drag(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				_update_drag(event.position)
				launch_from_pull(_pull)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _pointer_index:
		_update_drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == _pointer_index:
		if event.canceled:
			cancel_drag()
		elif not event.pressed:
			_update_drag(event.position)
			launch_from_pull(_pull)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_drag()


func _try_begin_drag(viewport_position: Vector2, pointer: int) -> void:
	var world_position := _viewport_to_world(viewport_position)
	if world_position.distance_to(loaded_projectile.global_position) > GRAB_RADIUS:
		return
	is_dragging = true
	_tension_reported = false
	loaded_projectile.set_aiming(true)
	_pointer_index = pointer
	_update_drag(viewport_position)
	get_viewport().set_input_as_handled()


func _update_drag(viewport_position: Vector2) -> void:
	if not is_instance_valid(loaded_projectile):
		cancel_drag()
		return
	_pull = (_viewport_to_world(viewport_position) - global_position).limit_length(max_pull)
	loaded_projectile.global_position = global_position + _pull
	if not _tension_reported and _pull.length() >= MIN_PULL:
		_tension_reported = true
		tension_started.emit()
	queue_redraw()


func _viewport_to_world(viewport_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_position


func _draw() -> void:
	var outline := Color("704b35")
	var wood := Color("b98149")
	# Wide silhouettes keep the fork legible on phone screens.
	_draw_branch(Vector2(2, 149), Vector2(0, 50), outline, wood, 22.0)
	_draw_branch(Vector2(0, 55), Vector2(-28, -9), outline, wood, 17.0)
	_draw_branch(Vector2(0, 55), Vector2(28, -9), outline, wood, 17.0)
	draw_line(Vector2(-5, 139), Vector2(-7, 72), Color("dda461"), 3.0, true)
	var pouch := _pull if is_instance_valid(loaded_projectile) else Vector2(0, 6)
	draw_line(Vector2(-28, -8), pouch, Color("765b4d"), 7.0, true)
	draw_line(Vector2(28, -8), pouch, Color("8e6950"), 7.0, true)
	draw_circle(Vector2(-28, -8), 5.0, Color("deb66d"))
	draw_circle(Vector2(28, -8), 5.0, Color("deb66d"))
	if is_dragging and _pull.length() >= MIN_PULL:
		var velocity := -_pull * launch_speed
		var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
		for index in range(1, 20):
			var time := index * 0.065
			var point := _pull + velocity * time + Vector2(0, 0.5 * gravity * time * time)
			point += loaded_projectile.trajectory_offset(time, velocity)
			var opacity := 0.75 * (1.0 - float(index) / 24.0)
			draw_circle(point, 4.0 - index * 0.09, Color(1.0, 0.98, 0.85, opacity))


func _draw_branch(from: Vector2, to: Vector2, outline: Color, wood: Color, width: float) -> void:
	draw_line(from, to, outline, width + 4.0, true)
	draw_circle(from, width * 0.5 + 2.0, outline)
	draw_circle(to, width * 0.5 + 2.0, outline)
	draw_line(from, to, wood, width, true)
	draw_circle(from, width * 0.5, wood)
	draw_circle(to, width * 0.5, wood)
