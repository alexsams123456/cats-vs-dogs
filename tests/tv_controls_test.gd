extends SceneTree
## Полный путь пульта: меню, прицел, бросок, способность, пауза и результат.

const APP := preload("res://scenes/app.tscn")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(TVControls.is_enabled(), "Test requires --tv")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		var app := APP.instantiate() as GameApp
		app.profile_path = ""
		app.animate_screen_changes = false
		root.add_child(app)
		await _frames()
		_check(not app.campaign.editor_button.visible, "Pointer editor hidden on TV")
		for options: Node in app.find_children("*", "DesktopOptions", true, false):
			_check(not (options as Control).visible, "Keyboard settings hidden on TV")
		_check(root.gui_get_focus_owner() == app.campaign.continue_button, "Menu starts focused")
		_key(KEY_DOWN)
		await _frames()
		_check(root.gui_get_focus_owner() == app.campaign.campaign_button, "D-pad reaches campaign")
		_key(KEY_ENTER)
		await _frames()
		_check(app.campaign.page == &"campaign", "OK opens campaign")
		_key(KEY_DOWN)
		await _frames()
		_check(root.gui_get_focus_owner() != app.campaign.back_button, "D-pad reaches level")
		await _capture("campaign")
		_key(KEY_ESCAPE)
		await _frames()
		_check(app.campaign.page == &"home", "Back closes campaign page")
		app.campaign.sandbox_button.grab_focus()
		_key(KEY_ENTER)
		await _frames()
		_check(is_instance_valid(app.menu) and not app.menu.editor_button.visible, "OK opens TV sandbox without editor")
		app.menu.card_buttons[1].grab_focus()
		_key(KEY_ENTER)
		_check(app.selected_cat_id == &"bomb", "OK selects another cat")
		app.menu.next_page_button.grab_focus()
		_key(KEY_ENTER)
		await _frames()
		_check(app.menu.current_page == 1, "OK pages through heroes")
		await _capture("sandbox")
		_key(KEY_ESCAPE)
		await _frames()
		_check(is_instance_valid(app.campaign), "Back leaves sandbox")
		app.campaign.continue_button.grab_focus()
		_key(KEY_ENTER)
		await _frames()
		_check(is_instance_valid(app.game), "OK starts level")
		if not is_instance_valid(app.game):
			app.queue_free()
			await _frames()
			continue
		var game := app.game
		var controls := app.get_node("TVControls") as TVControls
		_check(root.gui_get_focus_owner() == null, "Battle gives keys to aiming")
		_check(game.slingshot.is_dragging and game.slingshot.loaded_projectile.freeze, "Ready preview keeps cat loaded")
		var ready_shots := game.shots_left
		_key(KEY_ESCAPE)
		await _frames()
		_check(paused and not game.slingshot.is_dragging and game.shots_left == ready_shots, "Back cancels preview without firing")
		_key(KEY_ENTER)
		await _frames()
		_check(not paused and game.slingshot.is_dragging, "Preview restored on resume")
		_key(KEY_UP)
		_key(KEY_LEFT)
		await _frames()
		_check(is_equal_approx(controls.angle, 37.0) and is_equal_approx(controls.power, 0.95), "Directions adjust aim")
		_check(game.hud._hint.text.contains("37°") and game.hud._hint.text.contains("95%"), "Aim values visible")
		for index in 50:
			_key(KEY_DOWN, true)
			_key(KEY_LEFT, true)
		_check(is_equal_approx(controls.angle, 5.0) and is_equal_approx(controls.power, 0.25), "Held directions clamp low")
		for index in 50:
			_key(KEY_UP, true)
			_key(KEY_RIGHT, true)
		_check(is_equal_approx(controls.angle, 80.0) and is_equal_approx(controls.power, 1.0), "Held directions clamp high")
		controls.angle = 35.0
		controls._update_aim(game)
		await _capture("aim")
		var cat := game.slingshot.loaded_projectile
		var ability_count: Array[int] = [0]
		cat.ability_used.connect(func() -> void: ability_count[0] += 1)
		var shots := game.shots_left
		_key(KEY_ENTER, true)
		_check(game.shots_left == shots, "OK repeat does not launch")
		_key(KEY_ENTER)
		_check(game.state == GameRound.RoundState.FLYING and game.shots_left == shots - 1, "OK launches once")
		_check(ability_count[0] == 0, "Launch release does not activate ability")
		_key(KEY_ENTER, true)
		_check(ability_count[0] == 0, "Holding OK cannot activate ability")
		_key(KEY_ESCAPE)
		await _frames()
		_check(paused and root.gui_get_focus_owner() == game.hud._resume_button, "Back pauses and focuses resume")
		_key(KEY_UP)
		await _frames()
		_check(game.hud._overlay.is_ancestor_of(root.gui_get_focus_owner()), "Pause focus stays inside overlay")
		game.hud._resume_button.grab_focus()
		var position := cat.position
		await _frames()
		_check(cat.position.is_equal_approx(position), "Pause stops physical flight")
		await _capture("pause")
		_key(KEY_ENTER)
		await _frames()
		_check(not paused and ability_count[0] == 0, "OK resumes without spending ability")
		_key(KEY_ENTER)
		_key(KEY_ENTER)
		_check(ability_count[0] == 1, "Flight OK activates ability once")
		game.state = GameRound.RoundState.WON
		game.hud.show_result(true, 1, 3)
		await _frames()
		_check(root.gui_get_focus_owner() != null and game.hud._overlay.is_ancestor_of(root.gui_get_focus_owner()), "Result owns focus")
		await _capture("result")
		_key(KEY_ESCAPE)
		await _frames()
		_check(is_instance_valid(app.campaign) and not is_instance_valid(app.game), "Back returns from result to menu")
		app.queue_free()
		await _frames()
	print("TV controls checks: %d passed, %d failed" % [_checks - _failures, _failures])
	await create_timer(0.3).timeout
	quit(1 if _failures else 0)


func _frames() -> void:
	for index in 6:
		await process_frame


func _key(key: Key, echo: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		event.echo = echo and pressed
		root.push_input(event, true)


func _capture(label: String) -> void:
	if "--capture-tv" not in OS.get_cmdline_user_args():
		return
	if label == "result":
		await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/tv-%s-%dx%d.png" % [label, root.size.x, root.size.y])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("TV: " + message)
