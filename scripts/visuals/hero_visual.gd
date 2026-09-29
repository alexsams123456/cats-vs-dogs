class_name HeroVisual
extends RefCounted
## Shared original hero art in local coordinates, with a body radius of 25 px.

const INK := Color("284448")
const CREAM := Color("fff5dc")
const WHITE := Color("fffefa")
const BLUSH := Color("e89b8b")
const GOLD := Color("ffd477")


static func paint(canvas: CanvasItem, species: StringName, kind: StringName, fur: Color, accent: Color, time: float, phase: float, expression: StringName = &"idle", shield: bool = false) -> void:
	var cat: bool = species == &"cat"
	var motion: float = sin(time * 2.8 + phase)
	_tail(canvas, fur, accent, time, phase, cat)
	if cat:
		_cat_cape(canvas, kind, accent, motion)
	_ears(canvas, fur, accent, time, phase, cat, expression)
	_ellipse(canvas, Vector2(0, 0.5), Vector2(24.5, 23.5), fur, true)
	_ellipse(canvas, Vector2(0, -10), Vector2(17, 11), fur.lightened(0.075))
	_ellipse(canvas, Vector2(0, 15), Vector2(19, 7.5), fur.darkened(0.075))
	if not cat:
		_ellipse(canvas, Vector2(-8.8, -3.2), Vector2(9.2, 10), accent.lerp(fur, 0.3))
	_markings(canvas, kind, accent, cat)
	_face(canvas, accent, time, phase, expression, cat)
	_accessories(canvas, kind, fur, accent, motion, cat, shield)
	if cat and kind == &"bomb":
		_fuse(canvas, time, phase)
	if expression == &"hit":
		for index in 3:
			var angle: float = -2.55 + float(index) * 0.95 + sin(time * 8.0 + phase) * 0.12
			_star(canvas, Vector2.from_angle(angle) * 32.0, 3.1, time * 2.0, GOLD)
	elif expression == &"alert" and not cat:
		canvas.draw_line(Vector2(29, -22), Vector2(30, -27), GOLD, 2.3, true)
		canvas.draw_circle(Vector2(28.5, -18.5), 1.3, GOLD)


static func _tail(canvas: CanvasItem, fur: Color, accent: Color, time: float, phase: float, cat: bool) -> void:
	var points := PackedVector2Array()
	var wag: float = sin(time * (3.7 if cat else 6.3) + phase)
	for index in 13:
		var part: float = float(index) / 12.0
		var point := Vector2(-18.0 - sin(part * PI * 0.75) * 14.0, 15.0 - part * 19.0)
		point.y += sin(part * PI) * 4.0 + wag * part * (2.0 if cat else 4.0)
		if not cat:
			point = Vector2(-19.0 - part * 13.0, 15.0 - part * 12.0 + wag * part * 3.0)
		points.append(point)
	canvas.draw_polyline(points, INK, 6.7, true)
	canvas.draw_polyline(points, fur, 4.4, true)
	canvas.draw_circle(points[points.size() - 1], 2.2, accent if cat else fur)


static func _ears(canvas: CanvasItem, fur: Color, accent: Color, time: float, phase: float, cat: bool, expression: StringName) -> void:
	for side in [-1.0, 1.0]:
		var twitch: float = _ear_twitch(time, phase, side)
		if cat:
			if expression == &"fly" or expression == &"meow":
				_polygon(canvas, [Vector2(side * 22, -10), Vector2(side * 30, -16), Vector2(side * 31, -20 + twitch), Vector2(side * 27, -23 + twitch), Vector2(side * 8, -22)], fur, true)
				_polygon(canvas, [Vector2(side * 22, -15), Vector2(side * 27, -19 + twitch), Vector2(side * 14, -21)], accent.lerp(BLUSH, 0.6))
			else:
				var forward: float = 2.5 if expression == &"aim" else 0.0
				var swivel: float = twitch * side * 0.65
				_polygon(canvas, [Vector2(side * 22, -10), Vector2(side * 24, -24), Vector2(side * 23 + forward + swivel, -32 + twitch - forward), Vector2(side * 20 + forward + swivel, -33 + twitch - forward), Vector2(side * 8, -22)], fur, true)
				_polygon(canvas, [Vector2(side * 19.5, -16), Vector2(side * 20.5 + forward + swivel, -28 + twitch - forward), Vector2(side * 12, -21)], accent.lerp(BLUSH, 0.6))
		else:
			var center := Vector2(side * (23 + twitch * 0.3), -5.0 + twitch)
			_ellipse(canvas, center, Vector2(7.7, 16), accent.lerp(fur, 0.25), true)
			_ellipse(canvas, center + Vector2(side * 1.0, 3), Vector2(3.8, 9), accent.lerp(fur, 0.48))


