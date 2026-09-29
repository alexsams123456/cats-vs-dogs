extends Node2D
## A hand-shaped tree whose cached drawing sways through its parent's clock.

var warm_foliage: bool = false


func _draw() -> void:
	var shade := Color("3d6c56") if not warm_foliage else Color("497155")
	var middle := Color("5d8559") if not warm_foliage else Color("71915d")
	var light := Color("88a66b") if not warm_foliage else Color("a3b779")
	_draw_blob(Vector2(2, -3), Vector2(63, 7), 0.0, Color(0.22, 0.37, 0.26, 0.18))
	_draw_branches()
	# Interlocking, asymmetrical lobes retain one legible crown silhouette.
	_draw_blob(Vector2(-13, -166), Vector2(96, 62), 0.7, shade)
	_draw_blob(Vector2(-76, -179), Vector2(50, 44), 1.8, shade)
	_draw_blob(Vector2(64, -161), Vector2(52, 43), 4.3, shade)
	_draw_blob(Vector2(40, -190), Vector2(68, 51), 2.0, middle)
	_draw_blob(Vector2(-39, -199), Vector2(73, 53), 0.3, middle)
	_draw_blob(Vector2(-72, -190), Vector2(47, 35), 2.1, Color("779761"))
	_draw_blob(Vector2(3, -218), Vector2(53, 35), 3.5, light)
	_draw_blob(Vector2(64, -190), Vector2(35, 26), 1.6, light.lerp(middle, 0.38))
	_draw_blob(Vector2(-42, -219), Vector2(44, 24), 2.3, light)
	_draw_blob(Vector2(-16, -169), Vector2(44, 25), 4.2, middle.lerp(light, 0.25))
	_draw_leaf_marks(light, middle)
	_draw_shrub(Vector2(-49, -7), 0.9, middle, light)
	_draw_shrub(Vector2(37, -3), 0.7, shade, middle)


func _draw_branches() -> void:
	var bark := Color("776950")
	var lit_bark := Color("a38c65")
	var trunk := PackedVector2Array([Vector2(-15, 0)])
	_append_curve(trunk, Vector2(-3, -45), Vector2(-20, -81), Vector2(-9, -124))
	_append_curve(trunk, Vector2(-4, -143), Vector2(-8, -159), Vector2(-12, -185))
	trunk.append(Vector2(-3, -187))
	_append_curve(trunk, Vector2(5, -151), Vector2(5, -131), Vector2(4, -111))
	_append_curve(trunk, Vector2(5, -64), Vector2(8, -24), Vector2(20, 0))
	draw_colored_polygon(trunk, bark)
	var light_strip := PackedVector2Array([Vector2(-11, -1)])
	_append_curve(light_strip, Vector2(-1, -50), Vector2(-14, -88), Vector2(-5, -124))
	light_strip.append(Vector2(-1, -121))
	_append_curve(light_strip, Vector2(-7, -79), Vector2(2, -32), Vector2(5, -1))
	draw_colored_polygon(light_strip, lit_bark)
	_draw_branch(Vector2(-1, -84), Vector2(-38, -122), Vector2(-57, -167), 12.0, bark)
	_draw_branch(Vector2(0, -111), Vector2(43, -129), Vector2(67, -176), 10.0, bark)
	_draw_branch(Vector2(-7, -132), Vector2(18, -160), Vector2(25, -204), 7.0, bark)
	draw_line(Vector2(-4, -62), Vector2(-1, -78), Color("685e4c"), 1.4, true)
	draw_line(Vector2(5, -22), Vector2(1, -46), Color("c0a77a"), 1.3, true)


func _draw_branch(root: Vector2, middle: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var points := PackedVector2Array()
	for step in 13:
		var t := float(step) / 12.0
		var center := root.lerp(middle, t).lerp(middle.lerp(tip, t), t)
		points.append(center + Vector2(-width * (1.0 - t) * 0.5, 0))
	for step in range(11, -1, -1):
		var t := float(step) / 12.0
		var center := root.lerp(middle, t).lerp(middle.lerp(tip, t), t)
		points.append(center + Vector2(width * (1.0 - t) * 0.5, 0))
	draw_colored_polygon(points, color)


func _draw_blob(center: Vector2, radius: Vector2, phase: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 72:
		var angle := float(index) * TAU / 72.0
		var edge := 1.0 + sin(angle * 5.0 + phase) * 0.067 + sin(angle * 9.0 - phase * 1.7) * 0.033
		points.append(center + Vector2(cos(angle), sin(angle)) * radius * edge)
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, color, 0.85, true)


func _draw_leaf_marks(light: Color, middle: Color) -> void:
	for index in 31:
		var x := -90.0 + fposmod(float(index) * 43.7, 179.0)
		var y := -227.0 + fposmod(float(index) * 27.1, 76.0)
		if Vector2(x / 103.0, (y + 191.0) / 55.0).length_squared() > 0.88:
			continue
		var tint := light.lerp(Color("c3ce8f"), 0.18) if index % 3 == 0 else middle.lerp(light, 0.5)
		draw_set_transform(Vector2(x, y), -0.7 + float(index % 4) * 0.42, Vector2(1.0, 0.47))
		draw_circle(Vector2.ZERO, 3.6 + float(index % 3), tint, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_shrub(root: Vector2, size: float, shade: Color, light: Color) -> void:
	_draw_blob(root + Vector2(0, -12) * size, Vector2(36, 21) * size, 1.1, shade)
	_draw_blob(root + Vector2(-10, -22) * size, Vector2(23, 16) * size, 2.6, light)
	_draw_blob(root + Vector2(18, -12) * size, Vector2(19, 15) * size, 1.7, light.lerp(shade, 0.28))


func _append_curve(points: PackedVector2Array, control_a: Vector2, control_b: Vector2, end: Vector2) -> void:
	var start := points[points.size() - 1]
	for step in range(1, 13):
		points.append(start.bezier_interpolate(control_a, control_b, end, float(step) / 12.0))
