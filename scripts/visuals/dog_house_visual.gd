class_name DogHouseVisual
extends RefCounted
## Original silhouettes shared by physical shelters and editor previews.

const DOOR_COLOR := Color("293d3d")
const SIGN_COLOR := Color("fff1ca")


static func paint(canvas: CanvasItem, material_id: StringName, damage: float = 0.0, house_type: StringName = &"classic") -> void:
	var material := BlockMaterials.get_definition(material_id)
	match house_type:
		&"barrel":
			_barrel(canvas, material)
		&"igloo":
			_igloo(canvas, material)
		&"fortress":
			_fortress(canvas, material)
		_:
			_classic(canvas, material)
	if damage > 0.0:
		_cracks(canvas, material, damage, house_type)


static func collision_outline(house_type: StringName) -> PackedVector2Array:
	match house_type:
		&"barrel":
			return PackedVector2Array([
				Vector2(-44, 56), Vector2(-58, 16), Vector2(-60, -3),
				Vector2(-52, -30), Vector2(-30, -49), Vector2(0, -56),
				Vector2(30, -49), Vector2(52, -30), Vector2(60, -3),
				Vector2(58, 16), Vector2(44, 56),
			])
		&"igloo":
			return _dome_points(Vector2(88, 116), 58.0)
		&"fortress":
			return PackedVector2Array([Vector2(-82, 78), Vector2(-82, -78), Vector2(82, -78), Vector2(82, 78)])
		_:
			return PackedVector2Array([Vector2(-70, 62), Vector2(-70, -62), Vector2(70, -62), Vector2(70, 62)])


static func _classic(canvas: CanvasItem, material: BlockMaterialDefinition) -> void:
	_panel(canvas, Rect2(-58, -24, 116, 86), material)
	var roof := PackedVector2Array([Vector2(-70, -24), Vector2(0, -62), Vector2(70, -24), Vector2(64, -16), Vector2(0, -49), Vector2(-64, -16)])
	canvas.draw_colored_polygon(roof, material.edge_color)
	canvas.draw_polyline(PackedVector2Array([Vector2(-65, -25), Vector2(0, -57), Vector2(65, -25)]), material.highlight_color, 4.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-49, -24), Vector2(0, -49), Vector2(49, -24)]), material.base_color)
	_door(canvas, material, 37.0, 62.0)
	_bone(canvas, Vector2(0, -27))


static func _barrel(canvas: CanvasItem, material: BlockMaterialDefinition) -> void:
	# Feet give the round barrel a stable, flat support at its advertised bottom.
	for side in [-1.0, 1.0]:
		canvas.draw_rect(Rect2(side * 34 - 10, 41, 20, 15), material.edge_color)
		canvas.draw_rect(Rect2(side * 34 - 7, 47, 14, 6), material.detail_color)
	canvas.draw_colored_polygon(_ellipse_points(Vector2(0, -3), Vector2(60, 53)), material.edge_color)
	canvas.draw_colored_polygon(_ellipse_points(Vector2(0, -3), Vector2(56, 49)), material.base_color)
	# Horizontal seams follow the varying width of the barrel's round end.
	for row in 4:
		var y: float = -36.0 + float(row) * 20.0
		var half_width: float = 54.0 * sqrt(maxf(0.0, 1.0 - pow((y + 3.0) / 48.0, 2.0)))
		canvas.draw_line(Vector2(-half_width, y), Vector2(half_width, y), material.detail_color, 2.0, true)
		if material.id == &"stone":
			var joint: float = -18.0 if row % 2 == 0 else 19.0
			canvas.draw_line(Vector2(joint, y), Vector2(joint, y + 17), material.edge_color, 2.0, true)
	# Two curved hoops read as a barrel even when its surface is glass or stone.
	for side in [-1.0, 1.0]:
		var hoop := PackedVector2Array([Vector2(side * 28, -47), Vector2(side * 40, -30), Vector2(side * 47, -4), Vector2(side * 44, 23), Vector2(side * 34, 42)])
		canvas.draw_polyline(hoop, material.edge_color, 7.0, true)
		canvas.draw_polyline(hoop, material.highlight_color, 2.0, true)
		_rivet(canvas, Vector2(side * 44, 15), material)
	if material.id == &"glass":
		canvas.draw_line(Vector2(-21, -38), Vector2(7, -48), material.highlight_color, 3.0, true)
		canvas.draw_line(Vector2(-19, -31), Vector2(18, -44), material.highlight_color, 2.0, true)
	elif material.id == &"metal":
		for side in [-1.0, 1.0]:
			_rivet(canvas, Vector2(side * 20, -36), material)
	_door(canvas, material, 31.0, 56.0)
	_bone(canvas, Vector2(0, -30))


