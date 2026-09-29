extends SceneTree
## Графическая проверка камеры и настоящего ввода; профиль и черновик не открываются.
## Godot --path . --script res://tools/capture_camera.gd

const GAME_SCENE := preload("res://scenes/main.tscn")
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для снимков камеры нужен графический запуск без --headless.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute("res://.artifacts") != OK:
		push_error("Не удалось создать папку .artifacts.")
		quit(1)
		return
	GameLocalization.apply_locale("ru")
	for window_size: Vector2i in WINDOW_SIZES:
		root.size = window_size
		var game := _round()
		await _layout()
		game.set_paused(false)
		await _check_views(game)
		await _check_shot(game, false)
		game.queue_free()
		await process_frame
		game = _round()
		await _layout()
		game.set_paused(false)
		await _check_shot(game, true)
		game.queue_free()
		await process_frame
	paused = false
	print("Camera graphic checks: %d passed, %d failed. Images: .artifacts/camera-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _round() -> GameRound:
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = CampaignCatalog.LEVELS[0].duplicate(true) as LevelDefinition
	game.campaign_mode = true
	game.has_next_level = true
	root.add_child(game)
	return game


func _check_views(game: GameRound) -> void:
	var camera := game.camera
	var hud_controls: Array[Control] = [game.hud._pause_button, game.hud._stats, game.hud._hint]
	var hud_rects: Array[Rect2] = []
	for control: Control in hud_controls:
		hud_rects.append(control.get_global_rect())
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Начальный масштаб равен единице")
	await _capture("normal")
	var center := root.get_visible_rect().get_center()
	_pinch(center, 110.0, 176.0)
	_check(is_equal_approx(camera.zoom.x, 1.6), "Разведение пальцев приближает поле")
	_check(not game.slingshot.is_dragging and game.shots_left == game.level.shots, "Жест камеры не расходует котов")
	await _capture("zoom-in")
	var position_before := camera.position
	var zoom_before := camera.zoom
	var displacement := Vector2(65, 30)
	_touch(center - Vector2(120, 0), true, 10)
	_touch(center + Vector2(120, 0), true, 11)
	_drag(center - Vector2(120, 0) + displacement, 10)
	_drag(center + Vector2(120, 0) + displacement, 11)
	_touch(center - Vector2(120, 0) + displacement, false, 10)
	_touch(center + Vector2(120, 0) + displacement, false, 11)
	_check(camera.zoom.is_equal_approx(zoom_before), "Перемещение двух пальцев сохраняет масштаб")
	_check(camera.position.distance_to(position_before - displacement / zoom_before.x) < 0.1, "Перемещение двух пальцев сдвигает поле")
	await _capture("pan")
	_pinch(center, 180.0, 45.0)
	_check(is_equal_approx(camera.zoom.x, camera.min_zoom), "Сведение пальцев показывает минимальный масштаб")
	_check(camera.position.is_equal_approx(Vector2(640, 360)), "На минимальном масштабе показан весь двор")
	await _capture("zoom-out")
	for index in hud_controls.size():
		_check(hud_controls[index].get_global_rect().is_equal_approx(hud_rects[index]), "Масштаб поля не меняет положение и размер HUD")
	_click(game.hud._pause_button, true)
	_check(paused, "Касание кнопки ставит игру на паузу после жеста")
	var paused_position := camera.position
	var paused_zoom := camera.zoom
	_pinch(center, 100.0, 160.0)
	_check(camera.position.is_equal_approx(paused_position) and camera.zoom.is_equal_approx(paused_zoom), "Пауза блокирует масштабирование")
	await _capture("pause")
	_click(game.hud._resume_button, true)
	_check(not paused, "Касание возобновляет игру")
	_pinch(center, 100.0, 140.0)
	_check(camera.zoom.x > paused_zoom.x, "После паузы новый жест снова работает")
	await _capture("resumed")


func _check_shot(game: GameRound, touch: bool) -> void:
	game.camera.reset_view()
	var focus := game.slingshot.get_global_transform_with_canvas().origin + Vector2(50, -80)
	_pinch(focus, 100.0, 145.0)
	_check(game.camera.zoom.x > 1.0, "Выстрел проверяется после приближения")
	var cat := game.slingshot.loaded_projectile
	if not _check(is_instance_valid(cat), "Кот доступен для проверки выстрела"):
		return
	var shots_before := game.shots_left
	var transform := game.slingshot.get_global_transform_with_canvas()
	var start := transform.origin
	var end := transform * Vector2(-95, 42)
	_pointer(start, true, touch)
	_motion(end, touch)
	_check(game.slingshot.is_dragging, "Рогатка принимает указатель в увеличенном мире")
	_check(cat.global_position.distance_to(game.slingshot.global_position + Vector2(-95, 42)) < 0.1, "Прицеливание учитывает масштаб камеры")
	await _capture("aim-" + ("touch" if touch else "mouse"))
	_pointer(end, false, touch)
	_check(cat.was_launched and game.shots_left == shots_before - 1, "Отпускание запускает ровно одного кота")
	var launch_position := cat.global_position
	await create_timer(0.15).timeout
	_check(cat.global_position.distance_to(launch_position) > 20.0, "После масштабирования кот летит в настоящей физике")
	await _capture("shot-" + ("touch" if touch else "mouse"))


func _pinch(center: Vector2, from_radius: float, to_radius: float) -> void:
	_touch(center - Vector2(from_radius, 0), true, 10)
	_touch(center + Vector2(from_radius, 0), true, 11)
	_drag(center - Vector2(to_radius, 0), 10)
	_drag(center + Vector2(to_radius, 0), 11)
	_touch(center - Vector2(to_radius, 0), false, 10)
	_touch(center + Vector2(to_radius, 0), false, 11)


func _click(button: BaseButton, touch: bool) -> void:
	var point := button.get_global_rect().get_center()
	_pointer(point, true, touch)
	_pointer(point, false, touch)


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		_touch(point, pressed, 0)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _motion(point: Vector2, touch: bool) -> void:
	if touch:
		_drag(point, 0)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _touch(point: Vector2, pressed: bool, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = pressed
	root.push_input(event, true)


func _drag(point: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point
	event.index = index
	root.push_input(event, true)


func _layout() -> void:
	for frame in 5:
		await process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/camera-%s-%dx%d.png" % [label, root.size.x, root.size.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Сохранён снимок " + path)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition
