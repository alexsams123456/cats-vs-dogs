class_name AbilityBurst
extends Node2D

var radius: float = 155.0
var color: Color = Color("ffcb72")
var lifetime: float = 0.6
var kind: StringName = &""
var direction: Vector2 = Vector2.RIGHT

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress: float = clampf(_elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var expansion: float = 1.0 - pow(1.0 - progress, 3.0)
	var fade: float = 1.0 - progress
	var extent: float = maxf(radius, 1.0)
	var tint := Color(color, color.a * fade)
	var ring_radius: float = extent * lerpf(0.12, 1.0, expansion)
	if kind == &"wind":
		_draw_wind(extent, expansion, tint)
		return
	if kind == &"splitter" or kind == &"classic" or kind == &"heavy":
		_draw_rays(extent, expansion, tint)
		return
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, tint, 2.0 + 4.0 * fade, true)
	draw_circle(Vector2.ZERO, extent * 0.22 * fade, Color(color, color.a * fade * fade * 0.4))
	if kind == &"bomb":
		var flash := PackedVector2Array()
		for index in range(24):
			var length := ring_radius * (0.83 if index % 2 == 0 else 0.34)
			flash.append(Vector2.from_angle(TAU * float(index) / 24.0) * length)
		draw_colored_polygon(flash, Color(color.lightened(0.2), fade * 0.7))
		draw_circle(Vector2.ZERO, ring_radius * 0.31, Color(Color("fff6d9"), fade * 0.85))
	for index in range(12):
		var angle: float = TAU * float(index) / 12.0 + 0.12
		var radial := Vector2.from_angle(angle)
		var variation: float = 0.72 + float(index % 3) * 0.12
		var center: Vector2 = radial * extent * expansion * variation
		var puff_radius: float = extent * (0.027 + float(index % 2) * 0.016) * fade
		if kind == &"frost":
			_draw_snowflake(center, 7.0 + 8.0 * fade, tint)
			continue
		draw_circle(center, maxf(puff_radius, 0.1), tint)
		if index % 2 == 0:
			var trail: Vector2 = radial * extent * 0.1 * fade
			draw_line(center - trail, center, tint, 1.0 + 2.0 * fade, true)


func _draw_wind(extent: float, expansion: float, tint: Color) -> void:
	var forward := direction.normalized()
	var normal := forward.orthogonal()
	for index in range(5):
		var side := float(index - 2)
		var center := normal * side * extent * 0.19 + forward * extent * (expansion - 0.5)
		var points := PackedVector2Array()
		for step in range(13):
			var progress := float(step) / 12.0
			points.append(center + forward * (progress - 0.5) * extent * 0.8 + normal * sin(progress * TAU + side) * 10.0)
		draw_polyline(points, tint, 4.0, true)
		var tip := points[-1]
		draw_line(tip, tip - forward * 18.0 + normal * 11.0, tint, 4.0, true)
		draw_line(tip, tip - forward * 18.0 - normal * 11.0, tint, 4.0, true)


func _draw_rays(extent: float, expansion: float, tint: Color) -> void:
	for index in range(3):
		var angle := float(index - 1) * (0.42 if kind == &"splitter" else 0.16)
		var ray := direction.normalized().rotated(angle)
		var tip := ray * extent * lerpf(0.3, 1.0, expansion)
		draw_line(ray * extent * expansion * 0.12, tip, tint, 6.0, true)
		draw_circle(tip, 8.0 * tint.a, Color(color.lightened(0.55), tint.a))


func _draw_snowflake(center: Vector2, size: float, tint: Color) -> void:
	for index in range(6):
		var ray := Vector2.from_angle(float(index) * TAU / 6.0)
		var tip := center + ray * size
		draw_line(center, tip, tint, 2.4, true)
		for side in [-1.0, 1.0]:
			draw_line(tip, center + ray * size * 0.5 + ray.orthogonal() * size * side * 0.27, tint, 2.0, true)
