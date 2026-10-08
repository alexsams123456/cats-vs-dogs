extends SceneTree
## Настоящие переходы, блокировка ввода, пауза и размеры экрана.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		await _test_size(dimensions)
	print("Screen transition checks: %d passed, %d failed" % [_checks - _failures, _failures])
	# При --fixed-fps игровые таймеры быстрее реального аудиопотока.
	OS.delay_msec(300)
	quit(1 if _failures else 0)


func _test_size(dimensions: Vector2i) -> void:
	root.size = dimensions
	var app := preload("res://scenes/app.tscn").instantiate() as GameApp
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await create_timer(0.4).timeout
	await process_frame
	var old_menu := app.campaign
	_pointer(old_menu.continue_button.get_global_rect().get_center(), false, true)
	_pointer(old_menu.continue_button.get_global_rect().get_center(), false, false)
	_check(app._transition_pending and app.has_node("ScreenTransition"), "Mouse starts the transition")
	_check(old_menu.process_mode == Node.PROCESS_MODE_DISABLED, "Outgoing screen stops accepting actions")
	await create_timer(0.10).timeout
	var curtain := app.get_node("ScreenTransition/Curtain") as ScreenTransition
	_check(curtain.progress > 0.0 and curtain.progress < 1.0 and app.game == null, "Fade advances before replacing the menu")
	_check(curtain.get_global_rect().is_equal_approx(root.get_visible_rect()), "Curtain covers viewport")
	await _shot("out", dimensions)
	app.show_editor()
	app.start_campaign_level(0)
	root.go_back_requested.emit()
	_key(KEY_ESCAPE)
	_check(app.campaign == old_menu and app.editor == null, "Repeated requests and Back are blocked")
	root.size = Vector2i(dimensions.x + 24, dimensions.y)
	await process_frame
	_check(curtain.get_global_rect().is_equal_approx(root.get_visible_rect()), "Curtain follows resize")
	root.size = dimensions
	# Палец остаётся прижатым до конца анимации.
	_pointer(Vector2(180, 540), true, true)
	while app.game == null:
		await process_frame
	_check(curtain.progress > 0.9, "Level replaces menu under opaque curtain")
	_key(KEY_ESCAPE)
	root.go_back_requested.emit()
	_check(app.game.state == GameRound.RoundState.READY and not paused and not app.game.hud.can_process(), "Incoming pause HUD cannot consume keys during reveal")
	await _shot("in", dimensions)
	await _settle(app)
	_pointer(Vector2(180, 540), true, false)
	_check(app.game != null and app.game.state == GameRound.RoundState.READY, "Held touch does not launch or pause the new level")
	_check(app.game.process_mode == Node.PROCESS_MODE_INHERIT, "Incoming level resumes after reveal")
	await _shot("level", dimensions)
	var music := app.get_node("BackgroundMusic")
	app.game.toggle_pause()
	_check(paused, "Round is paused before restart")
	app._restart_round()
	await _settle(app)
	_check(not paused and app.game.state == GameRound.RoundState.READY, "Restart transition works from paused round")
	_check(app.get_node("BackgroundMusic") == music, "Screen changes preserve the music node")
	app.game.state = GameRound.RoundState.WON
	app._on_round_completed(true, 1, 3)
	app._next_campaign_level()
	await _settle(app)
	_check(app.campaign_index == 1 and app.game.level.title == CampaignCatalog.LEVELS[1].title, "Next level uses the same transition")
	app.game.toggle_pause()
	await process_frame
	_pointer(app.game.hud._overlay_menu_button.get_global_rect().get_center(), true, true)
	_pointer(app.game.hud._overlay_menu_button.get_global_rect().get_center(), true, false)
	await _settle(app)
	_check(app.campaign != null and app.game == null and not paused, "Touch returns from paused level to menu")
	await _shot("menu", dimensions)
	app.show_sandbox()
	await _settle(app)
	_check(app.menu != null, "Sandbox transition completes")
	app.show_editor()
	await _settle(app)
	var editor := app.editor
	var draft := editor.draft
	app.start_editor_game(draft)
	await _settle(app)
	_check(app.game != null and app.game.editor_preview, "Editor preview opens with transition")
	app.game.return_to_menu()
	await _settle(app)
	_check(app.editor == editor and editor.draft == draft and editor.visible, "Returning from preview preserves editor draft")
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func _settle(app: GameApp) -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while app._transition_pending and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not app._transition_pending and not app.has_node("ScreenTransition"), "Transition completes and removes input blocker")


func _shot(phase: String, dimensions: Vector2i) -> void:
	if "--capture-transitions" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/transition-%s-%d.png" % [phase, dimensions.x])


func _pointer(point: Vector2, touch: bool, pressed: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 7
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
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
