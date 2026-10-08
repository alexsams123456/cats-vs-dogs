extends SceneTree
## Графическая проверка пейзажа, паузы и ввода в трёх пропорциях окна.
## Godot --path . --script res://tools/capture_nature.gd

const APP_SCENE := preload("res://scenes/app.tscn")
const BACKDROP := preload("res://scripts/world/backdrop.gd")
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для снимков природы нужен графический запуск без --headless.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute("res://.artifacts") != OK:
		push_error("Не удалось создать папку .artifacts.")
		quit(1)
		return
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	for window_size: Vector2i in WINDOW_SIZES:
		root.size = window_size
		app.start_game(&"classic", &"scout")
		await create_timer(0.45).timeout
		if not is_instance_valid(app.game):
			_verify(false, "Открылся бой для снимка природы")
			break
		app.game.set_paused(false)
		await _save_image("battle", 0.25)
		app.show_editor()
		await create_timer(0.35).timeout
		if not is_instance_valid(app.editor):
			_verify(false, "Открылся редактор для снимка природы")
			break
		_verify(app.editor.is_visible_in_tree(), "Поле редактора видно после перехода из боя")
		await _save_image("editor", 0.2)
	root.size = WINDOW_SIZES[0]
	for touch: bool in [false, true]:
		app.start_game(&"classic", &"scout")
		await create_timer(0.45).timeout
		if not is_instance_valid(app.game):
			_verify(false, "Открылся бой для проверки ввода")
			break
		await _check_shot(app.game, touch)
	paused = false
	app.queue_free()
	await process_frame
	await _capture_landscape()
	print("Nature previews: %d passed, %d failed. Images: .artifacts/nature-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _check_shot(game: GameRound, touch: bool) -> void:
	game.set_paused(false)
	await process_frame
	var cat := game.slingshot.loaded_projectile
	if not is_instance_valid(cat):
		_verify(false, "В рогатке есть кот для проверки ввода")
		return
	var backdrop := game.get_node("Backdrop")
	var start_time: float = backdrop.animation_time
	var shots := game.shots_left
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_press(anchor, true, touch)
	_press(anchor + Vector2(-95, 42), false, touch)
	var input_name := "touch" if touch else "mouse"
	_verify(cat.was_launched and game.shots_left == shots - 1, "%s запускает ровно одного кота" % input_name)
	await _save_image("shot-" + input_name, 0.3)
	_verify(backdrop.animation_time > start_time, "Природа продолжает двигаться во время выстрела")
	game.set_paused(true)
	var paused_time: float = backdrop.animation_time
	await create_timer(0.3, true).timeout
	_verify(is_equal_approx(backdrop.animation_time, paused_time), "Игровая пауза останавливает время природы")
	game.set_paused(false)
	await create_timer(0.15).timeout
	_verify(backdrop.animation_time > paused_time, "После игровой паузы природа оживает")


func _capture_landscape() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var backdrop := BACKDROP.new()
	world.add_child(backdrop)
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	world.add_child(camera)
	camera.make_current()
	var first := await _save_image("landscape-before", 0.5)
	var first_time: float = backdrop.animation_time
	var second := await _save_image("landscape-after", 3.0)
	_verify(backdrop.animation_time - first_time >= 2.8, "Между кадрами пейзажа прошло не менее 2.8 секунд анимации")
	_verify(first.get_data() != second.get_data(), "Пейзаж меняется без героев и интерфейса")
	paused = true
	var paused_time: float = backdrop.animation_time
	var frozen := await _save_image("landscape-paused", 0.15)
	await create_timer(0.35, true).timeout
	await RenderingServer.frame_post_draw
	var still_frozen := root.get_texture().get_image()
	_verify(is_equal_approx(backdrop.animation_time, paused_time), "Время отдельного пейзажа неподвижно на паузе")
	_verify(frozen.get_data() == still_frozen.get_data(), "На паузе пиксели пейзажа остаются неизменными")
	paused = false
	var resumed := await _save_image("landscape-resumed", 0.5)
	_verify(backdrop.animation_time > paused_time, "Время отдельного пейзажа продолжилось")
	_verify(frozen.get_data() != resumed.get_data(), "После паузы рисунок пейзажа снова меняется")
	world.queue_free()
	await process_frame


func _press(position: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _save_image(screen: String, delay: float) -> Image:
	await create_timer(delay, true).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://.artifacts/nature-%s-%dx%d.png" % [screen, root.size.x, root.size.y]
	_verify(image.save_png(path) == OK, "Сохранён снимок " + path)
	return image


func _verify(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
