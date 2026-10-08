extends SceneTree
## Графический путь кампании с мышью и синтетическими касаниями на ПК.

const ROUTES: Dictionary = preload("res://tools/solve_campaign.gd").ROUTES

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await create_timer(0.4).timeout
	_check(app.campaign != null and app.campaign.page == &"home" and app.menu == null, "Startup opens main menu")
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		app.profile.results.clear()
		app.profile.rewards.clear()
		app.show_campaign()
		await _layout()
		_check(app.campaign != null and app.campaign.page == &"home", "Main menu opens before yard selection")
		if app.campaign == null:
			break
		await _shot("home", dimensions)
		for button: Button in [app.campaign.continue_button, app.campaign.campaign_button, app.campaign.rating_button, app.campaign.sandbox_button, app.campaign.editor_button]:
			_check(button.is_visible_in_tree() and root.get_visible_rect().encloses(button.get_global_rect()), "Main navigation fits screen")
		_click(app.campaign.campaign_button, dimensions.x != 1280)
		await _layout()
		_check(app.campaign.page == &"campaign", "Main menu opens campaign map by pointer")
		await _shot("map", dimensions)
		for button in app.campaign.level_buttons:
			var parent := button.get_parent()
			while parent != null and not parent is ScrollContainer:
				parent = parent.get_parent()
			if parent is ScrollContainer:
				parent.ensure_control_visible(button)
				await _layout()
			_check(button.is_visible_in_tree() and root.get_visible_rect().encloses(button.get_global_rect()), "Every campaign yard is reachable on the scrolling map")
		_click(app.campaign.back_button, dimensions.x != 1280)
		await _layout()
		_check(app.campaign.continue_button.text.begins_with("Играть"), "First visit offers Play")
		_click(app.campaign.continue_button, dimensions.x != 1280)
		await create_timer(0.9).timeout
		_check(app.game != null and app.game.campaign_mode, "Campaign yard opens by pointer")
		var game: GameRound = app.game
		await _shot("aim", dimensions)
		var first_route: Array = ROUTES["01_first_throw"].duplicate(true)
		# После паузы и снимков обломки могут остановиться иначе: запасные коты
		# добивают дальнюю опору настоящими бросками в пределах отряда.
		first_route.append([-74.25, 74.25, 0.7])
		first_route.append([-80.43, 67.49, 0.9])
		var first_pull := Vector2(first_route[0][0], first_route[0][1])
		var launch := game.slingshot.get_global_transform_with_canvas().origin
		_pointer(launch, true, dimensions.x != 1280)
		_drag(launch + first_pull, dimensions.x != 1280)
		await _shot("drag", dimensions)
		_check(game.slingshot.is_dragging and "Шаг 2" in game.hud._hint.text, "Drag advances aim tutorial")
		_pointer(launch + first_pull, false, dimensions.x != 1280)
		await create_timer(0.1).timeout
		_check(game.shots_left == game.level.shots - 1, "Pointer release spends exactly one shot")
		game.set_paused(true)
		await _shot("pause", dimensions)
		_click(game.hud._resume_button, true)
		await _finish_route(game, first_route, 1)
		var first_used := game.level.shots - game.shots_left
		if not _check(game.state == GameRound.RoundState.WON and app.profile.stars_for(CampaignCatalog.IDS[0]) == game.level.stars_for_shots(first_used), "Real pointer throws win and save the earned stars"):
			await _finish(app)
			return
		await create_timer(GameHUD.VICTORY_DELAY + GameHUD.RESULT_FADE_DURATION).timeout
		await _shot("first-victory", dimensions)
		_check(app.profile.rewards.has("first_win") and game.hud._reward_notice.visible, "Real campaign victory grants and announces its first badge")
		_click(game.hud._next_button, true)
		await _layout()
		_check(app.campaign_index == 1, "Next yard opens by touch after victory")
		game = app.game
		await create_timer(0.8).timeout
		var second_route: Array = ROUTES["02_air_trick"].duplicate(true)
		second_route.append([-74.25, 74.25, 0.7])
		second_route.append([-80.43, 67.49, -1.0])
		second_route.append([-80.43, 67.49, 0.9])
		var second_pull := Vector2(second_route[0][0], second_route[0][1])
		launch = game.slingshot.get_global_transform_with_canvas().origin
		_pointer(launch, true, true)
		_drag(launch + second_pull, true)
		_pointer(launch + second_pull, false, true)
		while game._flight_time + 0.0001 < second_route[0][2] / Slingshot.FLIGHT_SPEED_SCALE and game.state == GameRound.RoundState.FLYING:
			await physics_frame
		if dimensions.x == 1280:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_E
			key.pressed = true
			root.push_input(key, true)
			key = key.duplicate() as InputEventKey
			key.pressed = false
			root.push_input(key, true)
		else:
			_click(game.hud._ability_button, true)
		_check(game._tutorial_ability_used, "E or touch activates the current cat ability")
		await _shot("ability", dimensions)
		await _finish_route(game, second_route, 1)
		var second_used := game.level.shots - game.shots_left
		print("Pointer campaign ", dimensions, " first shots=", first_used, " second shots=", second_used)
		if not _check(game.state == GameRound.RoundState.WON and app.profile.stars_for(CampaignCatalog.IDS[1]) == game.level.stars_for_shots(second_used), "Touch and ability win the second level and save the earned stars"):
			await _finish(app)
			return
		_click(game.hud._overlay_menu_button, true)
		await _layout()
		_check(app.campaign != null and not paused, "Result returns to campaign")
		_check(app.campaign.continue_index == 2 and app.campaign.continue_button.text.begins_with("Продолжить"), "Continue selects next unbeaten yard")
		app.campaign.show_page(&"campaign")
		await _shot("progress-map", dimensions)
		_click(app.campaign.back_button, true)
		await _layout()
		_click(app.campaign.sandbox_button, true)
		await _layout()
		_check(app.menu != null, "Sandbox opens optional hero selection")
		await _shot("sandbox", dimensions)
		_click(app.menu.campaign_button, true)
		await _layout()
		_check(app.campaign != null, "Sandbox returns to campaign")
		_click(app.campaign.editor_button, true)
		await _layout()
		_check(app.editor != null and app.editor.visible, "Campaign opens editor directly")
		app.editor.menu_requested.emit()
		await _layout()
		_check(app.campaign != null, "Editor returns to campaign")
	# Results and later mixed loadouts have their own view in each aspect ratio.
	for index in CampaignCatalog.IDS.size():
		app.profile.record_win(CampaignCatalog.IDS[index], CampaignCatalog.LEVELS[index].par_shots, 3)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		app.show_campaign()
		await _layout()
		app.campaign.show_page(&"campaign")
		await _shot("complete-map", dimensions)
		_check(app.campaign.continue_button.text.begins_with("Переиграть"), "Complete campaign offers replay")
		app.start_campaign_level(5)
		await create_timer(0.9).timeout
		await _shot("mixed", dimensions)
		app.game.hud.show_result(true, 5, 3)
		await _shot("result", dimensions)
		_check(root.get_visible_rect().encloses(app.game.hud._overlay_menu_button.get_global_rect()), "Result navigation fits screen")
		app.show_menu()
		await _layout()
	await _finish(app)