static func _markings(canvas: CanvasItem, kind: StringName, accent: Color, cat: bool) -> void:
	if cat and kind == &"classic":
		for index in 3:
			var x: float = float(index - 1) * 6.0
			canvas.draw_line(Vector2(x, -21), Vector2(x * 0.7, -14), accent, 2.5, true)
		for side in [-1.0, 1.0]:
			canvas.draw_line(Vector2(side * 22, 0), Vector2(side * 18, 1), accent, 1.8, true)
	elif cat and kind == &"zigzag":
		_polygon(canvas, [Vector2(-1, -23), Vector2(-6, -15), Vector2(-1, -15), Vector2(-3, -10), Vector2(6, -19), Vector2(1, -19)], GOLD)
	elif cat and kind == &"splitter":
		_ellipse(canvas, Vector2(-17, -8), Vector2(6, 10), accent.lightened(0.22))
		_ellipse(canvas, Vector2(17, -8), Vector2(6, 10), GOLD)
		for index in 3:
			canvas.draw_circle(Vector2(float(index - 1) * 6.0, -19), 2.3, accent)
	elif cat and kind == &"frost":
		_snowflake(canvas, Vector2(0, -18), 5.5, WHITE)
		for side in [-1.0, 1.0]:
			canvas.draw_circle(Vector2(side * 20, 0), 1.5, WHITE)
			canvas.draw_circle(Vector2(side * 18, -7), 1.0, WHITE)
	elif not cat and kind == &"armored":
		_polygon(canvas, [Vector2(-19, -17), Vector2(-16, -23), Vector2(16, -23), Vector2(19, -17)], Color("a8c0c7"), true)
		canvas.draw_line(Vector2(-14, -21), Vector2(14, -21), Color("e0efea"), 1.0, true)
		for side in [-1.0, 1.0]:
			canvas.draw_circle(Vector2(side * 14, -19.5), 1.1, CREAM)


static func _face(canvas: CanvasItem, accent: Color, time: float, phase: float, expression: StringName, cat: bool) -> void:
	var blink: float = _blink(time, phase)
	var smile: float = _idle_smile(time, phase) if expression == &"idle" else 0.0
	var gaze := Vector2(sin(time * 1.25 + phase) * 0.85, 0.3 - smile * 0.25)
	blink *= 1.0 - smile * 0.18
	if expression == &"aim":
		blink *= 0.7
		gaze = Vector2(1.2, 0.3)
	elif expression == &"fly":
		gaze = Vector2(1.0, -0.6)
	elif expression == &"alert":
		gaze = Vector2(-1.2, -0.6)
	elif expression == &"hit":
		blink = 1.0
	elif expression == &"defeated":
		blink = 1.0
		gaze = Vector2.from_angle(time * 10.0 + phase)
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * 8.5, -3.4)
		_eye(canvas, eye, accent, gaze, blink, expression)
		_ellipse(canvas, Vector2(side * 15.6, 7.7 - smile * 0.6), Vector2(4.6, 2.8), Color(BLUSH, 0.42 + smile * 0.16))
		if expression == &"aim":
			canvas.draw_line(eye + Vector2(-4, -8.0 - side), eye + Vector2(4, -8.0 + side), INK, 1.25, true)
		else:
			canvas.draw_arc(eye + Vector2(0, -6.4 - smile * 0.8), 4.5, 3.8, 5.5, 8, INK, 1.1, true)
	if cat:
		_ellipse(canvas, Vector2(-5, 10.5), Vector2(7, 5.2), CREAM)
		_ellipse(canvas, Vector2(5, 10.5), Vector2(7, 5.2), CREAM)
		_polygon(canvas, [Vector2(-3.2, 5.6), Vector2(3.2, 5.6), Vector2(0, 8.7)], INK)
		canvas.draw_line(Vector2(-1.4, 6), Vector2(0.5, 6), BLUSH, 0.8, true)
		for side in [-1.0, 1.0]:
			canvas.draw_line(Vector2(side * 14.5, 9.8), Vector2(side * 26.5, 7.2), INK, 0.9, true)
			canvas.draw_line(Vector2(side * 15, 13), Vector2(side * 26, 14.5), INK, 0.9, true)
	else:
		_ellipse(canvas, Vector2(0, 10.5), Vector2(13.2, 8.9), CREAM)
		_ellipse(canvas, Vector2(0, 5.5), Vector2(4.9, 3.5), INK)
		_ellipse(canvas, Vector2(-1.2, 4.5), Vector2(1.7, 0.75), Color("69848a"))
	_mouth(canvas, expression, cat, smile)


