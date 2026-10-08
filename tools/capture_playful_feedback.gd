extends SceneTree
## Графика обучения и праздника на ПК. Результаты задаются явно, без имитации физической победы.

const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Playful feedback screenshots require a graphical run.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	AudioServer.set_bus_mute(0, true)
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	GameLocalization.apply_locale("ru")
	await _layout()
	for index in CampaignCatalog.IDS.size():
		app.profile.record_win(CampaignCatalog.IDS[index], CampaignCatalog.LEVELS[index].par_shots, 3)
	for dimensions: Vector2i in WINDOW_SIZES:
		root.size = dimensions
		await _layout()
		await _capture_tutorial(app, dimensions.x != 1280)
		await _capture_result_art(app)
		await _check_immediate_next(app, dimensions.x != 1280)
	await _capture_final_warning(app)
	paused = false
	app.queue_free()
	await create_timer(0.5).timeout
	print("Playful feedback graphic checks: %d passed, %d failed. Images: .artifacts/playful-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _capture_tutorial(app: GameApp, touch: bool) -> void:
	app.start_campaign_level(0)
	await _layout()
	var game := app.game
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.set_paused(false)
	var hint := game._aim_gesture
	var backdrop := game.get_node("Backdrop")
	var initial_position := game.slingshot.loaded_projectile.global_position
	var background_time: float = backdrop.animation_time
	await _wait_for_hint(game, 0.4)
	_check(hint.visible and game.shots_left == game.level.shots, "The first gesture appears without spending a cat")
	_check(game.slingshot.loaded_projectile.global_position.is_equal_approx(initial_position), "The demonstration keeps the real projectile in its cradle")
	_check(backdrop.animation_time > background_time, "The landscape continues moving beside the lesson")
	await _shot("tutorial-touch")
	await _wait_for_hint(game, 1.6)
	await _shot("tutorial-pull")
	game.set_paused(true)
	background_time = backdrop.animation_time
	var hint_time: float = hint.visual_time
	await create_timer(0.12).timeout
	_check(not hint.visible and is_equal_approx(hint.visual_time, hint_time), "Pause hides and freezes the gesture")
	_check(is_equal_approx(background_time, backdrop.animation_time), "Pause freezes the landscape")
	await _shot("tutorial-pause")
	game.set_paused(false)
	await _wait_for_hint(game, 0.4)
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(paused and not hint.visible, "Losing application focus pauses the game and hides the hand")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(paused, "Returning focus keeps the explicit pause until resume")
	game.set_paused(false)
	await _wait_for_hint(game, 0.4)
	var transform := game.slingshot.get_global_transform_with_canvas()
	var pulled := transform * Vector2(-70, 30)
	_pointer(transform.origin, true, touch)
	_drag(pulled, touch)
	_check(game.slingshot.is_dragging and not hint.visible, "Real pointer capture immediately hides the demonstration")
	await _shot("tutorial-real-drag")
	_pointer(pulled, false, touch)
	_check(game.shots_left == game.level.shots - 1 and game.state == GameRound.RoundState.FLYING, "The real pointer gesture launches exactly one cat")
	_check(not hint.visible and not hint.is_processing(), "The hand stays off after the first real launch")
	await _shot("tutorial-real-launch")


func _capture_result_art(app: GameApp) -> void:
	app.start_campaign_level(4)
	await _layout()
	var game := app.game
	game.set_paused(false)
	# Только состояние HUD: этот сценарий не утверждает, что постройка пройдена.
	game.hud.show_result(true, 3, 3)
	var celebration := game.hud._result_celebration
	var backdrop := game.get_node("Backdrop")
	var background_time: float = backdrop.animation_time
	await _wait_for_celebration(celebration, 0.55)
	_check(celebration.cast.size() == 3 and celebration.cast[0].id == &"frost", "Result art uses the authored squad")
	_check(backdrop.animation_time > background_time, "The result leaves the landscape animation running")
	_check_result_layout(game.hud)
	await _shot("result-ui-jump")
	paused = true
	var celebration_time := celebration.elapsed
	background_time = backdrop.animation_time
	await create_timer(0.12).timeout
	_check(is_equal_approx(celebration.elapsed, celebration_time) and is_equal_approx(backdrop.animation_time, background_time), "Tree pause freezes both the result art and landscape")
	paused = false
	celebration.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	celebration_time = celebration.elapsed
	await create_timer(0.12).timeout
	_check(is_equal_approx(celebration.elapsed, celebration_time), "The result art freezes while application focus is lost")
	celebration.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await _wait_for_celebration(celebration, 1.9)
	_check(celebration.elapsed > celebration_time, "The result art resumes when focus returns")
	await _shot("result-ui-bow")
	await _wait_for_celebration(celebration, ResultCelebration.DURATION)
	_check(not celebration.is_processing() and celebration.visible, "The celebration finishes on a static team picture")
	await _shot("result-ui-finished")


func _check_immediate_next(app: GameApp, touch: bool) -> void:
	app.start_campaign_level(0)
	await _layout()
	var game := app.game
	game.set_paused(false)
	# Интеграция результата и перехода: исход вызван напрямую, а не физическим попаданием.
	game._complete_round(true)
	await create_timer(GameHUD.VICTORY_DELAY + GameHUD.RESULT_FADE_DURATION).timeout
	await _layout()
	_check(game.hud._result_celebration.elapsed < ResultCelebration.DURATION, "Result navigation is ready before the celebration finishes")
	var old_game: WeakRef = weakref(game)
	var started := Time.get_ticks_msec()
	var point := game.hud._next_button.get_global_rect().get_center()
	_pointer(point, true, touch)
	_pointer(point, false, touch)
	await _layout()
	_check(app.campaign_index == 1 and app.game != game and old_game.get_ref() == null, "Next immediately replaces the finished round through real pointer input")
	_check(Time.get_ticks_msec() - started < int(ResultCelebration.DURATION * 1000), "Next does not wait for the end of the celebration")
	_check(app.game.state == GameRound.RoundState.READY and app.game.shots_left == app.game.level.shots, "The new round starts ready with its full authored squad")
	await _shot("next-integration")


func _capture_final_warning(app: GameApp) -> void:
	root.size = Vector2i(960, 720)
	app.start_campaign_level(CampaignCatalog.IDS.size() - 1)
	await _layout()
	app.game.set_paused(false)
	for locale: String in ["ru", "de", "ur"]:
		GameLocalization.apply_locale(locale)
		# Только демонстрация HUD с вручную выставленным предупреждением сохранения.
		app.game.hud.show_result(true, 5, 3)
		app.game.hud.set_save_warning()
		await _layout()
		_check_result_layout(app.game.hud)
		_check(not app.game.hud._next_button.visible, "The final chapter has no Next action")
		await _wait_for_celebration(app.game.hud._result_celebration, 0.55)
		await _shot("final-warning-ui-" + locale)
	GameLocalization.apply_locale("ru")


func _wait_for_hint(game: GameRound, target: float) -> void:
	var deadline := Time.get_ticks_msec() + 5500
	while Time.get_ticks_msec() < deadline:
		if game._aim_gesture.visible and game._aim_gesture.visual_time >= target:
			return
		await process_frame
	_check(false, "The tutorial reaches its natural animation phase")


func _wait_for_celebration(celebration: ResultCelebration, target: float) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while celebration.elapsed < target and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(celebration.elapsed >= target, "The result reaches its natural animation phase")


func _check_result_layout(hud: GameHUD) -> void:
	for control: Control in [hud._result_title, hud._result_detail, hud._result_celebration, hud._overlay_menu_button]:
		_check(root.get_visible_rect().encloses(control.get_global_rect()), "Result control fits the viewport")
	_check(not hud._result_detail.get_global_rect().intersects(hud._result_celebration.get_global_rect()), "Celebrating heroes stay clear of the result text")
	if hud._next_button.visible:
		_check(root.get_visible_rect().encloses(hud._next_button.get_global_rect()), "Next remains visible")


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
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


func _drag(point: Vector2, touch: bool) -> void:
	if touch:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = point
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _layout() -> void:
	for frame in 6:
		await process_frame


func _shot(screen: String) -> void:
	await _layout()
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/playful-%s-%dx%d.png" % [screen, root.size.x, root.size.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Screenshot saved: " + screen)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
