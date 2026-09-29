class_name CampaignBiomeIcon
extends Control
## Маленькие собственные пейзажи отмечают главы карты кампании.

var biome: StringName = &"backyard"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / 64.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	var sky := Color("acd9ca")
	if biome == &"mountain":
		sky = Color("c6d9dc")
	elif biome == &"glacier":
		sky = Color("b8dfec")
	draw_circle(Vector2(32, 32), 30, sky)
	if biome == &"backyard":
		draw_circle(Vector2(46, 18), 7, Color("ffe6a0"))
		draw_rect(Rect2(11, 33, 38, 19), Color("6c9c66"))
		draw_rect(Rect2(20, 26, 28, 25), Color("f1ca88"))
		draw_colored_polygon(PackedVector2Array([Vector2(15, 28), Vector2(34, 11), Vector2(53, 28)]), Color("ae6851"))
		draw_rect(Rect2(30, 35, 9, 16), Color("725440"))
		for x in [10, 17, 48, 55]:
			draw_line(Vector2(x, 44), Vector2(x, 56), Color("fff0cc"), 4)
		draw_line(Vector2(7, 47), Vector2(20, 47), Color("fff0cc"), 3)
		draw_line(Vector2(46, 47), Vector2(58, 47), Color("fff0cc"), 3)
	elif biome == &"mountain":
		draw_colored_polygon(PackedVector2Array([Vector2(4, 49), Vector2(24, 14), Vector2(43, 49)]), Color("927f6e"))
		draw_colored_polygon(PackedVector2Array([Vector2(21, 54), Vector2(44, 9), Vector2(61, 49)]), Color("677f82"))
		draw_colored_polygon(PackedVector2Array([Vector2(35, 26), Vector2(44, 9), Vector2(51, 27), Vector2(44, 23), Vector2(41, 29)]), Color("fff8e7"))
		draw_line(Vector2(15, 53), Vector2(23, 53), Color("dcb481"), 4)
		draw_line(Vector2(23, 53), Vector2(32, 45), Color("dcb481"), 4)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(4, 44), Vector2(15, 23), Vector2(22, 24), Vector2(26, 48)]), Color("73b1d0"))
		draw_colored_polygon(PackedVector2Array([Vector2(40, 47), Vector2(46, 16), Vector2(52, 19), Vector2(60, 42)]), Color("7bbbd8"))
		draw_line(Vector2(47, 18), Vector2(46, 38), Color("daf5fb"), 3)
		draw_circle(Vector2(32, 43), 17, Color("f4fcfa"))
		draw_rect(Rect2(15, 43, 35, 10), Color("e7f4f4"))
		draw_arc(Vector2(32, 49), 8, PI, TAU, 16, Color("497e9f"), 10, true)
		draw_line(Vector2(19, 37), Vector2(45, 37), Color("bedee9"), 1)
		draw_line(Vector2(16, 44), Vector2(47, 44), Color("bedee9"), 1)
		draw_line(Vector2(32, 28), Vector2(32, 37), Color("bedee9"), 1)
		draw_line(Vector2(23, 37), Vector2(23, 43), Color("bedee9"), 1)
	draw_set_transform(Vector2.ZERO)
