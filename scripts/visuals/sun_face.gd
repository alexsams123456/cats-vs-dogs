class_name SunFace
extends Node2D
## Лицо солнца: только рисунок; время задаёт владелец пейзажа.

const INK := Color("80522e")
const MOODS: Array[StringName] = [&"happy", &"focused", &"surprised", &"delighted", &"sad"]

var mood: StringName = &"happy"
var emotion: StringName:
	get:
		return _reaction if _reaction_left > 0.0 else mood
var gaze := Vector2(-0.6, 0.5)
var animation_time: float = 0.0
var _target_gaze := Vector2(-0.6, 0.5)
var _reaction: StringName = &"happy"
var _reaction_left: float = 0.0
var _smile: float = 1.0
var _mouth_open: float = 0.0
var _eye_height: float = 1.0
var _brow: float = 0.0


func focus_on(point: Vector2) -> void:
	_target_gaze = ((point - position) / Vector2(320, 260)).limit_length(1.0)


func set_mood(value: StringName) -> void:
	if value in MOODS:
		mood = value


func react(value: StringName, duration: float = 1.0) -> void:
	if value not in MOODS or duration <= 0.0:
		return
	_reaction = value
	_reaction_left = duration


func reset() -> void:
	mood = &"happy"
	_reaction = &"happy"
	_reaction_left = 0.0
	_smile = 1.0
	_mouth_open = 0.0
	_eye_height = 1.0
	_brow = 0.0
	animation_time = 0.0
	gaze = Vector2(-0.6, 0.5)
	_target_gaze = gaze
	queue_redraw()


func advance(delta: float) -> void:
	animation_time += delta
	_reaction_left = maxf(0.0, _reaction_left - delta)
	var expression := Vector4(1.0, 0.0, 1.0, 0.0)
	match emotion:
		&"focused":
			expression = Vector4(0.55, 0.0, 0.88, -0.5)
		&"surprised":
			expression = Vector4(0.0, 1.0, 1.15, 1.0)
		&"delighted":
			expression = Vector4(1.25, 0.75, 0.8, 0.65)
		&"sad":
			expression = Vector4(-0.65, 0.0, 0.85, -1.0)
	var blend := 1.0 - exp(-delta * 9.0)
	_smile = lerpf(_smile, expression.x, blend)
	_mouth_open = lerpf(_mouth_open, expression.y, blend)
	_eye_height = lerpf(_eye_height, expression.z, blend)
	_brow = lerpf(_brow, expression.w, blend)
	gaze = gaze.lerp(_target_gaze, 1.0 - exp(-delta * 7.0))
	queue_redraw()


func _draw() -> void:
	var breath := sin(animation_time * 0.48) * 1.5
	for layer in range(6, 0, -1):
		draw_circle(Vector2.ZERO, 46.0 + float(layer) * 11.0 + breath, Color(1.0, 0.93, 0.69, 0.025), true, -1.0, true)
	draw_circle(Vector2.ZERO, 47.0, Color("f9e8b4"), true, -1.0, true)
	draw_circle(Vector2(-2, -3), 43.0, Color("fff1c7"), true, -1.0, true)
	var blink_phase := fposmod(animation_time + 1.4, 4.8)
	var blink := 1.0
	if blink_phase > 4.6:
		blink = maxf(0.08, absf(blink_phase - 4.7) / 0.1)
	for side: float in [-1.0, 1.0]:
		var eye := Vector2(side * 14.0, -7.0)
		var eye_scale := Vector2(1.0, _eye_height * blink)
		draw_set_transform(eye, 0.0, eye_scale)
		draw_circle(Vector2.ZERO, 8.4, INK, true, -1.0, true)
		draw_circle(Vector2.ZERO, 6.9, Color("fffdf1"), true, -1.0, true)
		var pupil := gaze * 3.0
		draw_circle(pupil, 3.6, Color("553c2e"), true, -1.0, true)
		draw_circle(pupil + Vector2(-1.1, -1.2), 1.15, Color("ffffff"), true, -1.0, true)
		draw_set_transform(Vector2.ZERO)
		var brow_y := -21.0 - maxf(0.0, _brow) * 3.0
		var brow_tilt := minf(0.0, _brow) * 3.0
		_draw_curve(Vector2(side * 8.0, brow_y + brow_tilt), Vector2(side * 14.0, brow_y - 2.0), Vector2(side * 20.0, brow_y - brow_tilt * 0.3), INK, 2.1)
		draw_set_transform(Vector2(side * 25.0, 9.0), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 7.0, Color(0.92, 0.48, 0.26, 0.26), true, -1.0, true)
		draw_set_transform(Vector2.ZERO)
	_draw_mouth()


func _draw_mouth() -> void:
	var half_width := lerpf(15.0, 6.0, _mouth_open * (1.0 - clampf(_smile, 0.0, 1.0)))
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for index in 21:
		var along := float(index) / 20.0 * 2.0 - 1.0
		var curve := 1.0 - along * along
		var y := 13.0 + curve * _smile * 7.0
		top.append(Vector2(along * half_width, y - curve * _mouth_open * 3.0))
		bottom.append(Vector2(along * half_width, y + curve * _mouth_open * 10.0))
	if _mouth_open > 0.03:
		var outline := top.duplicate()
		bottom.reverse()
		outline.append_array(bottom)
		draw_colored_polygon(outline, INK)
		draw_polyline(outline, INK, 2.0, true)
		if _smile > 0.7:
			_draw_curve(Vector2(-6, 23), Vector2(0, 25), Vector2(6, 23), Color("e99572"), 3.0 * _mouth_open)
	draw_polyline(top, INK, 2.6, true)
	for tip: Vector2 in [top[0], top[top.size() - 1]]:
		draw_circle(tip, 1.3, INK, true, -1.0, true)


func _draw_curve(start: Vector2, middle: Vector2, end: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 13:
		var along := float(index) / 12.0
		points.append(start.lerp(middle, along).lerp(middle.lerp(end, along), along))
	draw_polyline(points, color, width, true)
