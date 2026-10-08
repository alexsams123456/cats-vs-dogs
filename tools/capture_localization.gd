extends SceneTree
## Переключение языков и раскладка на ПК; профиль и черновик пользователя не меняются.

const APP_SCENE := preload("res://scenes/app.tscn")
const DIMENSIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _settle()
	for dimensions in DIMENSIONS:
		root.size = dimensions
		await _settle()
		for locale in GameLocalization.SUPPORTED_LOCALES:
			var index := GameLocalization.SUPPORTED_LOCALES.find(locale)
			# Настоящее открытие списка мышью или синтетическим касанием, выбор клавишами.
			var picker := app.campaign.language_picker
			_click(picker, dimensions.x == 960)
			await _settle()
			_check(picker.get_popup().visible, "Language list opens by pointer: %s" % locale)
			if locale == "ru" and dimensions.x == 1280:
				await _shot("languages", locale, dimensions)
			var popup := picker.get_popup()
			var focused := popup.get_focused_item()
			var steps := index + 1 if focused < 0 else posmod(index - focused, popup.item_count)
			for step in steps:
				_key(KEY_DOWN)
			_check(popup.get_focused_item() == index, "Keyboard focuses chosen language")
			_key(KEY_ENTER)
			await _settle()
			_check(app.profile.locale == locale, "Language selected: %s" % locale)
			_check(app.campaign.language_picker.selected == index, "Picker retains selected language")
			_check_menu(app.campaign)
			await _shot("home", locale, dimensions)
			app.campaign.show_page(&"campaign")
			await _settle()
			_check_menu(app.campaign)
			if dimensions.x == 960:
				await _shot("campaign", locale, dimensions)
			app.campaign.show_page(&"rating")
			await _settle()
			_check_menu(app.campaign)
			if dimensions.x == 960:
				await _shot("rating", locale, dimensions)
			app.campaign.show_page(&"home")
			if dimensions.x == 960 and locale in ["en", "zh_CN", "hi", "ar", "bn", "ur", "de", "ja"]:
				await _check_screens(app, locale, dimensions)
	app.queue_free()
	await _settle()
	print("Localization graphics: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _check_screens(app: GameApp, locale: String, dimensions: Vector2i) -> void:
	app.show_sandbox()
	await _settle()
	for button: Button in [app.menu.play_button, app.menu.editor_button, app.menu.campaign_button, app.menu.previous_page_button, app.menu.next_page_button]:
		_check(root.get_visible_rect().encloses(button.get_global_rect()), "Sandbox navigation stays visible: %s" % locale)
	await _shot("roster", locale, dimensions)
	app.show_editor()
	await _settle()
	_check(root.get_visible_rect().encloses(app.editor.play_button.get_global_rect()), "Editor play remains visible: %s" % locale)
	_check(root.get_visible_rect().encloses(app.editor.canvas.get_global_rect()), "Editor field remains visible: %s" % locale)
	_check(root.get_visible_rect().encloses(app.editor._status.get_global_rect()), "Editor status remains visible: %s" % locale)
	await _shot("editor", locale, dimensions)
	app.show_campaign()
	await _settle()
	app.start_campaign_level(0)
	await _settle()
	for button: Button in [app.game.hud._pause_button, app.game.hud._camera_button, app.game.hud._help_button]:
		_check(root.get_visible_rect().encloses(button.get_global_rect()), "Game navigation stays visible: %s" % locale)
	await _shot("game", locale, dimensions)
	app.game.set_paused(true)
	await _settle()
	for control: Control in [app.game.hud._overlay_menu_button, app.game.hud._queue_label, app.game.hud._score_hint]:
		_check(control.is_visible_in_tree() and root.get_visible_rect().encloses(control.get_global_rect()), "Pause navigation and details stay visible: %s" % locale)
	await _shot("pause", locale, dimensions)
	app.show_campaign()
	await _settle()
	_check(app.profile.locale == locale, "Locale survives all screen changes")


func _check_menu(menu: CampaignMenu) -> void:
	var bounds := root.get_visible_rect()
	_check(bounds.encloses(menu.language_picker.get_global_rect()), "Language picker stays inside window")
	if menu.page == &"home":
		for button: Button in [menu.continue_button, menu.campaign_button, menu.rating_button, menu.editor_button, menu.sandbox_button]:
			_check(bounds.encloses(button.get_global_rect()), "Main action fits window: %s" % button.text)
		_check(not menu._title.get_global_rect().intersects(menu._home_panel.get_global_rect()), "Title and main actions do not overlap")
	else:
		_check(bounds.encloses(menu.back_button.get_global_rect()), "Menu return fits window")


func _click(button: Control, touch: bool) -> void:
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


func _settle() -> void:
	for frame in 6:
		await process_frame
	await create_timer(0.35).timeout


func _shot(screen: String, locale: String, dimensions: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/locale-%s-%s-%dx%d.png" % [locale, screen, dimensions.x, dimensions.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Screenshot saved")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