static func _eye(canvas: CanvasItem, center: Vector2, accent: Color, gaze: Vector2, blink: float, expression: StringName) -> void:
	if expression == &"defeated":
		_ellipse(canvas, center, Vector2(6.5, 7.0), WHITE, true)
		var spiral := PackedVector2Array()
		for index in 25:
			var part: float = float(index) / 24.0
			var angle: float = part * TAU * 1.55 + gaze.angle()
			spiral.append(center + Vector2.from_angle(angle) * (0.3 + part * 4.4))
		canvas.draw_polyline(spiral, INK, 1.25, true)
		return
	if blink < 0.16:
		canvas.draw_arc(center + Vector2(0, -2), 4.8, 0.2, PI - 0.2, 10, INK, 1.4, true)
		return
	_ellipse(canvas, center, Vector2(6.1, 7.0 * blink), WHITE, true)
	var pupil: float = 2.7 if expression == &"hit" else 3.65
	var eye_center: Vector2 = center + gaze * Vector2(1, blink)
	_ellipse(canvas, eye_center, Vector2(pupil + 0.65, (pupil + 1.1) * blink), accent.darkened(0.22))
	_ellipse(canvas, eye_center, Vector2(pupil, (pupil + 0.65) * blink), INK)
	_ellipse(canvas, eye_center + Vector2(-1.1, -1.8 * blink), Vector2(1.5, 1.5 * blink), WHITE)
	_ellipse(canvas, eye_center + Vector2(1.7, 1.4 * blink), Vector2(0.65, 0.65 * blink), WHITE)


static func _mouth(canvas: CanvasItem, expression: StringName, cat: bool, smile: float) -> void:
	var y: float = 11.5 if cat else 12.7
	canvas.draw_line(Vector2(0, 8), Vector2(0, y), INK, 1.05, true)
	if expression == &"hit":
		_ellipse(canvas, Vector2(0, y + 2.5), Vector2(3.0, 4.0), INK)
	elif expression == &"defeated":
		canvas.draw_arc(Vector2(0, y - 0.5), 3.8, 0.0, PI, 12, INK, 1.3, true)
		_ellipse(canvas, Vector2(2.5, y + 3.4), Vector2(2.3, 3.0), BLUSH)
		canvas.draw_line(Vector2(2.7, y + 1.3), Vector2(2.7, y + 3.6), BLUSH.darkened(0.16), 0.8, true)
	elif expression == &"meow" or expression == &"fly" or expression == &"bark":
		_ellipse(canvas, Vector2(0, y + 2), Vector2(4.9, 4.3), INK)
		_ellipse(canvas, Vector2(0, y + 4), Vector2(3.2, 1.9), BLUSH)
		if expression == &"fly":
			canvas.draw_line(Vector2(-2.6, y - 0.6), Vector2(2.6, y - 0.6), WHITE, 1.4, true)
		elif expression == &"bark":
			for side in [-1.0, 1.0]:
				canvas.draw_line(Vector2(side * 29, y - 3), Vector2(side * 34, y - 5), GOLD, 2.0, true)
				canvas.draw_line(Vector2(side * 30, y + 3), Vector2(side * 36, y + 4), GOLD, 2.0, true)
	else:
		canvas.draw_arc(Vector2(-3.5, y - 1), 3.5, 0.0, PI * 0.83, 10, INK, 1.1, true)
		canvas.draw_arc(Vector2(3.5, y - 1), 3.5, PI * 0.17, PI, 10, INK, 1.1, true)
		if smile > 0.01:
			_ellipse(canvas, Vector2(0, y + 1.8), Vector2(6.5, 3.5) * smile, INK)
			_ellipse(canvas, Vector2(0, y + 1.8 + smile * 1.7), Vector2(3.8, 1.3) * smile, BLUSH)


