extends RefCounted
## Lookup by the existing wind value, so the original pausable clock is preserved.

const FRAMES: int = 64
const COLUMNS: int = 32
const WIND_MIN: float = -6.3
const WIND_MAX: float = 8.7
const GRASS_BOUNDS := Rect2(-24, -32, 48, 36)
const FLOWER_BOUNDS := Rect2(-18, -56, 36, 64)


static func wind_for(frame: int) -> float:
	return lerpf(WIND_MIN, WIND_MAX, float(frame) / float(FRAMES - 1))


static func paint(canvas: CanvasItem, texture: Texture2D, root: Vector2, variant: int, wind: float, flower: bool) -> void:
	var frame := clampi(roundi(inverse_lerp(WIND_MIN, WIND_MAX, wind) * (FRAMES - 1)), 0, FRAMES - 1)
	var tile := variant * FRAMES + frame
	var bounds := FLOWER_BOUNDS if flower else GRASS_BOUNDS
	var cell := bounds.size * 2.0
	var region := Rect2(Vector2(tile % COLUMNS, tile / COLUMNS) * cell, cell)
	canvas.draw_texture_rect_region(texture, Rect2(root + bounds.position, bounds.size), region)
