extends SceneTree
## Compact combat UI, folded guidance and ability feedback through real GUI events.

const GAME_SCENE := preload("res://scenes/main.tscn")
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0
var _music_playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HUD screenshots require a graphical run without --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	AudioServer.set_bus_mute(0, true)
	GameLocalization.apply_locale("ru")
	for window_size: Vector2i in WINDOW_SIZES:
		root.size = window_size
		GameLocalization.apply_locale("ru")
		for cat: CharacterDefinition in CharacterCatalog.CATS:
			var game := _round(cat)
			await _layout()
			game.set_paused(false)
			_check(not game.hud._help_card.visible and game.hud._current_portrait.definition == cat, "The current cat stays visible while detailed help starts folded")
			_check_layout(game.hud)
			if cat == CharacterCatalog.CATS[0]:
				await _capture("compact")
			_click(game.hud._help_button, false)
			await _layout()
			_check(game.hud._help_card.visible and game.hud._help_portrait.definition == cat, "Requested help explains the current cat")
			_check(game.hud._help_card.get_global_rect().end.y < 400.0, "Help stays above the slingshot")
			await _capture(String(cat.id))
			await _remove(game)
		for touch: bool in [false, true]:
			var game := _round(CharacterCatalog.CATS[0])
			await _layout()
			game.set_paused(false)
			await _check_controls(game, touch)
			await _remove(game)
			game = _round(CharacterCatalog.CATS[0])
			await _layout()
			game.set_paused(false)
			await _check_contact(game, touch)
			await _remove(game)
		for campaign_index: int in [0, CampaignCatalog.LEVELS.size() - 1]:
			var game := _round(CharacterCatalog.CATS[0], campaign_index)
			await _layout()
			game.set_paused(false)
			if campaign_index == 0:
				_check(game.level.tutorial == &"aim" and game.hud._hint.text.begins_with("Шаг 1/2"), "The authored first yard retains its aiming lesson")
				_check_layout(game.hud)
				_check_footer_layout(game.hud)
				_check(root.get_visible_rect().encloses(game.hud._hint.get_global_rect()) and not game.hud._hint.get_global_rect().intersects(game.hud._current_card.get_global_rect()), "Aiming guidance fits beside the compact current cat")
				await _capture("tutorial")
			else:
				_click(game.hud._pause_button, true)
				await _layout()
				_check_pause_layout(game.hud)
				_check(game.hud._queue_label.text.count("→") + 1 == game.level.cat_sequence.size(), "Pause includes the full final-yard squad without truncation")
				await _capture("final-pause")
				game.set_paused(false)
			await _remove(game)
		for locale: String in GameLocalization.SUPPORTED_LOCALES:
			if window_size.x != 960 and locale not in ["ar", "ur"]:
				continue
			GameLocalization.apply_locale(locale)
			var game := _round(CharacterCatalog.find_cat(&"homing"))
			await _layout()
			game.set_paused(false)
			game.hud.set_touch_ui(true)
			await _layout()
			_check_layout(game.hud)
			await _capture("locale-" + locale + "-compact")
			_click(game.hud._help_button, true)
			await _layout()
			_check(root.get_visible_rect().encloses(game.hud._help_card.get_global_rect()), "Translated help stays on screen: " + locale)
			_check(game.hud._help_card.get_global_rect().end.y < 400.0, "Translated help stays above the slingshot: " + locale)
			await _capture("locale-" + locale)
			_click(game.hud._help_button, true)
			# This UI-only state checks translated text; _check_contact covers real physics.
			game.hud.set_ability_state(GameHUD.AbilityState.CONTACTED)
			await _layout()
			_check_footer_layout(game.hud)
			await _capture("locale-" + locale + "-contact")
			_click(game.hud._pause_button, true)
			await _layout()
			_check_pause_layout(game.hud)
			await _capture("locale-" + locale + "-pause")
			game.set_paused(false)
			await _remove(game)
	paused = false
	var audio_deadline := Time.get_ticks_msec() + 1000
	while not _music_released() and Time.get_ticks_msec() < audio_deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(_music_released(), "Removed rounds release their music playback")
	print("HUD help graphic checks: %d passed, %d failed. Images: .artifacts/hud-help-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _round(cat: CharacterDefinition, campaign_index: int = -1) -> GameRound:
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = CampaignCatalog.LEVELS[maxi(campaign_index, 0)].duplicate(true) as LevelDefinition
	if campaign_index < 0:
		game.level.tutorial = &""
		game.level.cat_sequence = PackedStringArray()
	game.cat_definition = cat
	game.campaign_mode = true
	game.has_next_level = true
	root.add_child(game)
	return game


func _check_controls(game: GameRound, touch: bool) -> void:
	var hud := game.hud
	var camera := game.camera
	var mode := "touch" if touch else "mouse"
	# Zoom with the normal wheel, then exercise the camera button with each pointer.
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(700, 450)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel, true)
	_check(camera.zoom.x > 1.0, "Wheel zooms the game before using Whole yard")
	_click(hud._camera_button, touch)
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Whole-yard button resets the camera using " + mode)
	_check(game.shots_left == game.level.shots and not game.slingshot.is_dragging, "Camera action does not start or spend a throw")
	_click(hud._help_button, touch)
	_check(hud._help_card.visible, "Help can be opened using " + mode)
	_click(hud._help_button, touch)
	_check(not hud._help_card.visible, "Help can be collapsed using " + mode)
	_click(hud._help_button, touch)
	await _capture(mode + "-ready")
	var transform := game.slingshot.get_global_transform_with_canvas()
	var start := transform.origin
	var pulled := transform * Vector2(-85, 45)
	_pointer(start, true, touch)
	_motion(pulled, touch)
	_check(game.slingshot.is_dragging, "Open guide leaves the slingshot gesture available")
	_pointer(pulled, false, touch)
	_check(game.state == GameRound.RoundState.FLYING and game.shots_left == game.level.shots - 1, "A genuine pointer throw launches one cat")
	_check(not hud._help_card.visible, "Launch automatically collapses the guide")
	_check(hud._ability_state == GameHUD.AbilityState.READY and not hud._ability_button.disabled, "The launched cat presents a ready ability")
	await _capture(mode + "-flying")
	_check(hud._ability_button.text.contains("E") != touch, "The action shows a keyboard shortcut only for mouse input")
	_click(hud._help_button, touch)
	_check(hud._help_card.visible and game.shots_left == game.level.shots - 1, "Opening help during flight does not spend another cat")
	_click(hud._ability_button, touch)
	_check(game._active_cat.ability_spent, "The ability button remains usable after opening help")
	_check(hud._ability_state == GameHUD.AbilityState.USED and hud._ability_button.disabled, "The used ability is clearly disabled")
	_click(hud._help_button, touch)
	await _capture(mode + "-used")
	_click(hud._pause_button, touch)
	await _layout()
	_check(paused and hud._pause_details.is_visible_in_tree(), "Pause exposes details using " + mode)
	_check_pause_layout(hud)
	var portrait_time := hud._help_portrait.visual_time
	var current_time := hud._current_portrait.visual_time
	await create_timer(0.1).timeout
	_check(is_equal_approx(portrait_time, hud._help_portrait.visual_time) and is_equal_approx(current_time, hud._current_portrait.visual_time), "Hero portraits freeze while the game is paused")
	await _capture(mode + "-pause")
	_click(hud._resume_button, touch)
	_check(not paused and not hud._queue_label.is_visible_in_tree() and not hud._score_hint.is_visible_in_tree(), "Resume restores compact combat using " + mode)