static func _accessories(canvas: CanvasItem, kind: StringName, fur: Color, accent: Color, motion: float, cat: bool, shield: bool) -> void:
	if cat:
		_cat_headgear(canvas, kind, fur, accent, motion)
		_polygon(canvas, [Vector2(-16, 19), Vector2(16, 19), Vector2(5, 29), Vector2(-3, 27)], accent, true)
		_polygon(canvas, [Vector2(12, 20), Vector2(27, 18 + motion), Vector2(24, 24 + motion), Vector2(16, 25)], accent, true)
		_cat_badge(canvas, kind)
		if kind == &"frost":
			for index in 7:
				canvas.draw_circle(Vector2(-12.0 + float(index) * 4.0, 20), 2.5, WHITE)
	else:
		canvas.draw_line(Vector2(-15, 21), Vector2(15, 21), INK, 5.5, true)
		canvas.draw_line(Vector2(-15, 21), Vector2(15, 21), accent, 3.7, true)
		if kind == &"jumper":
			_polygon(canvas, [Vector2(-15, 19), Vector2(15, 19), Vector2(0, 31)], accent, true)
			_polygon(canvas, [Vector2(13, 20), Vector2(26, 17 + motion), Vector2(23, 26 + motion)], accent, true)
			_star(canvas, Vector2(0, 23.5), 2.4, 0.0, CREAM)
		else:
			canvas.draw_circle(Vector2(0, 25), 4.0, INK)
			canvas.draw_circle(Vector2(0, 25), 3.2, GOLD)
			canvas.draw_circle(Vector2(-0.8, 24), 1.0, CREAM)
	for side in [-1.0, 1.0]:
		var paw := Vector2(side * 15, 21.5 + (motion * side * 0.4 if kind == &"jumper" else 0.0))
		_ellipse(canvas, paw, Vector2(6.3, 4.5), fur.lightened(0.1), true)
		for offset in [-1.4, 1.4]:
			canvas.draw_line(paw + Vector2(offset, 1.3), paw + Vector2(offset, 3.3), fur.darkened(0.3), 0.8, true)
	if not cat and kind == &"armored" and shield:
		_polygon(canvas, [Vector2(22, 8), Vector2(32, 12), Vector2(30, 25), Vector2(22, 32), Vector2(14, 25), Vector2(12, 12)], accent, true)
		_polygon(canvas, [Vector2(22, 11), Vector2(28.5, 14), Vector2(27, 23), Vector2(22, 27.8), Vector2(17, 23), Vector2(15.5, 14)], accent.lightened(0.27), true)
		canvas.draw_polyline(PackedVector2Array([Vector2(18, 19), Vector2(21, 22), Vector2(26, 16)]), CREAM, 1.8, true)


static func _cat_cape(canvas: CanvasItem, kind: StringName, accent: Color, motion: float) -> void:
	if kind == &"ghost":
		_polygon(canvas, [Vector2(-18, -18), Vector2(-26, 4), Vector2(-30, 27 + motion), Vector2(-17, 24), Vector2(-8, 30), Vector2(4, 25), Vector2(21, 28 - motion), Vector2(24, 2), Vector2(16, -18)], accent.darkened(0.12), true)
	elif kind == &"wind":
		_polygon(canvas, [Vector2(17, 14), Vector2(37, 8 + motion * 2), Vector2(32, 16 + motion * 2), Vector2(39, 20 + motion), Vector2(18, 23)], accent, true)


