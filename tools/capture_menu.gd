extends SceneTree
## Главная, карта и локальный рейтинг: графика и синтетический ввод на ПК.

const APP_SCENE := preload("res://scenes/app.tscn")
const DIMENSIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0
var _initial_quit_on_go_back: bool


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	_initial_quit_on_go_back = quit_on_go_back
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	var app := APP_SCENE.instantiate() as GameApp
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _layout()
	_check(app.campaign != null and app.campaign.page == &"home", "Application starts on the main menu")
	_check(not quit_on_go_back, "Main menu intercepts native Back before automatic quit")
	for dimensions in DIMENSIONS:
		root.size = dimensions
		app.profile.results.clear()
		app.show_campaign()
		await _layout()
		await _capture_empty_menu(app, dimensions)
		await _check_destinations(app)
		await _capture_progress(app, dimensions)
		await _capture_completion(app, dimensions)
	app.queue_free()
	await create_timer(0.3).timeout
	print("Menu graphic checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _capture_empty_menu(app: GameApp, dimensions: Vector2i) -> void:
	var menu := app.campaign
	_check(menu.continue_index == 0 and menu.continue_button.text.begins_with("Играть"), "Empty profile offers first yard")
	await _shot("home", dimensions)
	_check_layout(menu)
	if dimensions.x == 1280:
		await _check_animation(menu, dimensions)
	_click(menu.campaign_button, false)
	await _layout()
	_check(menu.page == &"campaign", "Mouse opens campaign from main menu")
	await _shot("campaign", dimensions)
	_check_layout(menu)
	for button in menu.level_buttons:
		_check(button.is_visible_in_tree() and root.get_visible_rect().encloses(button.get_global_rect()), "Every yard action is visible on the campaign page")
	for panel in menu.chapter_panels:
		_check(root.get_visible_rect().encloses(panel.get_global_rect()), "Every biome chapter fits the campaign page")
	_click(menu.level_buttons[1], true)
	await _layout()
	_check(app.game == null and app.campaign == menu, "Touching locked yard does not start a round")
	_click(menu.back_button, true)
	await _layout()
	_check(menu.page == &"home", "Touch on Back restores main menu")
	_click(menu.rating_button, true)
	await _layout()
	_check(menu.page == &"rating", "Touch opens local rating")
	await _shot("rating", dimensions)
	_check_layout(menu)
	_check_rating(menu)
	_key(KEY_ESCAPE)
	await _layout()
	_check(menu.page == &"home", "Escape closes rating")
	_click(menu.campaign_button, true)
	await _layout()
	root.go_back_requested.emit()
	await _layout()
	_check(menu.page == &"home", "System Back closes campaign page")
	_click(menu.continue_button, dimensions.x != 1280)
	await _layout()
	_check(app.game != null and app.game.campaign_mode and app.campaign_index == 0, "Main action starts first campaign yard by pointer")
	_check(quit_on_go_back == _initial_quit_on_go_back, "Starting a round restores the original native Back policy")
	_click(app.game.hud._pause_button, true)
	await _layout()
	_click(app.game.hud._overlay_menu_button, true)
	await _layout()
	_check(app.campaign != null and app.campaign.page == &"home", "Round menu returns to main menu")


func _check_destinations(app: GameApp) -> void:
	_click(app.campaign.sandbox_button, true)
	await _layout()
	_check(app.menu != null and app.campaign == null, "Touch opens sandbox hero selection")
	_click(app.menu.campaign_button, false)
	await _layout()
	_check(app.campaign != null and app.campaign.page == &"home", "Mouse returns from sandbox to main menu")
	_click(app.campaign.editor_button, false)
	await _layout()
	_check(app.editor != null and app.editor.visible, "Mouse opens level editor")
	var return_button: Button
	for node in app.editor.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == "Меню":
			return_button = button
			break
	_check(return_button != null, "Editor has a visible return action")
	if return_button != null:
		_click(return_button, true)
	else:
		app.editor.menu_requested.emit()
	await _layout()
	_check(app.campaign != null and app.campaign.page == &"home", "Touch returns from editor to main menu")


func _capture_progress(app: GameApp, dimensions: Vector2i) -> void:
	app.profile.record_win(CampaignCatalog.IDS[0], 1, 3)
	app.profile.record_win(CampaignCatalog.IDS[1], 3, 1)
	app.show_campaign()
	await _layout()
	_check(app.campaign.continue_index == 2 and app.campaign.continue_button.text.begins_with("Продолжить"), "Saved progress selects first unbeaten yard")
	await _shot("home-progress", dimensions)
	_check_layout(app.campaign)
	_click(app.campaign.campaign_button, true)
	await _layout()
	await _shot("campaign-progress", dimensions)
	_check_layout(app.campaign)
	_check(not app.campaign.level_buttons[2].disabled and app.campaign.level_buttons[3].disabled, "Progress unlocks exactly the next yard")
	_click(app.campaign.back_button, false)
	await _layout()
	_click(app.campaign.rating_button, false)
	await _layout()
	await _shot("rating-progress", dimensions)
	_check_layout(app.campaign)
	_check_rating(app.campaign)
	_click(app.campaign.back_button, true)
	await _layout()
	_click(app.campaign.continue_button, true)
	await _layout()
	_check(app.game != null and app.campaign_index == 2, "Touch on Continue enters next unbeaten yard")
	_click(app.game.hud._pause_button, true)
	await _layout()
	_click(app.game.hud._overlay_menu_button, true)
	await _layout()


func _capture_completion(app: GameApp, dimensions: Vector2i) -> void:
	for index in CampaignCatalog.IDS.size():
		app.profile.record_win(CampaignCatalog.IDS[index], CampaignCatalog.LEVELS[index].par_shots, 3)
	app.show_campaign()
	await _layout()
	_check(app.campaign.continue_index == 0 and app.campaign.continue_button.text.begins_with("Переиграть"), "Completed campaign offers replay")
	await _shot("home-complete", dimensions)
	_check_layout(app.campaign)
	_click(app.campaign.campaign_button, false)
	await _layout()
	await _shot("campaign-complete", dimensions)
	_check_layout(app.campaign)
	for button in app.campaign.level_buttons:
		_check(not button.disabled, "Completed campaign keeps all yards replayable")
	_click(app.campaign.back_button, true)
	await _layout()
	_click(app.campaign.rating_button, true)
	await _layout()
	await _shot("rating-complete", dimensions)
	_check_layout(app.campaign)
	_check_rating(app.campaign)
	_click(app.campaign.back_button, false)
	await _layout()
	_click(app.campaign.continue_button, false)
	await _layout()
	_check(app.game != null and app.game.campaign_mode and app.campaign_index == 0, "Replay action starts the first completed yard")
	_click(app.game.hud._pause_button, true)
	await _layout()
	_click(app.game.hud._overlay_menu_button, true)
	await _layout()


func _check_animation(menu: CampaignMenu, dimensions: Vector2i) -> void:
	var before_rect := menu.continue_button.get_global_rect()
	await RenderingServer.frame_post_draw
	var first := root.get_texture().get_image()
	_check(first.save_png("res://.artifacts/menu-animation-start-%dx%d.png" % [dimensions.x, dimensions.y]) == OK, "First animation frame saved")
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var second := root.get_texture().get_image()
	_check(second.save_png("res://.artifacts/menu-animation-end-%dx%d.png" % [dimensions.x, dimensions.y]) == OK, "Second animation frame saved")
	_check(first.get_data() != second.get_data(), "Decorative main-menu animation changes rendered pixels")
	_check(menu.continue_button.get_global_rect().is_equal_approx(before_rect), "Animation keeps the primary action stationary")


func _check_layout(menu: CampaignMenu) -> void:
	var buttons: Array[Button] = []
	for node in menu.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.is_visible_in_tree():
			continue
		buttons.append(button)
		_check(root.get_visible_rect().encloses(button.get_global_rect()), "Visible menu action fits viewport: " + button.text)
		_check(button.size.y >= 40.0, "Menu action retains a usable touch height: " + button.text)
	for first in buttons.size():
		for second in range(first + 1, buttons.size()):
			_check(not buttons[first].get_global_rect().intersects(buttons[second].get_global_rect()), "Menu actions do not overlap")


func _check_rating(menu: CampaignMenu) -> void:
	_check(menu.rating_rows.size() == CampaignCatalog.LEVELS.size(), "Local rating lists exactly the campaign yards")
	_check("%d/18" % CampaignCatalog.total_stars(menu.profile) in menu.rating_summary.text.replace(" ", ""), "Local rating summary matches saved stars")
	for index in menu.rating_rows.size():
		var row := menu.rating_rows[index]
		_check(row.is_visible_in_tree() and root.get_visible_rect().encloses(row.get_global_rect()), "Local rating row fits viewport")
		var best := menu.profile.best_shots_for(CampaignCatalog.IDS[index])
		if best < 0:
			_check("не пройден" in row.text.to_lower(), "Unplayed yard displays no invented record")
		else:
			_check("Рекорд: %d" % best in row.text, "Played yard displays saved best shot count")


func _click(button: BaseButton, touch: bool) -> void:
	_check(button.is_visible_in_tree(), "Pointer targets a visible action")
	var point := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
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


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)


func _layout() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.25).timeout


func _shot(screen: String, dimensions: Vector2i) -> void:
	await _layout()
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/menu-chapters-%s-%dx%d.png" % [screen, dimensions.x, dimensions.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Menu screenshot saved")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