func _check_contact(game: GameRound, touch: bool) -> void:
	var transform := game.slingshot.get_global_transform_with_canvas()
	var pulled := transform * Vector2(-60, -20)
	_pointer(transform.origin, true, touch)
	_motion(pulled, touch)
	_pointer(pulled, false, touch)
	var cat := game._active_cat
	_check(is_instance_valid(cat) and game.shots_left == game.level.shots - 1, "Contact scenario starts with a real pointer throw")
	if not is_instance_valid(cat):
		return
	for frame in 120:
		await physics_frame
		if cat.has_contacted():
			break
	_check(cat.has_contacted() and not cat.ability_spent, "The cat contacts the ground with its ability unused")
	_check(game.hud._ability_state == GameHUD.AbilityState.CONTACTED and game.hud._ability_button.disabled, "Contact explains why the unused ability is unavailable")
	await _capture(("touch" if touch else "mouse") + "-contact")


func _check_layout(hud: GameHUD) -> void:
	var bounds := root.get_visible_rect()
	for control: Control in [hud._level_label, hud._stats, hud._camera_button, hud._help_button, hud._pause_button, hud._current_portrait, hud._current_name, hud._ability_status]:
		_check(control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()), "Compact combat control stays visible inside the window")
	if hud._ability_button.visible:
		_check(bounds.encloses(hud._ability_button.get_global_rect()), "The ability action stays inside the window")
	_check(not hud._queue_label.is_visible_in_tree() and not hud._score_hint.is_visible_in_tree() and not hud._camera_hint.is_visible_in_tree(), "Detailed rules and camera instructions stay off the compact field")
	_check(not hud._camera_button.get_global_rect().intersects(hud._help_button.get_global_rect()) and not hud._help_button.get_global_rect().intersects(hud._pause_button.get_global_rect()), "Header actions do not overlap")


func _check_pause_layout(hud: GameHUD) -> void:
	for control: Control in [hud._queue_label, hud._score_hint, hud._resume_button, hud._overlay_menu_button]:
		_check(control.is_visible_in_tree() and root.get_visible_rect().encloses(control.get_global_rect()), "Pause details and navigation stay visible inside the window")


func _check_footer_layout(hud: GameHUD) -> void:
	var card := hud._current_card.get_global_rect()
	for control: Control in [hud._current_card, hud._ability_status, hud._ability_button]:
		_check(root.get_visible_rect().encloses(control.get_global_rect()), "The current cat and its translated action status stay on screen")
	_check(card.encloses(hud._ability_status.get_global_rect()) and card.encloses(hud._ability_button.get_global_rect()), "The action and translated status stay inside the current-cat card")
	_check(not hud._ability_status.get_global_rect().intersects(hud._ability_button.get_global_rect()), "The translated status and ability action do not overlap")


func _click(button: BaseButton, touch: bool) -> void:
	var point := button.get_global_rect().get_center()
	_pointer(point, true, touch)
	_pointer(point, false, touch)


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


func _motion(point: Vector2, touch: bool) -> void:
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
	for frame in 5:
		await process_frame


func _capture(screen: String) -> void:
	await _layout()
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/hud-help-%s-%dx%d.png" % [screen, root.size.x, root.size.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Screenshot saved: " + screen)


func _remove(game: GameRound) -> void:
	_music_playbacks.append(weakref(game.background_music.get_stream_playback()))
	game.queue_free()
	await _layout()


func _music_released() -> bool:
	for playback: WeakRef in _music_playbacks:
		if playback.get_ref() != null:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
