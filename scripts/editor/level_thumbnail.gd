class_name LevelThumbnail
extends LevelCanvas
## Та же процедурная картинка, что в редакторе, без ввода, сетки и физики.

var view_bounds := Rect2(Vector2.ZERO, WORLD_SIZE)


func _scale_factor() -> float:
	return maxf(0.01, minf(size.x / view_bounds.size.x, size.y / view_bounds.size.y))


func _origin() -> Vector2:
	return (size - view_bounds.size * _scale_factor()) * 0.5 - view_bounds.position * _scale_factor()


func _init() -> void:
	read_only = true
	grid_enabled = false
	show_guides = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(184, 104)


func _ready() -> void:
	super._ready()
	set_process_input(false)
	set_process_unhandled_input(false)
