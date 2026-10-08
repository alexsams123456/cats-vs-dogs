extends SceneTree
## Настройки ПК: запись, ввод, защита модального окна и графика.

const APP_SCENE := preload("res://scenes/app.tscn")
var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture = "--capture-desktop" in OS.get_cmdline_user_args()
	_path = "user://desktop_test_%d.json" % Time.get_ticks_usec()
	_test_preferences()
	await _test_app()
	if _capture:
		await _test_graphics()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_path + suffix):
			DirAccess.remove_absolute(_path + suffix)
	GameLocalization.apply_locale("ru")
	print("Desktop options checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_preferences() -> void:
	var profile := PlayerProfile.new(_path)
	_check(profile.desktop.keys == DesktopPreferences.DEFAULT_KEYS and profile.desktop.screen_shake, "Defaults preserve original controls and shake")
	_check(profile.desktop.bind_key(0, KEY_Q) == OK, "Ability can use a custom physical key")
	_check(profile.desktop.bind_key(1, KEY_Q) == ERR_ALREADY_IN_USE, "Two actions cannot share a key")
	_check(profile.desktop.bind_key(0, KEY_ESCAPE) != OK and profile.desktop.bind_key(0, KEY_F11) != OK, "Escape and system function keys are protected")
	profile.desktop.screen_shake = false
	profile.desktop.reduced_particles = true
	profile.record_win("first_throw", 2, 3)
	var restored := PlayerProfile.new(_path)
	restored.load_data()
	_check(restored.desktop.keys[0] == KEY_Q and not restored.desktop.screen_shake and restored.desktop.reduced_particles, "Controls and effect options survive a reload")
	_check(restored.stars_for("first_throw") == 3 and restored.rewards.has("first_win"), "Desktop settings preserve progress and rewards")
	for invalid: Variant in ["bad", {}, {"keys": [KEY_Q, KEY_Q, KEY_SPACE, KEY_HOME]}, {"keys": [1.5, KEY_R, KEY_SPACE, KEY_HOME]}, {"keys": [KEY_F11, KEY_R, KEY_SPACE, KEY_HOME]}, {"keys": "bad"}]:
		var options := DesktopPreferences.new()
		options.load_data(invalid)
		_check(options.keys == DesktopPreferences.DEFAULT_KEYS, "Malformed and conflicting saved keys use defaults")


func _test_app() -> void:
	var old_ability := InputMap.action_get_events("ability")
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	await _settle()
	var options := _options(app.campaign)
	_click(options, false)
	await _settle()
	_check(options.dialog.visible, "Menu button opens PC settings")
	_click(options.binding_buttons[0], false)
	_key(options.dialog, KEY_Q)
	await _settle()
	_check(app.profile.desktop.keys[0] == KEY_Q and options.binding_buttons[0].text == "Q", "Real dialog key input changes binding")
	_click(options.binding_buttons[1], true)
	_key(options.dialog, KEY_Q)
	_check(app.profile.desktop.keys[1] == KEY_R and options._listening == 1, "Conflicting key leaves previous binding intact")
	_key(options.dialog, KEY_ESCAPE)
	_check(options.dialog.visible and options._listening == -1, "Escape cancels key capture without closing dialog")
	options.dialog.hide()
	app.start_campaign_level(0)
	await _settle()
	var game := app.game
	_check("Q" in game.hud._ability_button.text, "HUD displays chosen ability key")
	var launches: int = game.shots_left
	game.slingshot.launch_from_pull(Vector2(-70, 31))
	_key(root, KEY_Q, false, 0x419)
	_check(game._active_cat.ability_spent and game.shots_left == launches - 1, "Physical key activates ability under a different layout without extra launches")
	app.profile.desktop.keys[2] = KEY_P
	app._on_desktop_settings_changed()
	var shortcut := InputEventKey.new()
	shortcut.physical_keycode = KEY_R
	shortcut.pressed = true
	shortcut.ctrl_pressed = true
	root.push_input(shortcut, true)
	await _settle()
	_check(app.game == game, "Ctrl combinations do not trigger gameplay shortcuts")
	_key(root, KEY_P)
	await _settle()
	_check(paused, "Custom pause key pauses the round")
	options = _options(game.hud)
	_click(options, true)
	await _settle()
	_check(options.dialog.visible and paused, "PC settings open from pause by touch")
	_click(options.binding_buttons[1], false)
	_key(options.dialog, KEY_T)
	await _settle()
	_check(app.game == game and paused and app.profile.desktop.keys[1] == KEY_T, "Capturing restart key does not restart or resume game")
	options.shake_toggle.button_pressed = false
	options.particles_toggle.button_pressed = true
	_check(game.camera.max_impact_pixels == 0 and game.camera.offset == Vector2.ZERO, "Shake can be disabled during pause and existing offset cleared")
	_check((game.get_node("ImpactFeedback") as ImpactFeedback).reduced_particles, "Particle setting reaches the running round")
	_key(options.dialog, KEY_ESCAPE)
	await _settle()
	_check(not options.dialog.visible and paused, "Escape closes the settings window without resuming the parent round")
	options.open_settings()
	await _settle()
	app._go_back()
	_check(not options.dialog.visible and paused, "Native Back closes only the child settings window")
	_key(root, KEY_ESCAPE)
	await _settle()
	_check(not paused, "Fixed Escape still resumes after remapping pause")
	var feedback := game.get_node("ImpactFeedback") as ImpactFeedback
	feedback._pending = {"strength": 900.0, "point": Vector2(600, 400), "material": &"wood", "direction": Vector2.RIGHT}
	feedback._present_pending()
	_check(feedback.get_child_count() == 1 and (feedback.get_child(0) as ImpactBurst).fragment_count == 4, "Reduced mode creates four decorative fragments per burst")
	game.camera.zoom = Vector2(1.5, 1.5)
	_key(root, KEY_HOME)
	_check(game.camera.zoom == Vector2.ONE, "Overview key restores camera zoom")
	_key(root, KEY_T, true)
	await _settle()
	_check(app.game == game, "Holding restart does not repeat the action")
	_key(root, KEY_T)
	await _settle()
	_check(app.game != game and app.game.camera.max_impact_pixels == 0 and (app.game.get_node("ImpactFeedback") as ImpactFeedback).reduced_particles, "Custom restart recreates round with saved visual preferences")
	if _capture:
		await _shot("game")
	app.game.set_paused(true)
	options = _options(app.game.hud)
	options.open_settings()
	await _settle()
	_click(options.binding_buttons[0], false)
	for button in options.find_children("*", "Button", true, false):
		if button.text == tr("Сбросить клавиши"):
			_click(button, true)
	_check(app.profile.desktop.keys == DesktopPreferences.DEFAULT_KEYS and options._listening == -1 and InputMap.action_get_events("ability")[0].physical_keycode == KEY_E, "Reset restores default bindings and cancels active capture")
	options.dialog.hide()
	app.game.set_paused(false)
	app.queue_free()
	await _settle()
	_check(InputMap.action_get_events("ability")[0].physical_keycode == old_ability[0].physical_keycode, "Removing app restores original input map for other scenes")


func _test_graphics() -> void:
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	await _settle()
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		await _settle()
		var options := _options(app.campaign)
		_check(root.get_visible_rect().encloses(options.get_global_rect()), "PC button fits menu header")
		_click(options, false)
		await _settle()
		_check(options.dialog.size.x <= root.get_visible_rect().size.x and options.dialog.size.y <= root.get_visible_rect().size.y, "Settings fit viewport")
		await _shot("menu-%dx%d" % [dimensions.x, dimensions.y])
		if dimensions.x == 1280:
			options.fullscreen_toggle.button_pressed = true
			await _settle()
			_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Fullscreen option changes native window mode")
			options.fullscreen_toggle.button_pressed = false
			await _settle()
			_check(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN, "Fullscreen can return to windowed mode")
		options.dialog.hide()
	for locale in GameLocalization.SUPPORTED_LOCALES:
		GameLocalization.apply_locale(locale)
		app.show_campaign()
		await _settle()
		var options := _options(app.campaign)
		options.open_settings()
		await _settle()
		await _shot(locale)
		options.dialog.hide()
	GameLocalization.apply_locale("ru")
	app.start_campaign_level(0)
	await _settle()
	app.game.set_paused(true)
	_options(app.game.hud).open_settings()
	await _settle()
	await _shot("pause")
	app.queue_free()
	await _settle()


func _options(parent: Node) -> DesktopOptions:
	for node in parent.find_children("*", "", true, false):
		if node is DesktopOptions:
			return node
	return null


func _key(viewport: Viewport, code: int, echo: bool = false, label: int = 0) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = label if label != 0 else code
	event.pressed = true
	event.echo = echo
	viewport.push_input(event, true)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	release.echo = false
	viewport.push_input(release, true)


func _click(button: BaseButton, touch: bool) -> void:
	var point := button.get_global_rect().get_center()
	if button.get_window() != root:
		point += Vector2(button.get_window().position)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = point
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(event, true)


func _settle() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.08).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture.save_png("res://.artifacts/desktop-%s.png" % label) == OK, "Desktop screenshot saved")
	for child in root.get_children():
		if child is GameApp:
			for window in child.find_children("*", "Window", true, false):
				if window.visible:
					var image: Image = window.get_texture().get_image()
					_check(image.save_png("res://.artifacts/desktop-dialog-%s.png" % label) == OK, "Dialog screenshot saved")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
