extends SceneTree
## Первый жест остаётся рисунком: реальные события управляют только рогаткой.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const FIRST_LEVEL := preload("res://levels/campaign/01_first_throw.tres")
const OTHER_LEVEL := preload("res://levels/campaign/02_air_trick.tres")
const AimGestureVisual := preload("res://scripts/visuals/aim_gesture.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_scope()
	var game := await _new_game()
	var hint := game.slingshot.get_node("AimGesture") as AimGestureVisual
	_check(not hint.visible, "Первый показ начинается после короткой задержки")
	var initial_position := game.slingshot.loaded_projectile.global_position
	_show_hint(hint)
	_check(hint.visible, "Рука появляется перед первым броском")
	_check(game.slingshot.loaded_projectile.global_position.is_equal_approx(initial_position), "Демонстрация не передвигает настоящего кота")
	_check(game.shots_left == FIRST_LEVEL.shots and game.state == GameRound.RoundState.READY, "Демонстрация не тратит котов и не начинает полёт")
	_check(not hint.is_processing_input() and not hint.is_processing_unhandled_input(), "Рука не принимает события ввода")
	_test_mouse_cancellation(game, hint)
	_test_touch_cancellation(game, hint)
	_test_camera(game, hint)
	await _test_suspension(game, hint)
	_test_launch(game, hint)
	await _dispose_game(game)
	await _test_new_attempt()
	print("Aim gesture checks: %d passed, %d failed" % [_checks - _failures, _failures])
	await create_timer(0.3).timeout
	quit(1 if _failures else 0)


func _test_scope() -> void:
	for mode in ["sandbox", "other_tutorial", "editor"]:
		var game := MAIN_SCENE.instantiate() as GameRound
		game.level = OTHER_LEVEL if mode == "other_tutorial" else FIRST_LEVEL
		game.campaign_mode = mode != "sandbox"
		game.editor_preview = mode == "editor"
		root.add_child(game)
		current_scene = game
		await _settle()
		_check(not game.slingshot.has_node("AimGesture"), "Рука отсутствует вне первого урока кампании: " + mode)
		await _dispose_game(game)


func _test_mouse_cancellation(game: GameRound, hint: AimGestureVisual) -> void:
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_mouse(anchor, true)
	_check(game.slingshot.is_dragging, "Видимая рука пропускает захват мышью")
	hint._process(0.0)
	_check(not hint.visible, "Захват кота скрывает демонстрацию до натяжения")
	_mouse_motion(anchor + Vector2(-50, 20))
	_mouse(anchor, false)
	_check(game.shots_left == FIRST_LEVEL.shots and not game.slingshot.is_dragging, "Отмена мышью не расходует кота")
	hint._process(0.2)
	_check(not hint.visible, "После отмены рука не возникает немедленно")
	_show_hint(hint)
	_check(hint.visible, "После отмены мышью подсказка возвращается")
	_mouse(anchor + Vector2(-20, 0), true)
	_check(not hint.visible, "Начало настоящего натяжения скрывает руку в том же событии")
	_mouse(anchor, false)
	_show_hint(hint)


func _test_touch_cancellation(game: GameRound, hint: AimGestureVisual) -> void:
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_touch(anchor, 4, true)
	_drag(anchor + Vector2(-45, 22), 4)
	_check(game.slingshot.is_dragging and not hint.visible, "Настоящее касание натягивает рогатку и сразу скрывает руку")
	_touch(anchor + Vector2(-45, 22), 4, false, true)
	_check(game.shots_left == FIRST_LEVEL.shots and not game.slingshot.is_dragging, "Отменённое касание не превращается в бросок")
	_show_hint(hint)
	_check(hint.visible, "После отменённого касания подсказка возвращается")


func _test_camera(game: GameRound, hint: AimGestureVisual) -> void:
	var pause_rect := game.hud._pause_button.get_global_rect()
	_touch(Vector2(400, 350), 10, true)
	_touch(Vector2(600, 350), 11, true)
	_drag(Vector2(350, 370), 10)
	_drag(Vector2(650, 370), 11)
	_touch(Vector2(350, 370), 10, false)
	_touch(Vector2(650, 370), 11, false)
	_check(game.camera.zoom.x > 1.0, "Подсказка не блокирует масштабирование двумя пальцами")
	_check(hint.get_global_transform_with_canvas().is_equal_approx(game.slingshot.get_global_transform_with_canvas()), "Рука сохраняет привязку к рогатке при масштабе и переносе")
	_check(game.hud._pause_button.get_global_rect().is_equal_approx(pause_rect), "Камера и подсказка не смещают интерфейс")
	_check(game.shots_left == FIRST_LEVEL.shots, "Масштабирование с подсказкой не запускает кота")
	game.camera.reset_view()


func _test_suspension(game: GameRound, hint: AimGestureVisual) -> void:
	_show_hint(hint)
	game.set_paused(true)
	_check(not hint.visible, "Пауза сразу скрывает руку")
	var paused_time := hint.visual_time
	await create_timer(0.06).timeout
	_check(is_equal_approx(hint.visual_time, paused_time), "Время демонстрации не идёт на паузе")
	game.set_paused(false)
	hint._process(0.2)
	_check(not hint.visible, "После паузы есть задержка перед новой демонстрацией")
	_show_hint(hint)
	_check(hint.visible, "После возобновления рука возвращается")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(paused and not hint.visible, "Потеря фокуса скрывает руку вместе с паузой игры")
	game.set_paused(false)
	_show_hint(hint)
	_check(not hint.visible, "Без фокуса демонстрация не возобновляется")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_show_hint(hint)
	_check(hint.visible, "После возвращения фокуса демонстрация доступна")
	game.hide()
	hint._process(0.1)
	var hidden_time := hint.visual_time
	await create_timer(0.06).timeout
	_check(not hint.visible and is_equal_approx(hint.visual_time, hidden_time), "В скрытой сцене демонстрация не продолжается")
	game.show()
	hint._process(0.1)
	_check(not hint.visible, "Возвращение в сцену не показывает середину старого жеста")
	_show_hint(hint)
	_check(hint.visible, "В видимой сцене демонстрация начинается снова")


func _test_launch(game: GameRound, hint: AimGestureVisual) -> void:
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	var pull := Vector2(-65, 28)
	_touch(anchor, 4, true)
	_drag(anchor + pull, 4)
	var cat := game.slingshot.loaded_projectile
	_touch(anchor + pull, 4, false)
	_check(game.shots_left == FIRST_LEVEL.shots - 1 and game.state == GameRound.RoundState.FLYING, "Обычный жест запускает ровно одного кота")
	_check(cat.linear_velocity.distance_to(-pull * game.slingshot.launch_speed) < 0.1, "Подсказка не меняет скорость броска")
	_check(not hint.visible and not hint.is_processing(), "Первый запуск выключает демонстрацию")
	game._finish_shot()
	_check(game.state == GameRound.RoundState.READY and not hint.visible and not hint.is_processing(), "При подготовке следующего кота рука не возвращается")


func _test_new_attempt() -> void:
	var game := await _new_game()
	var hint := game.slingshot.get_node("AimGesture") as AimGestureVisual
	_show_hint(hint)
	_check(hint.visible, "Новая попытка получает собственную демонстрацию")
	game._complete_round(true)
	_check(not hint.visible and not hint.is_processing(), "Завершение раунда скрывает подсказку даже без первого броска")
	await _dispose_game(game)


func _show_hint(hint: AimGestureVisual) -> void:
	hint._process(2.0)
	hint._process(0.1)


func _new_game() -> GameRound:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = FIRST_LEVEL
	game.campaign_mode = true
	root.add_child(game)
	current_scene = game
	await _settle()
	return game


func _dispose_game(game: GameRound) -> void:
	paused = false
	game.queue_free()
	await _settle()


func _settle() -> void:
	for frame in 4:
		await process_frame


func _touch(position: Vector2, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _drag(position: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = index
	root.push_input(event, true)


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
