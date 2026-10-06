class_name BackgroundActivity
extends Node2D
## Небольшие фоновые сценки; все фазы задаёт общий приостанавливаемый счётчик.

const CABLE_START := Vector2(395, 345)
const CABLE_END := Vector2(942, 304)
const PENGUIN_COLOR := Color("7594a5")

var biome: StringName = &"backyard"
var animation_time: float = 0.0
var _cabin_styles: Array[StyleBoxFlat] = []
var _kite_shape := PackedVector2Array([Vector2(0, -25), Vector2(19, 0), Vector2(0, 29), Vector2(-19, 0)])


func _ready() -> void:
	for tint: Color in [Color("c6b496"), Color("9bbbbb")]:
		var style := StyleBoxFlat.new()
		style.bg_color = tint
		style.set_corner_radius_all(5)
		_cabin_styles.append(style)


func advance(elapsed: float, environment: StringName) -> void:
	animation_time = elapsed
	biome = environment
	queue_redraw()


func _draw() -> void:
	match biome:
		&"backyard":
			_draw_kite()
			_draw_chimney_smoke()
			_draw_swing()
			_draw_garden_bird()
		&"mountain":
			_draw_cable_cars()
			_draw_goats()
		&"glacier":
			_draw_penguins()


func _draw_kite() -> void:
	var center := Vector2(478, 186) + Vector2(sin(animation_time * 0.57) * 44, sin(animation_time * 0.89) * 17)
	var angle := sin(animation_time * 1.1) * 0.18
	var string := PackedVector2Array()
	for index in 21:
		var progress := float(index) / 20.0
		var point := center.lerp(Vector2(442, 400), progress)
		point.x += sin(progress * PI) * (20 + sin(animation_time * 1.3 - progress * 4) * 7)
		string.append(point)
	draw_polyline(string, Color(0.52, 0.62, 0.56, 0.34), 1, true)
	draw_set_transform(center, angle)
	draw_colored_polygon(_kite_shape, Color("dbaa99"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -25), Vector2(19, 0), Vector2.ZERO]), Color("e7d4a0"))
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(0, 29), Vector2(-19, 0)]), Color("a2bdb9"))
	draw_line(Vector2(0, -25), Vector2(0, 29), Color("f0dfb6"), 1, true)
	draw_line(Vector2(-19, 0), Vector2(19, 0), Color("f0dfb6"), 1, true)
	var tail := PackedVector2Array()
	for index in 17:
		var distance := float(index) * 4.0
		tail.append(Vector2(sin(animation_time * 2.3 - distance * 0.09) * distance * 0.17, 29 + distance))
	draw_polyline(tail, Color("b7ae90"), 1.2, true)
	for index in [3, 7, 11, 15]:
		var point := tail[index]
		var color := Color("c6b3ca") if index % 3 == 0 else Color("e5c591")
		draw_colored_polygon(PackedVector2Array([point, point + Vector2(-5, -3), point + Vector2(-5, 3)]), color)
		draw_colored_polygon(PackedVector2Array([point, point + Vector2(5, -3), point + Vector2(5, 3)]), color)
	draw_set_transform(Vector2.ZERO)


func _draw_chimney_smoke() -> void:
	for index in 5:
		var progress := fposmod(animation_time * 0.12 + float(index) / 5, 1.0)
		var center := Vector2(387, 294) + Vector2(progress * 33 + sin(animation_time * 0.8 + index) * progress * 9, -progress * 76)
		var alpha := sin(progress * PI) * 0.18
		_ellipse(center, Vector2(7 + progress * 16, 5 + progress * 9), Color(0.96, 0.94, 0.85, alpha))
		_ellipse(center + Vector2(8, -4), Vector2(6 + progress * 11, 5 + progress * 8), Color(0.96, 0.94, 0.85, alpha * 0.6))


func _draw_swing() -> void:
	var angle := sin(animation_time * 1.45) * 0.22
	draw_set_transform(Vector2(516, 472), angle)
	for side in [-1, 1]:
		draw_line(Vector2(side * 13, 0), Vector2(side * 13, 62), Color("9d9d7e"), 1.3, true)
	draw_line(Vector2(-17, 63), Vector2(17, 63), Color("ac9b7e"), 5, true)
	draw_line(Vector2(-15, 61), Vector2(15, 61), Color("d3bc96"), 2, true)
	draw_set_transform(Vector2.ZERO)


func _draw_garden_bird() -> void:
	var phase := fposmod(animation_time + 2, 12.0)
	var center := Vector2(120, 483)
	var flying := phase > 3 and phase < 10
	var facing := 1.0
	if flying:
		var progress := (phase - 3) / 7.0
		center += Vector2(sin(progress * PI) * 161, -sin(progress * PI) * 78)
		facing = 1.0 if progress < 0.5 else -1.0
	else:
		center.y -= maxf(0, sin(phase * 3.5)) * 3
	draw_set_transform(center, 0, Vector2(facing, 1))
	_ellipse(Vector2.ZERO, Vector2(9, 6), Color("92b5b8"))
	draw_circle(Vector2(7, -5), 5, Color("92b5b8"), true, -1, true)
	draw_circle(Vector2(9, -6), 1, Color("536f7b"), true, -1, true)
	draw_colored_polygon(PackedVector2Array([Vector2(11, -4), Vector2(17, -3), Vector2(11, -1)]), Color("d8bc7d"))
	var wing := sin(animation_time * 17) * 9 if flying else -2.0
	draw_line(Vector2(-2, -1), Vector2(-7, wing - 3), Color("6f98a4"), 4, true)
	draw_line(Vector2(-7, 1), Vector2(-15, -3), Color("6f98a4"), 3, true)
	if not flying:
		for x in [-3, 3]:
			draw_line(Vector2(x, 4), Vector2(x, 8), Color("a89675"), 1, true)
	draw_set_transform(Vector2.ZERO)