static func _cat_headgear(canvas: CanvasItem, kind: StringName, fur: Color, accent: Color, motion: float) -> void:
	match kind:
		&"heavy":
			_polygon(canvas, [Vector2(-23, -14), Vector2(-20, -24), Vector2(-11, -29), Vector2(11, -29), Vector2(20, -24), Vector2(23, -14)], accent, true)
			_polygon(canvas, [Vector2(-12, -27), Vector2(-5, -27), Vector2(-7, -17), Vector2(-17, -17)], accent.lightened(0.23))
			canvas.draw_line(Vector2(-24, -14), Vector2(24, -14), INK, 3.3, true)
			canvas.draw_polyline(PackedVector2Array([Vector2(9, -27), Vector2(5, -22), Vector2(9, -19)]), accent.darkened(0.3), 1.6, true)
		&"wind":
			var tip := Vector2(8 + motion, -37)
			_polygon(canvas, [Vector2(-4, -20), Vector2(-5, -30), tip, Vector2(13, -28), Vector2(6, -22)], CREAM, true)
			canvas.draw_line(Vector2(-4, -19), tip, accent, 1.5, true)
			canvas.draw_line(Vector2(-1, -25), Vector2(6, -25), accent, 1.1, true)
			canvas.draw_line(Vector2(2, -30), Vector2(9, -29), accent, 1.1, true)
		&"magnet":
			var horseshoe := PackedVector2Array([Vector2(-6, -25), Vector2(-6, -20), Vector2(-3, -17), Vector2(3, -17), Vector2(6, -20), Vector2(6, -25)])
			canvas.draw_polyline(horseshoe, INK, 6.3, true)
			canvas.draw_polyline(horseshoe, accent, 4.3, true)
			for side in [-1.0, 1.0]:
				canvas.draw_line(Vector2(side * 6, -25), Vector2(side * 6, -22), WHITE, 4.3, true)
		&"ghost":
			canvas.draw_arc(Vector2(0, -1), 25, PI + 0.5, TAU - 0.5, 28, accent, 5.2, true)
			canvas.draw_circle(Vector2(0, -18), 4.5, CREAM)
			canvas.draw_circle(Vector2(2.3, -19.5), 3.8, fur.lightened(0.075))
		&"homing":
			canvas.draw_line(Vector2(-22, -20), Vector2(22, -20), accent.darkened(0.18), 4.0, true)
			for side in [-1.0, 1.0]:
				_ellipse(canvas, Vector2(side * 8, -20), Vector2(6.2, 5.2), GOLD, true)
				_ellipse(canvas, Vector2(side * 8, -20), Vector2(4.4, 3.5), Color("9be1e4"), true)
				canvas.draw_line(Vector2(side * 8 - 2, -21), Vector2(side * 8 + 1, -22), WHITE, 1.0, true)
			canvas.draw_line(Vector2(-2, -20), Vector2(2, -20), INK, 1.5, true)


static func _cat_badge(canvas: CanvasItem, kind: StringName) -> void:
	match kind:
		&"classic", &"homing":
			_polygon(canvas, [Vector2(-3, 22), Vector2(1, 22), Vector2(1, 20), Vector2(5, 23), Vector2(1, 26), Vector2(1, 24), Vector2(-3, 24)], CREAM)
		&"zigzag":
			_polygon(canvas, [Vector2(1, 20), Vector2(-3, 24), Vector2(0, 24), Vector2(-1, 27), Vector2(5, 22), Vector2(2, 22)], GOLD)
		&"bomb":
			canvas.draw_circle(Vector2(1, 23), 2.3, GOLD)
			canvas.draw_line(Vector2(1, 21), Vector2(2.5, 19.5), CREAM, 1.0, true)
		&"splitter":
			for point in [Vector2(-2, 22), Vector2(4, 22), Vector2(1, 26)]:
				canvas.draw_circle(point, 1.5, CREAM)
		&"heavy":
			_polygon(canvas, [Vector2(-1, 20), Vector2(3, 20), Vector2(3, 23), Vector2(5, 23), Vector2(1, 27), Vector2(-3, 23), Vector2(-1, 23)], CREAM)
		&"wind":
			canvas.draw_arc(Vector2(1, 23), 2.5, PI * 0.6, TAU * 1.15, 14, CREAM, 1.2, true)
		&"magnet":
			canvas.draw_line(Vector2(-2, 23), Vector2(3, 23), CREAM, 1.4, true)
			canvas.draw_line(Vector2(0.5, 20.5), Vector2(0.5, 25.5), CREAM, 1.4, true)
		&"frost":
			_snowflake(canvas, Vector2(1, 25), 2.6, WHITE)
		&"ghost":
			_star(canvas, Vector2(1, 23), 3.4, 0.0, CREAM)


