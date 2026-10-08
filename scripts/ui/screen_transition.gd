class_name ScreenTransition
extends Control
## Общая шторка смены экранов, работающая также при паузе боя.

const COVER_SECONDS: float = 0.22
const REVEAL_SECONDS: float = 0.28
var progress: float = 0.0


func _ready() -> void:
	resized.connect(queue_redraw)


func cover() -> void:
	await _animate(1.0, COVER_SECONDS)


func reveal() -> void:
	await _animate(0.0, REVEAL_SECONDS)


func _animate(target: float, seconds: float) -> void:
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_set_progress, progress, target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _set_progress(value: float) -> void:
	progress = value
	queue_redraw()


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.16, 0.20, progress))
	var center := size * 0.5
	var scale_factor := 0.85 + 0.15 * progress
	var ink := Color(1.0, 0.90, 0.68, progress)
	draw_circle(center + Vector2(0, 12) * scale_factor, 19 * scale_factor, ink, true, -1.0, true)
	for toe: Vector2 in [Vector2(-26, -9), Vector2(-10, -27), Vector2(10, -27), Vector2(26, -9)]:
		draw_circle(center + toe * scale_factor, 9 * scale_factor, ink, true, -1.0, true)