static func cable_point(progress: float) -> Vector2:
	return CABLE_START.lerp(CABLE_END, progress) + Vector2(0, sin(progress * PI) * 19)


func _draw_cable_cars() -> void:
	for index in 2:
		var phase := animation_time * 0.24 + float(index) * PI
		var progress := 0.04 + (0.5 - cos(phase) * 0.5) * 0.92
		var point := cable_point(progress)
		draw_line(point, point + Vector2(0, 13), Color("829a97"), 2, true)
		draw_set_transform(point + Vector2(0, 13), sin(animation_time * 1.6 + index) * 0.055)
		var tint := Color("c6b496") if index == 0 else Color("9bbbbb")
		draw_style_box(_cabin_styles[index], Rect2(-17, 0, 34, 26))
		draw_rect(Rect2(-12, 4, 10, 10), Color("d5e5df"))
		draw_rect(Rect2(2, 4, 10, 10), Color("d5e5df"))
		draw_line(Vector2(-19, 0), Vector2(19, 0), Color("819b97"), 3, true)
		draw_line(Vector2(-12, 21), Vector2(12, 21), tint.lightened(0.15), 2, true)
		draw_set_transform(Vector2.ZERO)


func _draw_goats() -> void:
	for index in 2:
		var phase := animation_time * 1.8 + float(index) * 2.4
		var center := Vector2(323 + index * 68, 533) + Vector2(sin(animation_time * 0.34 + index) * 20, -pow(maxf(0, sin(phase)), 2) * 11)
		var facing := 1.0 if cos(animation_time * 0.34 + index) >= 0 else -1.0
		draw_set_transform(center, sin(phase) * 0.04, Vector2(facing, 1) * 0.8)
		_ellipse(Vector2.ZERO, Vector2(15, 8), Color("cbd1bb"))
		for leg in 4:
			var x := -9.0 + leg * 6
			var step := sin(phase + float(leg % 2) * PI) * 3
			draw_line(Vector2(x, 5), Vector2(x + step, 15), Color("99ad9e"), 2.5, true)
		_ellipse(Vector2(13, -9), Vector2(6, 9), Color("cbd1bb"))
		draw_line(Vector2(12, -16), Vector2(8, -25), Color("93a59a"), 2, true)
		draw_line(Vector2(16, -16), Vector2(16, -25), Color("93a59a"), 2, true)
		draw_line(Vector2(11, -13), Vector2(4, -17), Color("b5c3ad"), 3, true)
		draw_circle(Vector2(16, -10), 1, Color("6e8986"), true, -1, true)
		draw_line(Vector2(-13, -2), Vector2(-21, -7), Color("cbd1bb"), 3, true)
		draw_set_transform(Vector2.ZERO)


func _draw_penguins() -> void:
	for index in 3:
		var phase := animation_time * 2.8 + float(index) * 1.9
		var center := Vector2(328 + index * 42, 553) + Vector2(sin(animation_time * 0.31 + index * 0.6) * 26, -absf(sin(phase)) * 2)
		_draw_penguin(center, sin(phase) * 0.12, 0.7 + float(index % 2) * 0.15, phase)
	# Четвёртый пингвин катается на животе по льду и оставляет исчезающий след.
	var phase := animation_time * 0.44
	var center := Vector2(741 + sin(phase) * 109, 591)
	var direction := 1.0 if cos(phase) >= 0 else -1.0
	for index in 5:
		var point := center + Vector2(-direction * (18 + index * 10), 3)
		draw_line(point, point - Vector2(direction * 6, 0), Color(0.92, 0.98, 1, 0.22 * (1 - float(index) / 5)), 1, true)
	draw_set_transform(center, direction * PI * 0.5, Vector2.ONE * 0.65)
	_draw_penguin_body(sin(animation_time * 6) * 4)
	draw_set_transform(Vector2.ZERO)


func _draw_penguin(center: Vector2, angle: float, size: float, phase: float) -> void:
	draw_set_transform(center + Vector2(0, 2), 0, Vector2(size, size * 0.23))
	draw_circle(Vector2.ZERO, 12, Color(0.4, 0.62, 0.73, 0.12), true, -1, true)
	draw_set_transform(center, angle, Vector2.ONE * size)
	for side in [-1, 1]:
		_ellipse(Vector2(side * 6, -1 + sin(phase + side) * 1.4), Vector2(5, 2.3), Color("c8b59a"))
	_draw_penguin_body(sin(phase) * 3)
	draw_set_transform(Vector2.ZERO)


func _draw_penguin_body(flipper: float) -> void:
	_ellipse(Vector2(0, -14), Vector2(11, 17), PENGUIN_COLOR)
	_ellipse(Vector2(0, -12), Vector2(7, 11), Color("e3eef0"))
	for side in [-1, 1]:
		draw_line(Vector2(side * 9, -21), Vector2(side * 15, -9 - flipper), PENGUIN_COLOR, 4, true)
		draw_circle(Vector2(side * 4, -25), 2, Color("eaf3f2"), true, -1, true)
		draw_circle(Vector2(side * 4, -25), 0.8, Color("547481"), true, -1, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-3, -21), Vector2(3, -21), Vector2(0, -17)]), Color("d7bd93"))


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	# Рисунок использует текущую локальную трансформацию героя.
	var points := PackedVector2Array()
	for index in 20:
		var angle := float(index) * TAU / 20
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