static func _snowflake(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	for index in 6:
		var ray: Vector2 = Vector2.from_angle(float(index) * TAU / 6.0 - PI * 0.5)
		var tip: Vector2 = center + ray * radius
		canvas.draw_line(center, tip, color, 1.2, true)
		if radius > 4.0:
			for side in [-1.0, 1.0]:
				canvas.draw_line(center + ray * radius * 0.58, tip + ray.rotated(side * PI * 0.5) * radius * 0.28, color, 1.0, true)


static func _fuse(canvas: CanvasItem, time: float, phase: float) -> void:
	var spark := Vector2(12.5, -31.5 + sin(time * 3.0 + phase) * 0.5)
	canvas.draw_polyline(PackedVector2Array([Vector2(1, -22), Vector2(3, -29), Vector2(8, -32), spark]), INK, 2.6, true)
	canvas.draw_polyline(PackedVector2Array([Vector2(1, -22), Vector2(3, -29), Vector2(8, -32), spark]), CREAM, 1.1, true)
	_star(canvas, spark, 3.7 + sin(time * 14.0 + phase) * 0.6, time * 0.8, GOLD)
	canvas.draw_circle(spark, 1.5, WHITE)


static func _blink(time: float, phase: float) -> float:
	# A short blink every 1.8–2.4 seconds; every third one is a double blink.
	var interval: float = 2.1 + sin(phase * 1.7) * 0.3
	var cycle: float = fposmod(time + phase, interval * 3.0)
	var blink_time: float = fposmod(cycle, interval)
	if cycle >= interval * 2.0 and blink_time >= 0.30 and blink_time < 0.48:
		blink_time -= 0.30
	if blink_time >= 0.18:
		return 1.0
	return maxf(0.03, 1.0 - sin(blink_time / 0.18 * PI))


static func _idle_smile(time: float, phase: float) -> float:
	var interval: float = 3.3 + sin(phase * 0.9) * 0.35
	var cycle: float = fposmod(time + phase * 1.3, interval)
	return smoothstep(0.2, 0.48, cycle) * (1.0 - smoothstep(1.12, 1.5, cycle))


static func _ear_twitch(time: float, phase: float, side: float) -> float:
	var interval: float = 2.4 + sin(phase + side) * 0.3
	var cycle: float = fposmod(time + phase + side * 0.43, interval)
	var motion: float = sin(time * 3.6 + phase + side * 0.7) * 0.8
	if cycle < 0.55:
		motion += sin(cycle / 0.55 * TAU) * sin(cycle / 0.55 * PI) * 3.6
	return motion


static func _ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color, outlined: bool = false) -> void:
	var points := PackedVector2Array()
	var count: int = 40 if radius.x > 10.0 else 16
	for index in count:
		var angle: float = TAU * float(index) / float(count)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_colored_polygon(points, color)
	if outlined:
		points.append(points[0])
		canvas.draw_polyline(points, INK, 1.3, true)


static func _polygon(canvas: CanvasItem, vertices: Array[Vector2], color: Color, outlined: bool = false) -> void:
	var points := PackedVector2Array(vertices)
	canvas.draw_colored_polygon(points, color)
	if outlined:
		points.append(points[0])
		canvas.draw_polyline(points, INK, 1.3, true)


static func _star(canvas: CanvasItem, center: Vector2, radius: float, rotation: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 8:
		var angle: float = float(index) * TAU / 8.0 + rotation
		points.append(center + Vector2.from_angle(angle) * radius * (1.0 if index % 2 == 0 else 0.35))
	canvas.draw_colored_polygon(points, color)
