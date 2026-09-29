class_name ResultCelebration
extends Control
## Короткий общий поклон команды, без ввода, физических тел и бесконечных частиц.

const HERO_VISUAL := preload("res://scripts/visuals/hero_visual.gd")
const DURATION: float = 2.6
const CONFETTI_COLORS: Array[Color] = [Color("f2bd62"), Color("68ae98"), Color("ef9c8e")]

var elapsed: float = 0.0
var cast: Array[CharacterDefinition] = []
var _focused: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	custom_minimum_size = Vector2(0, 112)
	resized.connect(queue_redraw)
	visibility_changed.connect(_update_processing)
	stop()


func start(kinds: PackedStringArray) -> void:
	cast.clear()
	for kind: String in kinds:
		cast.append(CharacterCatalog.find_cat(StringName(kind)))
		if cast.size() == 3:
			break
	if cast.is_empty():
		cast.append(CharacterCatalog.CATS[0])
	elapsed = 0.0
	show()
	_update_processing()
	queue_redraw()


func stop() -> void:
	hide()
	set_process(false)
	elapsed = 0.0


func _process(delta: float) -> void:
	elapsed = minf(elapsed + delta, DURATION)
	queue_redraw()
	_update_processing()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_update_processing()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_update_processing()


func _update_processing() -> void:
	set_process(is_visible_in_tree() and _focused and elapsed < DURATION)


func _draw() -> void:
	if cast.is_empty():
		return
	var center := Vector2(size.x * 0.5, size.y - 31)
	var spacing := minf(108.0, size.x / float(cast.size() + 1))
	_draw_confetti(center)
	for index: int in cast.size():
		var hero := cast[index]
		var ground := center + Vector2((float(index) - float(cast.size() - 1) * 0.5) * spacing, 0)
		var jump_time := clampf((elapsed - 0.18 - float(index) * 0.22) / 0.72, 0.0, 1.0)
		var jump := sin(jump_time * PI)
		var bow_time := clampf((elapsed - 1.5) / 0.85, 0.0, 1.0)
		var bow := sin(bow_time * PI)
		draw_set_transform(ground + Vector2(0, 24), 0.0, Vector2(1.0 - jump * 0.25, 0.18))
		draw_circle(Vector2.ZERO, 29, Color(0.18, 0.37, 0.31, 0.12))
		var tilt := sin(jump_time * TAU) * 0.16 + bow * (0.12 if index % 2 == 0 else -0.12)
		var stretch := Vector2(1.0 + bow * 0.06 - jump * 0.04, 1.0 - bow * 0.10 + jump * 0.06)
		draw_set_transform(ground + Vector2(0, -jump * 24 + bow * 3), tilt, stretch * 0.92)
		HERO_VISUAL.paint(self, &"cat", hero.id, hero.fur_color, hero.accent_color, elapsed, float(index), &"celebrate")
	draw_set_transform(Vector2.ZERO)


func _draw_confetti(center: Vector2) -> void:
	var progress := clampf(elapsed / 2.25, 0.0, 1.0)
	var opacity := sin(progress * PI)
	if opacity <= 0.0:
		return
	for index in 18:
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var spread: float = 45.0 + float(index % 5) * 22.0
		var point := center + Vector2(side * spread * (0.5 + progress), -22.0 - sin(progress * PI) * (28 + index % 4 * 7) + progress * 21)
		var color := CONFETTI_COLORS[index % CONFETTI_COLORS.size()]
		color.a = opacity
		draw_set_transform(point, float(index) + progress * side * 3.0)
		draw_line(Vector2(-3, 0), Vector2(3, 0), color, 3.0, true)
	draw_set_transform(Vector2.ZERO)
