class_name SpringPadVisual
extends RefCounted
## Общая процедурная пружина для боя, редактора и миниатюр.

const SIZE := Vector2(96, 36)


static func paint(canvas: CanvasItem, compression: float = 0.0) -> void:
	var top := -14.0 + compression * 8.0
	canvas.draw_style_box(_plate(Color("526d73")), Rect2(-48, 10, 96, 8))
	for x: float in [-26.0, 26.0]:
		var points := PackedVector2Array([Vector2(x, 10)])
		for index in 7:
			points.append(Vector2(x + (-8.0 if index % 2 == 0 else 8.0), lerpf(8.0, top + 4.0, float(index) / 6.0)))
		canvas.draw_polyline(points, Color("51697b"), 4.0, true)
	canvas.draw_style_box(_plate(Color("efa85a")), Rect2(-48, top - 4, 96, 8))
	canvas.draw_line(Vector2(-39, top - 1), Vector2(39, top - 1), Color("fff1cb"), 2.0, true)
	canvas.draw_line(Vector2(0, top + 19), Vector2(0, top + 8), Color("298c87"), 3.0, true)
	canvas.draw_polyline(PackedVector2Array([Vector2(-5, top + 13), Vector2(0, top + 8), Vector2(5, top + 13)]), Color("298c87"), 3.0, true)


static func _plate(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style
