class_name BlockVisual
extends RefCounted
## Material textures are shared by the editor and the physical building parts.


static func paint(canvas: CanvasItem, size: Vector2, material_id: StringName, damage: float = 0.0) -> void:
	var material := BlockMaterials.get_definition(material_id)
	var rect := Rect2(-size * 0.5, size)
	canvas.draw_rect(rect, material.edge_color)
	canvas.draw_rect(rect.grow(-2.5), material.base_color)
	canvas.draw_line(rect.position + Vector2(4, 4), rect.position + Vector2(size.x - 4, 4), material.highlight_color, 2.0, true)
	match material.id:
		&"glass":
			_glass(canvas, size, material)
		&"stone":
			_stone(canvas, size, material)
		&"metal":
			_metal(canvas, size, material)
		_:
			_wood(canvas, size, material)
	if damage > 0.0:
		_cracks(canvas, size, material.edge_color, damage)


static func _wood(canvas: CanvasItem, size: Vector2, material: BlockMaterialDefinition) -> void:
	if size.y >= size.x:
		canvas.draw_line(Vector2(-size.x * 0.15, -size.y * 0.4), Vector2(-size.x * 0.09, size.y * 0.35), material.detail_color, 2.0, true)
		canvas.draw_line(Vector2(size.x * 0.18, -size.y * 0.22), Vector2(size.x * 0.24, size.y * 0.43), material.highlight_color, 2.0, true)
		_rivet(canvas, Vector2(0, -size.y * 0.5 + 10), 2.7, material.edge_color)
		_rivet(canvas, Vector2(0, size.y * 0.5 - 10), 2.7, material.edge_color)
	else:
		canvas.draw_line(Vector2(-size.x * 0.4, 0), Vector2(size.x * 0.35, 2), material.detail_color, 2.0, true)
		_rivet(canvas, Vector2(-size.x * 0.5 + 10, 0), 2.7, material.edge_color)
		_rivet(canvas, Vector2(size.x * 0.5 - 10, 0), 2.7, material.edge_color)


static func _glass(canvas: CanvasItem, size: Vector2, material: BlockMaterialDefinition) -> void:
	var inset := Rect2(-size * 0.5 + Vector2(6, 6), size - Vector2(12, 12))
	canvas.draw_rect(inset, material.highlight_color, false, 1.0)
	# Diagonal reflected streaks make glass readable even without transparency.
	for index in 2:
		var offset: float = -0.17 + float(index) * 0.32
		canvas.draw_line(Vector2(-size.x * 0.26, size.y * (offset + 0.13)), Vector2(size.x * 0.26, size.y * (offset - 0.13)), material.highlight_color, 3.0, true)


static func _stone(canvas: CanvasItem, size: Vector2, material: BlockMaterialDefinition) -> void:
	var rows: int = maxi(1, int(size.y / 28.0))
	var row_height: float = size.y / float(rows)
	for row in rows:
		var top: float = -size.y * 0.5 + float(row) * row_height
		if row > 0:
			canvas.draw_line(Vector2(-size.x * 0.5 + 3, top), Vector2(size.x * 0.5 - 3, top), material.edge_color, 2.0, true)
		var joint: float = size.x * (-0.14 if row % 2 == 0 else 0.19)
		canvas.draw_line(Vector2(joint, top + 3), Vector2(joint, top + row_height - 3), material.detail_color, 2.0, true)
		canvas.draw_line(Vector2(-size.x * 0.36, top + row_height * 0.65), Vector2(-size.x * 0.24, top + row_height * 0.6), material.highlight_color, 1.7, true)


static func _metal(canvas: CanvasItem, size: Vector2, material: BlockMaterialDefinition) -> void:
	var inset := Rect2(-size * 0.5 + Vector2(7, 7), size - Vector2(14, 14))
	canvas.draw_rect(inset, material.detail_color, false, 2.0)
	if size.y >= size.x:
		canvas.draw_line(Vector2(-size.x * 0.12, -size.y * 0.38), Vector2(-size.x * 0.12, size.y * 0.38), material.highlight_color, 3.0, true)
		for side in [-1.0, 1.0]:
			_rivet(canvas, Vector2(0, side * (size.y * 0.5 - 10)), 3.5, material.edge_color)
	else:
		canvas.draw_line(Vector2(-size.x * 0.38, -size.y * 0.12), Vector2(size.x * 0.38, -size.y * 0.12), material.highlight_color, 3.0, true)
		for side in [-1.0, 1.0]:
			_rivet(canvas, Vector2(side * (size.x * 0.5 - 10), 0), 3.5, material.edge_color)


static func _rivet(canvas: CanvasItem, at: Vector2, radius: float, color: Color) -> void:
	canvas.draw_circle(at, radius, color)
	canvas.draw_circle(at + Vector2(-0.7, -0.7), radius * 0.35, color.lightened(0.65))


static func _cracks(canvas: CanvasItem, size: Vector2, color: Color, damage: float) -> void:
	var crack := PackedVector2Array([
		Vector2(-size.x * 0.42, -size.y * 0.26),
		Vector2(-size.x * 0.1, -size.y * 0.09),
		Vector2(-size.x * 0.2, size.y * 0.02),
		Vector2(size.x * 0.21, size.y * 0.2),
		Vector2(size.x * 0.42, size.y * 0.32),
	])
	canvas.draw_polyline(crack, color.darkened(0.35), 2.4, true)
	if damage >= 0.5:
		canvas.draw_polyline(PackedVector2Array([
			Vector2(size.x * 0.29, -size.y * 0.4),
			Vector2(size.x * 0.05, -size.y * 0.12),
			Vector2(size.x * 0.18, size.y * 0.04),
			Vector2(-size.x * 0.02, size.y * 0.12),
		]), color.darkened(0.35), 2.4, true)