func _finish(app: GameApp) -> void:
	if _failures > 0:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.artifacts/campaign-failed.png")
	app.queue_free()
	await create_timer(0.2).timeout
	print("Campaign graphic checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _wait_for_shot(game: GameRound) -> void:
	for tick in 1800:
		if game.state != GameRound.RoundState.FLYING:
			return
		await physics_frame


func _finish_route(game: GameRound, route: Array, start_index: int) -> void:
	await _wait_for_shot(game)
	for index in range(start_index, route.size()):
		if game.state == GameRound.RoundState.WON:
			return
		if game.state != GameRound.RoundState.READY:
			break
		var shot: Array = route[index]
		var anchor := game.slingshot.get_global_transform_with_canvas().origin
		var pull := Vector2(shot[0], shot[1])
		var before := game.shots_left
		_pointer(anchor, true, true)
		_drag(anchor + pull, true)
		_pointer(anchor + pull, false, true)
		_check(game.shots_left == before - 1, "Each follow-up gesture launches exactly one cat")
		if shot[2] >= 0.0:
			while game._flight_time + 0.0001 < shot[2] / Slingshot.FLIGHT_SPEED_SCALE and game.state == GameRound.RoundState.FLYING:
				await physics_frame
			if game.state == GameRound.RoundState.FLYING:
				var could_activate := is_instance_valid(game._active_cat) and game._active_cat.can_activate_ability()
				_click(game.hud._ability_button, true)
				if could_activate:
					_check(not is_instance_valid(game._active_cat) or game._active_cat.ability_spent, "Follow-up touch actually activates the available ability")
		await _wait_for_shot(game)


func _click(button: BaseButton, touch: bool = false) -> void:
	var point := button.get_global_rect().get_center()
	_pointer(point, true, touch)
	_pointer(point, false, touch)


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
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
		event.position = point
		event.index = 0
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = point
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)


func _layout() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.15).timeout


func _shot(screen: String, dimensions: Vector2i) -> void:
	await _layout()
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/campaign-%s-%dx%d.png" % [screen, dimensions.x, dimensions.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Screenshot saved")


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	return condition
