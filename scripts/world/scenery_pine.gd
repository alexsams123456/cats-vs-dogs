extends Node2D
## Рисунок сосны кэшируется; ветер меняет только преобразование узла.

var height: float = 100.0
var tint := Color("497867")


func _draw() -> void:
	draw_tree(self, Vector2.ZERO, height, tint)


static func draw_tree(canvas: CanvasItem, root: Vector2, tree_height: float, color: Color) -> void:
	canvas.draw_line(root, root - Vector2(0, tree_height * 0.86), color.darkened(0.2), maxf(2.0, tree_height * 0.047), true)
	for index in range(4, -1, -1):
		var tip := root - Vector2(0, tree_height * (1.0 - float(index) * 0.14))
		var half_width := tree_height * (0.10 + float(index) * 0.036)
		var depth := tree_height * (0.29 + float(index) * 0.014)
		canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(half_width, depth), tip + Vector2(half_width * 0.13, depth * 0.89), tip + Vector2(-half_width, depth * 1.02)]), color)
		canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-half_width, depth * 1.02), tip + Vector2(-half_width * 0.10, depth * 0.88)]), color.lightened(0.07))
