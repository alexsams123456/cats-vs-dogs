class_name MenuIcon
extends Control
## Small original menu symbols drawn in a shared 48-pixel coordinate space.

var kind: StringName = &"map":
	set(value):
		kind = value
		queue_redraw()
var color: Color = Color("28584c"):
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var icon_scale: float = minf(size.x, size.y) / 48.0
	if icon_scale <= 0.0:
		return
	draw_set_transform((size - Vector2.ONE * 48.0 * icon_scale) * 0.5, 0.0, Vector2.ONE * icon_scale)
	match kind:
		&"map":
			_draw_map()
		&"trophy":
			_draw_trophy()
		&"tools":
			_draw_tools()
		&"paw":
			_draw_paw()
		&"play":
			draw_colored_polygon(PackedVector2Array([Vector2(16, 9), Vector2(39, 24), Vector2(16, 39)]), color)
		&"star":
			_draw_star(Vector2(24, 24), 18.0, 8.3)
	draw_set_transform(Vector2.ZERO)


func _draw_map() -> void:
	var outline := PackedVector2Array([
		Vector2(6, 12), Vector2(18, 8), Vector2(30, 12), Vector2(42, 8),
		Vector2(42, 36), Vector2(30, 40), Vector2(18, 36), Vector2(6, 40), Vector2(6, 12),
	])
	draw_colored_polygon(outline, Color(color, 0.08))
	_stroke(outline)
	_stroke(PackedVector2Array([Vector2(18, 8), Vector2(18, 15)]), 1.6)
	_stroke(PackedVector2Array([Vector2(18, 31), Vector2(18, 36)]), 1.6)
	_stroke(PackedVector2Array([Vector2(30, 12), Vector2(30, 17)]), 1.6)
	_stroke(PackedVector2Array([Vector2(30, 30), Vector2(30, 40)]), 1.6)
	for point: Vector2 in [Vector2(12, 28), Vector2(17, 25), Vector2(22, 22), Vector2(27, 25), Vector2(32, 27)]:
		draw_circle(point, 1.65, color, true, -1.0, true)
	draw_circle(Vector2(36, 20), 4.2, color, false, 2.0, true)
	draw_circle(Vector2(36, 20), 1.3, color, true, -1.0, true)


func _draw_trophy() -> void:
	_stroke(PackedVector2Array([Vector2(14, 11), Vector2(7, 11), Vector2(7, 17), Vector2(9, 21), Vector2(15, 23)]))
	_stroke(PackedVector2Array([Vector2(34, 11), Vector2(41, 11), Vector2(41, 17), Vector2(39, 21), Vector2(33, 23)]))
	var cup := PackedVector2Array([
		Vector2(14, 8), Vector2(34, 8), Vector2(33, 22), Vector2(30, 27),
		Vector2(24, 30), Vector2(18, 27), Vector2(15, 22), Vector2(14, 8),
	])
	draw_colored_polygon(cup, Color(color, 0.12))
	_stroke(cup)
	_draw_star(Vector2(24, 18), 5.5, 2.6)
	_stroke(PackedVector2Array([Vector2(24, 30), Vector2(24, 36)]), 3.0)
	_stroke(PackedVector2Array([Vector2(17, 36), Vector2(31, 36), Vector2(34, 40), Vector2(14, 40), Vector2(17, 36)]))


func _draw_tools() -> void:
	var ruler := PackedVector2Array([
		Vector2(9, 10), Vector2(14, 6), Vector2(42, 34), Vector2(36, 40), Vector2(8, 12), Vector2(9, 10),
	])
	draw_colored_polygon(ruler, Color(color, 0.09))
	_stroke(ruler, 2.2)
	for index in 4:
		var start := Vector2(17 + index * 5, 10 + index * 5)
		_stroke(PackedVector2Array([start, start + Vector2(-2, 2)]), 1.7)
	var pencil := PackedVector2Array([
		Vector2(9, 30), Vector2(31, 8), Vector2(34, 7), Vector2(41, 14),
		Vector2(40, 17), Vector2(18, 39), Vector2(7, 41), Vector2(9, 30),
	])
	draw_colored_polygon(pencil, color)
	draw_line(Vector2(13, 31), Vector2(32, 12), Color("fff5dc"), 1.6, true)
	draw_colored_polygon(PackedVector2Array([Vector2(10, 33), Vector2(15, 38), Vector2(9, 39)]), Color("fff5dc"))


func _draw_paw() -> void:
	_ellipse(Vector2(10, 21), Vector2(4.7, 6.0), -0.40)
	_ellipse(Vector2(19, 13), Vector2(4.8, 6.5), -0.12)
	_ellipse(Vector2(30, 13), Vector2(4.8, 6.5), 0.12)
	_ellipse(Vector2(39, 21), Vector2(4.7, 6.0), 0.40)
	var pad := PackedVector2Array([
		Vector2(13, 29), Vector2(17, 25), Vector2(20, 22), Vector2(24, 21),
		Vector2(28, 22), Vector2(31, 25), Vector2(35, 29), Vector2(37, 34),
		Vector2(35, 39), Vector2(31, 41), Vector2(24, 39), Vector2(17, 41),
		Vector2(13, 39), Vector2(11, 34),
	])
	draw_colored_polygon(pad, color)


func _draw_star(center: Vector2, outer: float, inner: float) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle: float = -PI * 0.5 + PI * float(index) / 5.0
		var radius: float = outer if index % 2 == 0 else inner
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)


func _ellipse(center: Vector2, radius: Vector2, angle: float) -> void:
	var points := PackedVector2Array()
	for index in 24:
		var phase: float = TAU * float(index) / 24.0
		points.append(center + (Vector2(cos(phase), sin(phase)) * radius).rotated(angle))
	draw_colored_polygon(points, color)


func _stroke(points: PackedVector2Array, width: float = 2.4) -> void:
	draw_polyline(points, color, width, true)
	for point: Vector2 in points:
		draw_circle(point, width * 0.5, color, true, -1.0, true)