static func _igloo(canvas: CanvasItem, material: BlockMaterialDefinition) -> void:
	canvas.draw_colored_polygon(_dome_points(Vector2(88, 116), 58.0), material.edge_color)
	canvas.draw_colored_polygon(_dome_points(Vector2(84, 109), 55.0), material.base_color)
	# Curved masonry courses make the dome distinct from a round barrel.
	for row in 4:
		var y: float = -31.0 + float(row) * 23.0
		var half_width: float = 82.0 * sqrt(maxf(0.0, 1.0 - pow((55.0 - y) / 108.0, 2.0)))
		var course := PackedVector2Array()
		for step in 13:
			var x: float = lerpf(-half_width, half_width, float(step) / 12.0)
			course.append(Vector2(x, y + 5.0 * (1.0 - pow(x / half_width, 2.0))))
		canvas.draw_polyline(course, material.detail_color, 2.0, true)
		for side in [-1.0, 1.0]:
			var joint: float = side * half_width * (0.58 if row % 2 == 0 else 0.34)
			canvas.draw_line(Vector2(joint, y + 4), Vector2(joint + side * 5, minf(y + 21, 55.0)), material.detail_color, 2.0, true)
			if material.id == &"metal":
				_rivet(canvas, Vector2(side * half_width * 0.8, y + 8), material)
	if material.id == &"glass":
		canvas.draw_polyline(PackedVector2Array([Vector2(-65, 0), Vector2(-49, -26), Vector2(-27, -42)]), material.highlight_color, 4.0, true)
		canvas.draw_line(Vector2(45, 8), Vector2(62, -4), material.highlight_color, 3.0, true)
	else:
		canvas.draw_polyline(PackedVector2Array([Vector2(-60, -8), Vector2(-41, -32), Vector2(-17, -47)]), material.highlight_color, 2.0, true)
	# A protruding arch of wedge-shaped sections marks the igloo entrance.
	canvas.draw_circle(Vector2(0, 16), 40.0, material.edge_color)
	canvas.draw_rect(Rect2(-40, 16, 80, 42), material.edge_color)
	canvas.draw_circle(Vector2(0, 16), 36.0, material.highlight_color)
	canvas.draw_rect(Rect2(-36, 16, 72, 38), material.base_color)
	for step in 7:
		var angle: float = PI + float(step) * PI / 6.0
		canvas.draw_line(Vector2(0, 16) + Vector2.from_angle(angle) * 30.0, Vector2(0, 16) + Vector2.from_angle(angle) * 39.0, material.edge_color, 2.0, true)
	_door(canvas, material, 33.0, 58.0)
	_bone(canvas, Vector2(0, -35))


static func _fortress(canvas: CanvasItem, material: BlockMaterialDefinition) -> void:
	_panel(canvas, Rect2(-78, -46, 156, 124), material)
	for side in [-1.0, 1.0]:
		var left: float = -82.0 if side < 0.0 else 44.0
		_panel(canvas, Rect2(left, -64, 38, 142), material)
		for tooth in 3:
			canvas.draw_rect(Rect2(left + float(tooth) * 14, -78, 10, 19), material.edge_color)
			canvas.draw_rect(Rect2(left + float(tooth) * 14 + 2, -75, 6, 16), material.base_color)
		canvas.draw_rect(Rect2(left, -59, 38, 7), material.edge_color)
		canvas.draw_line(Vector2(left + 3, -56), Vector2(left + 35, -56), material.highlight_color, 2.0, true)
		# Narrow turret windows give the tall kennel a castle silhouette.
		canvas.draw_rect(Rect2(left + 15, -35, 8, 22), material.edge_color)
		canvas.draw_rect(Rect2(left + 18, -32, 3, 15), DOOR_COLOR)
	for tooth in 4:
		var x: float = -39.0 + float(tooth) * 22.0
		canvas.draw_rect(Rect2(x, -59, 12, 17), material.edge_color)
		canvas.draw_rect(Rect2(x + 2, -56, 8, 12), material.base_color)
	var shield := PackedVector2Array([Vector2(-18, -35), Vector2(18, -35), Vector2(15, -14), Vector2(0, -3), Vector2(-15, -14)])
	canvas.draw_colored_polygon(shield, material.edge_color)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-14, -31), Vector2(14, -31), Vector2(11, -16), Vector2(0, -8), Vector2(-11, -16)]), material.highlight_color)
	_bone(canvas, Vector2(0, -23))
	_door(canvas, material, 53.0, 78.0)


