class_name CharacterPortrait
extends Control
## Portrait backdrop and idle motion around the shared hero artwork.

const HERO_VISUAL = preload("res://scripts/visuals/hero_visual.gd")
const CREAM := Color("fff7df")

@export var definition: CharacterDefinition:
	set(value):
		definition = value
		queue_redraw()

var visual_time: float = 0.0
var _phase: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase = float(get_instance_id() % 997) * 0.061
	resized.connect(queue_redraw)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _process(delta: float) -> void:
	var previous_time := visual_time
	visual_time += delta
	if HeroVisual.needs_redraw(previous_time, visual_time):
		queue_redraw()


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	queue_redraw()


func _draw() -> void:
	if definition == null:
		return
	var portrait_scale: float = minf(size.x / 250.0, size.y / 200.0)
	var center := Vector2(size.x * 0.5, size.y * 0.53)
	draw_set_transform(center, 0.0, Vector2.ONE * portrait_scale)
	var backdrop: Color = definition.accent_color.lerp(CREAM, 0.84)
	draw_circle(Vector2.ZERO, 88.0, backdrop)
	draw_arc(Vector2.ZERO, 94.0, -0.65, 0.25, 20, definition.accent_color.lightened(0.25), 3.0, true)
	draw_arc(Vector2.ZERO, 94.0, 2.45, 3.05, 20, definition.accent_color.lightened(0.25), 3.0, true)
	_ellipse(Vector2(0, 67), Vector2(49, 9), Color(0.15, 0.29, 0.26, 0.10))
	var breathing: float = sin(visual_time * 2.4 + _phase)
	var offset := Vector2(0, breathing * 2.0) * portrait_scale
	var tilt: float = sin(visual_time * 1.6 + _phase) * 0.025
	var stretch := Vector2(1.0 - breathing * 0.006, 1.0 + breathing * 0.01)
	draw_set_transform(center + offset, tilt, stretch * 2.15 * portrait_scale)
	HERO_VISUAL.paint(self, StringName(definition.species), definition.id, definition.fur_color, definition.accent_color, visual_time, _phase, &"idle", definition.id == &"armored")
	draw_set_transform(Vector2.ZERO)


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 40:
		var angle: float = TAU * float(index) / 40.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)
