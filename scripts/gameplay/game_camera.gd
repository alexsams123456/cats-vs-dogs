class_name GameCamera
extends Camera2D
## New touches pass through GUI first; an accepted gesture owns its remaining fingers.

signal aim_cancel_requested

@export_range(0.5, 1.0, 0.05) var min_zoom: float = 0.75
@export_range(1.0, 3.0, 0.1) var max_zoom: float = 2.0

const MIN_PINCH_DISTANCE: float = 16.0
const WHEEL_STEP: float = 1.15

var _touches: Dictionary[int, Vector2] = {}
var _pair: Array[int] = []
var _gesture_active: bool = false
var _last_center: Vector2
var _last_distance: float = 0.0
var _home_position: Vector2


func _ready() -> void:
	_home_position = position
	get_viewport().size_changed.connect(_on_viewport_resized)


func cancel_gesture() -> void:
	_touches.clear()
	_pair.clear()
	_gesture_active = false
	_last_distance = 0.0
	aim_cancel_requested.emit()


func reset_view() -> void:
	cancel_gesture()
	zoom = Vector2.ONE
	position = _home_position
	force_update_scroll()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _gesture_active:
			if event.index in _pair:
				_update_pinch()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and _touches.has(event.index):
		if not event.pressed or event.canceled:
			var was_gesture := _gesture_active
			_touches.erase(event.index)
			if event.index in _pair:
				_pair.clear()
				_select_pair()
			if _touches.is_empty():
				_gesture_active = false
			if was_gesture:
				get_viewport().set_input_as_handled()
	elif event is InputEventMouse and _gesture_active:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			if not _gesture_active:
				_gesture_active = true
				aim_cancel_requested.emit()
			_select_pair()
		if _gesture_active:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and _touches.is_empty():
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		var factor := 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			factor = WHEEL_STEP
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			factor = 1.0 / WHEEL_STEP
		else:
			return
		aim_cancel_requested.emit()
		_transform_view(event.position, event.position, factor)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_gesture()


func _select_pair() -> void:
	if _pair.size() == 2 or _touches.size() < 2:
		return
	for index: int in _touches:
		_pair.append(index)
		if _pair.size() == 2:
			break
	var first := _touches[_pair[0]]
	var second := _touches[_pair[1]]
	_last_center = (first + second) * 0.5
	_last_distance = first.distance_to(second)


func _update_pinch() -> void:
	if _pair.size() < 2:
		return
	var first := _touches[_pair[0]]
	var second := _touches[_pair[1]]
	var center := (first + second) * 0.5
	var distance := first.distance_to(second)
	# Nearly coincident fingers must not turn a tiny movement into a huge zoom.
	if _last_distance >= MIN_PINCH_DISTANCE and distance >= MIN_PINCH_DISTANCE:
		_transform_view(_last_center, center, distance / _last_distance)
	_last_center = center
	_last_distance = distance


func _transform_view(previous_center: Vector2, center: Vector2, factor: float) -> void:
	var world_anchor := get_canvas_transform().affine_inverse() * previous_center
	zoom = Vector2.ONE * clampf(zoom.x * factor, min_zoom, max_zoom)
	position = world_anchor - (center - get_viewport_rect().size * 0.5) / zoom.x
	_clamp_position()
	force_update_scroll()


func _clamp_position() -> void:
	# The widest view remains centered on the whole yard, for every aspect ratio.
	var viewport_half := get_viewport_rect().size * 0.5
	var travel := viewport_half / min_zoom - viewport_half / zoom.x
	position = position.clamp(_home_position - travel, _home_position + travel)


func _on_viewport_resized() -> void:
	cancel_gesture()
	_clamp_position()
	force_update_scroll()
