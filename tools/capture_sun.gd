extends SceneTree
## Снимки солнца и проверка ввода на ПК; исходы для рисунка задаются явно.
## Godot --path . --script res://tools/capture_sun.gd

const APP_SCENE := preload("res://scenes/app.tscn")
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для снимков солнца нужен графический запуск без --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	AudioServer.set_bus_mute(0, true)
	var app := APP_SCENE.instantiate() as GameApp
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	GameLocalization.apply_locale("ru")
	for dimensions: Vector2i in WINDOW_SIZES:
		root.size = dimensions
		app.show_menu()
		await _layout()
		await create_timer(0.5).timeout
		await _save("menu")
		await _capture_round(app, dimensions.x != 1280)
		app.show_editor()
		await _layout()
		await _save("editor")
		var editor_face := (app.editor.canvas._backdrop.get_node("AmbientLife") as AmbientLife).sun_face
		var frozen := [editor_face.animation_time, editor_face.gaze]
		await create_timer(0.12).timeout
		_check([editor_face.animation_time, editor_face.gaze] == frozen, "Редактор оставляет солнце неподвижным")
	paused = false
	app.queue_free()
	await _layout()
	await _capture_gallery()
	await create_timer(0.3).timeout
	print("Sun graphic checks: %d passed, %d failed. Images: .artifacts/sun-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _capture_round(app: GameApp, touch: bool) -> void:
	app.start_game(&"classic", &"scout")
	await _layout()
	var game := app.game
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.set_paused(false)
	var face := (game.get_node("Backdrop/AmbientLife") as AmbientLife).sun_face
	_check(face.visible and face.emotion == &"happy", "Готовый раунд встречает улыбающимся солнцем")
	await _save("ready")
	var transform := game.slingshot.get_global_transform_with_canvas()
	var pulled := transform * Vector2(-70, 30)
	var shots := game.shots_left
	_pointer(transform.origin, true, touch)
	_drag(pulled, touch)
	await create_timer(0.15).timeout
	_check(game.slingshot.is_dragging and face.mood == &"focused", "Реальный жест сосредоточивает солнце")
	await _save("aim")
	var cat := game.slingshot.loaded_projectile
	_pointer(pulled, false, touch)
	_check(cat.was_launched and game.shots_left == shots - 1, "Жест запускает одного кота")
	await create_timer(0.22).timeout
	_check(face.mood == &"focused", "Солнце наблюдает за настоящим полётом")
	await _save("flight")
	game.set_paused(true)
	var frozen := [face.animation_time, face.gaze, face.emotion]
	await _save("pause")
	await create_timer(0.15, true).timeout
	_check([face.animation_time, face.gaze, face.emotion] == frozen, "Пауза останавливает взгляд и мимику")
	game.set_paused(false)
	await create_timer(0.08).timeout
	_check(face.animation_time > float(frozen[0]), "Продолжение возобновляет солнечную анимацию")
	# Только оформление результата: физическое прохождение этим вызовом не проверяется.
	game._complete_round(true)
	await create_timer(0.45).timeout
	_check(face.mood == &"delighted", "Результат победы включает радость")
	await _save("win")
	app.start_game(&"classic", &"scout")
	await _layout()
	game = app.game
	game.set_paused(false)
	game._complete_round(false)
	await create_timer(0.45).timeout
	face = (game.get_node("Backdrop/AmbientLife") as AmbientLife).sun_face
	_check(face.mood == &"sad", "Результат поражения включает сочувствие")
	await _save("loss")


func _capture_gallery() -> void:
	root.size = Vector2i(1280, 720)
	await _layout()
	var gallery := Node2D.new()
	root.add_child(gallery)
	var background := ColorRect.new()
	background.color = Color("c3e3e3")
	background.size = Vector2(1280, 720)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gallery.add_child(background)
	var emotions: Array[StringName] = [&"happy", &"focused", &"surprised", &"delighted", &"sad"]
	var titles := ["Улыбается", "Следит за котом", "Удивляется", "Радуется", "Сочувствует"]
	for index in emotions.size():
		var face := SunFace.new()
		face.position = Vector2(140 + index * 250, 325)
		face.scale = Vector2(2.3, 2.3)
		gallery.add_child(face)
		face.set_mood(emotions[index])
		face.focus_on(face.position + Vector2(-260, 180))
		face.advance(0.4)
		var label := Label.new()
		label.text = titles[index]
		label.add_theme_color_override("font_color", Color("385b50"))
		label.add_theme_font_size_override("font_size", 23)
		label.position = Vector2(25 + index * 250, 470)
		label.size = Vector2(230, 50)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gallery.add_child(label)
	await _save("expressions")
	gallery.queue_free()
	await _layout()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://.artifacts/sun-%s-%dx%d.png" % [name, root.size.x, root.size.y]
	_check(image.save_png(path) == OK, "Сохранён снимок " + path)


func _layout() -> void:
	for frame in 6:
		await process_frame


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 4
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _drag(point: Vector2, touch: bool) -> void:
	if touch:
		var event := InputEventScreenDrag.new()
		event.index = 4
		event.position = point
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