static func _panel(canvas: CanvasItem, rect: Rect2, material: BlockMaterialDefinition) -> void:
	canvas.draw_rect(rect, material.edge_color)
	var inner := rect.grow(-3)
	canvas.draw_rect(inner, material.base_color)
	match material.id:
		&"glass":
			canvas.draw_rect(inner.grow(-3), material.highlight_color, false, 1.0)
			for side in [-1.0, 1.0]:
				var x: float = rect.get_center().x + side * rect.size.x * 0.34
				canvas.draw_line(Vector2(x - 5, rect.position.y + 36), Vector2(x + 5, rect.position.y + 20), material.highlight_color, 3.0, true)
				canvas.draw_line(Vector2(x - 5, rect.position.y + 47), Vector2(x + 5, rect.position.y + 31), material.highlight_color, 2.0, true)
		&"stone":
			var rows: int = maxi(1, int(rect.size.y / 22))
			for row in rows:
				var y: float = inner.position.y + float(row) * 22.0
				canvas.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), material.edge_color, 2.0, true)
				var joint: float = rect.get_center().x + rect.size.x * (-0.15 if row % 2 == 0 else 0.19)
				canvas.draw_line(Vector2(joint, y), Vector2(joint, minf(y + 22, inner.end.y)), material.detail_color, 2.0, true)
		&"metal":
			for side in [-1.0, 1.0]:
				var x: float = rect.get_center().x + side * (rect.size.x * 0.5 - 11.0)
				canvas.draw_line(Vector2(x, inner.position.y + 8), Vector2(x, inner.end.y - 8), material.highlight_color, 3.0, true)
				_rivet(canvas, Vector2(x, inner.position.y + 8), material)
				_rivet(canvas, Vector2(x, inner.end.y - 8), material)
		_:
			var columns: int = maxi(1, int(rect.size.x / 19.0))
			for column in columns:
				var x: float = lerpf(inner.position.x, inner.end.x, float(column + 1) / float(columns + 1))
				canvas.draw_line(Vector2(x, inner.position.y + 2), Vector2(x, inner.end.y - 2), material.detail_color, 2.0, true)
			canvas.draw_line(inner.position + Vector2(6, 18), inner.position + Vector2(8, 53), material.highlight_color, 1.5, true)


static func _door(canvas: CanvasItem, material: BlockMaterialDefinition, dog_y: float, floor_y: float) -> void:
	var arch_y: float = dog_y - 17.0
	canvas.draw_circle(Vector2(0, arch_y), 31.0, material.edge_color)
	canvas.draw_rect(Rect2(-31, arch_y, 62, floor_y - arch_y), material.edge_color)
	canvas.draw_circle(Vector2(0, arch_y + 1), 26.0, DOOR_COLOR)
	canvas.draw_rect(Rect2(-26, arch_y + 1, 52, floor_y - arch_y - 4), DOOR_COLOR)
	canvas.draw_rect(Rect2(-38, floor_y - 6, 76, 6), material.edge_color)
	canvas.draw_line(Vector2(-35, floor_y - 5), Vector2(35, floor_y - 5), material.highlight_color, 2.0, true)


static func _bone(canvas: CanvasItem, at: Vector2) -> void:
	canvas.draw_rect(Rect2(at + Vector2(-8, -3), Vector2(16, 6)), SIGN_COLOR)
	for side in [-1.0, 1.0]:
		canvas.draw_circle(at + Vector2(side * 9, -3), 3.5, SIGN_COLOR)
		canvas.draw_circle(at + Vector2(side * 9, 3), 3.5, SIGN_COLOR)


static func _rivet(canvas: CanvasItem, at: Vector2, material: BlockMaterialDefinition) -> void:
	canvas.draw_circle(at, 3.2, material.edge_color)
	canvas.draw_circle(at + Vector2(-0.7, -0.7), 1.1, material.highlight_color)


static func _ellipse_points(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in 32:
		var angle: float = float(step) * TAU / 32.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


static func _dome_points(radii: Vector2, floor_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step in 25:
		var angle: float = PI - float(step) * PI / 24.0
		points.append(Vector2(cos(angle) * radii.x, floor_y - sin(angle) * radii.y))
	return points


static func _cracks(canvas: CanvasItem, material: BlockMaterialDefinition, damage: float, house_type: StringName) -> void:
	var definition := DogHouseTypes.get_definition(house_type)
	var half_width: float = definition.size.x * 0.5
	var floor_y: float = definition.size.y * 0.5
	var crack_color: Color = material.edge_color.darkened(0.35)
	# Side cracks stay visible around the resident and do not cross the doorway.
	for side in [-1.0, 1.0]:
		var x: float = minf(half_width - 14.0, 61.0)
		canvas.draw_polyline(PackedVector2Array([
			Vector2(side * x, floor_y - 64), Vector2(side * (x - 10), floor_y - 48),
			Vector2(side * (x - 5), floor_y - 40), Vector2(side * 34, floor_y - 17),
		]), crack_color, 2.6, true)
	if damage >= 0.5:
		var top: float = -definition.size.y * 0.5 + (23.0 if house_type == &"fortress" else 13.0)
		canvas.draw_polyline(PackedVector2Array([Vector2(-11, top), Vector2(-3, top + 10), Vector2(-9, top + 16), Vector2(8, top + 26)]), crack_color, 3.0, true)
