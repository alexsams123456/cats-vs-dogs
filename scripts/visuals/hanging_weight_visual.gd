class_name HangingWeightVisual
extends RefCounted
## Общий рисунок груза и крепления для боя и редактора.

const WEIGHT_SIZE := Vector2(76, 64)
const ROPE_TOP := Vector2(0, -172)
const ROPE_BOTTOM := Vector2(0, -32)
const BOUNDS := Rect2(-38, -180, 76, 212)


static func paint(canvas: CanvasItem, suspended: bool = true) -> void:
	if suspended:
		canvas.draw_rect(Rect2(-24, -180, 48, 12), Color("765b4d"))
		canvas.draw_circle(ROPE_TOP, 7, Color("e4b96f"))
		canvas.draw_line(ROPE_TOP, ROPE_BOTTOM, Color("765b4d"), 7, true)
		canvas.draw_line(ROPE_TOP + Vector2(-1, 0), ROPE_BOTTOM + Vector2(-1, 0), Color("f4cc87"), 3, true)
		for y in range(-164, -32, 12):
			canvas.draw_line(Vector2(-3, y), Vector2(3, y + 5), Color("bd8b53"), 2, true)
	canvas.draw_rect(Rect2(-WEIGHT_SIZE * 0.5, WEIGHT_SIZE), Color("344e60"))
	canvas.draw_rect(Rect2(-WEIGHT_SIZE * 0.5 + Vector2(4, 4), WEIGHT_SIZE - Vector2(8, 8)), Color("789aaa"))
	canvas.draw_rect(Rect2(-34, -28, 68, 12), Color("a9c4ce"))
	canvas.draw_rect(Rect2(-34, 18, 68, 10), Color("d9b854"))
	for x in [-26, 26]:
		for y in [-22, 22]:
			canvas.draw_circle(Vector2(x, y), 3, Color("344e60"))
	canvas.draw_line(Vector2(-13, -3), Vector2(0, 9), Color("fff2ce"), 4, true)
	canvas.draw_line(Vector2(0, 9), Vector2(13, -3), Color("fff2ce"), 4, true)
