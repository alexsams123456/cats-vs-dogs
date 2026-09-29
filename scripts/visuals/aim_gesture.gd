extends Node2D
## Наглядный первый жест; рисунок следует рогатке и не получает ввод.

const FIRST_DELAY: float = 0.7
const RETURN_DELAY: float = 1.4
const CYCLE_TIME: float = 3.6
const DEMO_PULL := Vector2(-76.0, 32.0)
const INK := Color("5d594f")
const CREAM := Color("fff5d9")

var visual_time: float = 0.0
var _slingshot: Slingshot
var _enabled: bool = false
var _focused: bool = true
var _delay_left: float = FIRST_DELAY


func _ready() -> void:
	_slingshot = get_parent() as Slingshot
	z_index = 12
	visible = false
	set_process(false)
	_slingshot.tension_started.connect(_hide_and_wait)


func set_enabled(value: bool) -> void:
	if value == _enabled:
		return
	_enabled = value
	visual_time = 0.0
	_delay_left = FIRST_DELAY
	visible = false
	set_process(value)


func _process(delta: float) -> void:
	if not _focused or not _slingshot.is_visible_in_tree() or _slingshot.is_dragging or not is_instance_valid(_slingshot.loaded_projectile):
		_hide_and_wait()
		return
	if _delay_left > 0.0:
		_delay_left = maxf(0.0, _delay_left - delta)
		return
	visible = true
	visual_time = fmod(visual_time + delta, CYCLE_TIME)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_hide_and_wait()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_focused = false
		_hide_and_wait()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_focused = true


func _hide_and_wait() -> void:
	visible = false
	visual_time = 0.0
	_delay_left = RETURN_DELAY


func _draw() -> void:
	# Подсказка только показывает жест: кот и тетива остаются неподвижными.
	var pull_progress := smoothstep(0.55, 1.85, visual_time)
	var release_progress := smoothstep(2.15, 2.7, visual_time)
	var opacity := smoothstep(0.0, 0.22, visual_time) * (1.0 - smoothstep(2.55, 3.1, visual_time))
	var tip := DEMO_PULL * pull_progress + Vector2(4.0, -24.0) * release_progress
	var line_color := Color(CREAM, opacity * 0.66)
	for index in range(1, 7):
		var point := DEMO_PULL * float(index) / 7.0
		draw_circle(point, 2.5, line_color)
	if visual_time < 0.8:
		var pulse := clampf(visual_time / 0.8, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 12.0 + pulse * 12.0, 0.0, TAU, 32, Color(CREAM, opacity * (1.0 - pulse)), 3.0, true)
	if release_progress > 0.0:
		draw_arc(DEMO_PULL, 10.0 + release_progress * 16.0, 0.0, TAU, 32, Color(CREAM, opacity * (1.0 - release_progress)), 3.0, true)
	_draw_hand(tip, opacity)


func _draw_hand(tip: Vector2, opacity: float) -> void:
	var points := PackedVector2Array([
		Vector2(-4, 25), Vector2(-4, 3), Vector2(-2, -1), Vector2(2, -2),
		Vector2(6, 1), Vector2(8, 18), Vector2(12, 14), Vector2(17, 15),
		Vector2(20, 19), Vector2(24, 18), Vector2(29, 22), Vector2(33, 23),
		Vector2(35, 29), Vector2(32, 42), Vector2(12, 45), Vector2(7, 39),
		Vector2(-6, 33), Vector2(-11, 27), Vector2(-10, 22), Vector2(-6, 22),
	])
	draw_set_transform(tip)
	draw_colored_polygon(points, Color(CREAM, opacity * 0.95))
	points.append(points[0])
	draw_polyline(points, Color(INK, opacity), 2.4, true)
	draw_line(Vector2(8, 19), Vector2(10, 29), Color(INK, opacity * 0.75), 1.7, true)
	draw_line(Vector2(18, 20), Vector2(20, 29), Color(INK, opacity * 0.75), 1.7, true)
	draw_line(Vector2(27, 24), Vector2(27, 30), Color(INK, opacity * 0.75), 1.7, true)
	draw_set_transform(Vector2.ZERO)
