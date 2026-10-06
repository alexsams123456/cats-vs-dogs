class_name StartupTransition
extends Control
## Продолжение загрузочной картинки: растворение в живой двор и появление меню.

signal finished

const SPLASH := preload("res://assets/boot_splash.png")
const PAPER := Color("fff6db")
const HOLD_SECONDS: float = 0.12
const REVEAL_SECONDS: float = 1.15

var _progress: float = 0.0
var _menu: CampaignMenu


func _ready() -> void:
	resized.connect(queue_redraw)


func begin(menu: CampaignMenu) -> void:
	_menu = menu
	_menu.prepare_startup_entrance()
	var reveal := create_tween()
	reveal.tween_interval(HOLD_SECONDS)
	reveal.tween_method(_set_progress, 0.0, 1.0, REVEAL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal.tween_callback(func() -> void: finished.emit())


func _input(_event: InputEvent) -> void:
	# Включая клавиатуру: прозрачная заставка всё ещё закрывает кнопки меню.
	get_viewport().set_input_as_handled()


func _set_progress(progress: float) -> void:
	_progress = progress
	modulate.a = 1.0 - smoothstep(0.0, 0.88, progress)
	_menu.set_startup_progress(progress)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var source_size := Vector2(SPLASH.get_size())
	var fit := minf(size.x / source_size.x, size.y / source_size.y)
	var picture_size := source_size * fit * (1.0 + _progress * 0.035)
	draw_texture_rect(SPLASH, Rect2((size - picture_size) * 0.5, picture_size), false)
