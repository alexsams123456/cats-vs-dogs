class_name CatQueue
extends Node2D
## Коты в запасе у рогатки; рисунок не участвует в физике и вводе.

const MAX_VISIBLE: int = 6
const SPACING: float = 32.0
const CAT_SCALE: float = 0.62

var cats: Array[CharacterDefinition] = []
var visual_time: float = 0.0


func set_cats(definitions: Array[CharacterDefinition]) -> void:
	cats.assign(definitions)
	set_process(not cats.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	var previous_time := visual_time
	visual_time += delta
	if HeroVisual.needs_redraw(previous_time, visual_time):
		queue_redraw()


func _draw() -> void:
	for index in range(mini(cats.size(), MAX_VISIBLE) - 1, -1, -1):
		var cat := cats[index]
		var center := Vector2(-float(index) * SPACING, 0.0)
		draw_set_transform(center + Vector2(0, 13), 0.0, Vector2(1, 0.25))
		draw_circle(Vector2.ZERO, 17.0, Color(0.15, 0.29, 0.26, 0.15))
		draw_set_transform(center, 0.0, Vector2.ONE * CAT_SCALE)
		HeroVisual.paint(self, &"cat", cat.id, cat.fur_color, cat.accent_color, visual_time, float(index) * 1.7)
	draw_set_transform(Vector2.ZERO)
	if cats.size() > MAX_VISIBLE:
		draw_string(ThemeDB.fallback_font, Vector2(-180, -35), "+%d" % (cats.size() - MAX_VISIBLE), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, HeroVisual.INK)
