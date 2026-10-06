class_name ImpactBurst
extends Node2D
## Локальная вспышка и декоративные обломки: без коллизий и игрового RNG.

var intensity: float = 1.0
var material_id: StringName = &"wood"
var direction: Vector2 = Vector2.UP
var elapsed: float = 0.0
var lifetime: float = 0.38
var fragment_count: int = 12


func _ready() -> void:
	z_index = 6


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= lifetime:
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var progress := clampf(elapsed / lifetime, 0.0, 1.0)
	if progress >= 0.99:
		return
	var fade := 1.0 - progress
	var radius := lerpf(45.0, 86.0, intensity)
	var expansion := 1.0 - pow(fade, 3.0)
	var tint := _material_color()
	var ring := radius * lerpf(0.18, 1.0, expansion)
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 36, Color("fff2cc", fade * fade * 0.6), 1.0 + fade * 3.0, true)
	if progress < 0.28:
		_draw_flash(radius, 1.0 - progress / 0.28)
	for index in fragment_count:
		var angle := float(index) * TAU / float(fragment_count) + direction.angle()
		var radial := Vector2.from_angle(angle)
		var spread := 0.58 + float(index % 4) * 0.14
		var center := radial * radius * expansion * spread + Vector2.DOWN * 34.0 * progress * progress
		var size := (3.0 + float(index % 3)) * fade
		_draw_fragment(center, radial, size, Color(tint, fade * fade), index)


func _draw_flash(radius: float, opacity: float) -> void:
	var points := PackedVector2Array()
	for index in 16:
		var length := radius * (0.48 if index % 2 == 0 else 0.17) * (0.7 + opacity * 0.3)
		points.append(Vector2.from_angle(float(index) * TAU / 16.0) * length)
	draw_colored_polygon(points, Color("fff7dd", opacity * 0.85))
	draw_circle(Vector2.ZERO, radius * 0.11 * opacity, Color("ffffff", opacity))


func _draw_fragment(center: Vector2, radial: Vector2, size: float, tint: Color, index: int) -> void:
	var side := radial.orthogonal()
	match material_id:
		&"glass":
			draw_colored_polygon(PackedVector2Array([center + radial * size * 2.0, center + side * size, center - side * size - radial * size]), tint)
		&"metal":
			draw_line(center - radial * size * 2.8, center + radial * size, tint, 1.5, true)
			if index % 3 == 0:
				draw_line(center - side * size, center + side * size, tint, 1.2, true)
		&"stone", &"fur":
			draw_circle(center, size * 1.6, Color(tint, tint.a * 0.55))
			draw_circle(center + side * size, size * 0.7, tint)
		_:
			draw_colored_polygon(PackedVector2Array([center + radial * size * 2.0 + side * size * 0.5, center + radial * size * 2.0 - side * size * 0.5, center - radial * size * 2.0 - side * size * 0.5, center - radial * size * 2.0 + side * size * 0.5]), tint)


func _material_color() -> Color:
	match material_id:
		&"glass": return Color("9ce8ed")
		&"stone": return Color("b8b4a0")
		&"metal": return Color("ffcc64")
		&"fur": return Color("fff0cb")
	return Color("dfad6a")
