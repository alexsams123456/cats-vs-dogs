extends SceneTree
## Переход запуска, блокировка ввода и возвращение в меню без повторной заставки.

const STARTUP_SCENE := preload("res://scenes/startup.tscn")
const DIMENSIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/startup.tscn", "Normal launch uses the animated entrance")
	for dimensions in DIMENSIONS:
		await _test_size(dimensions)
	print("Startup checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_size(dimensions: Vector2i) -> void:
	root.size = dimensions
	var app := STARTUP_SCENE.instantiate() as GameApp
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	var menu := app.campaign
	var intro := app.get_node("StartupTransition/Splash") as StartupTransition
	_check(intro.modulate.a == 1.0 and menu._margin.modulate.a == 0.0, "First scene frame continues the opaque boot splash")
	_check(menu.page == &"home" and app._transition_pending, "Menu is prepared behind the splash")
	await process_frame
	await _shot("begin", dimensions)
	_check(intro.get_global_rect().is_equal_approx(root.get_visible_rect()), "Splash covers the entire viewport at %s" % dimensions)
	_pointer(menu.continue_button.get_global_rect().get_center(), false)
	_pointer(menu.continue_button.get_global_rect().get_center(), true)
	_key(KEY_ENTER)
	_key(KEY_SPACE)
	_key(KEY_ESCAPE)
	root.go_back_requested.emit()
	app.show_sandbox()
	await process_frame
	_check(app.game == null and app.menu == null and app.campaign == menu, "Mouse, touch, keyboard and Back cannot leave the entrance")
	await create_timer(0.45).timeout
	_check(intro.modulate.a > 0.0 and intro.modulate.a < 1.0, "Splash dissolves gradually")
	_check(menu._margin.modulate.a > 0.0 and menu._margin.modulate.a < 1.0, "Menu controls fade in during the dissolve")
	await _shot("middle", dimensions)
	# Перераскладка во время анимации должна сохранить полноэкранный фон.
	root.size = Vector2i(dimensions.x + 24, dimensions.y)
	await process_frame
	_check(intro.get_global_rect().is_equal_approx(root.get_visible_rect()), "Resize during the entrance keeps the screen covered")
	root.size = dimensions
	# Удержанное касание заставки не превращается в нажатие кнопки после неё.
	var held := InputEventScreenTouch.new()
	held.index = 3
	held.position = menu.continue_button.get_global_rect().get_center()
	held.pressed = true
	root.push_input(held, true)
	await create_timer(1.0).timeout
	await process_frame
	held.pressed = false
	root.push_input(held, true)
	_check(not app._transition_pending and not app.has_node("StartupTransition"), "Entrance finishes and removes its input blocker")
	_check(menu._margin.modulate.a == 1.0 and menu._startup_progress == 1.0, "Menu finishes fully visible at its final layout")
	_check(app.game == null, "Releasing a touch held over the entrance does not start a level")
	for button: Button in [menu.continue_button, menu.campaign_button, menu.sandbox_button]:
		_check(root.get_visible_rect().encloses(button.get_global_rect()), "Menu action fits viewport after the entrance")
	await _shot("end", dimensions)
	_pointer(menu.rating_button.get_global_rect().get_center(), false)
	await process_frame
	_check(menu.page == &"rating", "Mouse works after the entrance")
	_key(KEY_ESCAPE)
	await create_timer(0.35).timeout
	_pointer(menu.sandbox_button.get_global_rect().get_center(), true)
	await process_frame
	await process_frame
	_check(app.menu != null, "Direct touch opens sandbox after the entrance")
	app.show_campaign()
	await process_frame
	await process_frame
	_check(app.campaign != null and not app.has_node("StartupTransition") and not app._transition_pending, "Returning to main menu does not replay the splash")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func _pointer(point: Vector2, touch: bool) -> void:
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.index = 0
			event.position = point
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event, true)


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)


func _shot(phase: String, dimensions: Vector2i) -> void:
	if "--capture-startup" not in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	var path := "res://.artifacts/startup-%s-%dx%d.png" % [phase, dimensions.x, dimensions.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Startup frame saved")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
