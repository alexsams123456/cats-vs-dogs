extends SceneTree
## Compact combat controls keep guidance, pause details and real ability feedback accessible.

const GAME_SCENE := preload("res://scenes/main.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_locale := TranslationServer.get_locale()
	GameLocalization.apply_locale("ru")
	var hud := GameHUD.new()
	root.add_child(hud)
	hud.set_campaign(true, true, 3)
	hud.set_queue(PackedStringArray(["Рыжик", "Искра", "Следопыт"]), false)
	await _settle()
	for cat: CharacterDefinition in CharacterCatalog.CATS:
		hud.set_loadout(cat, CharacterCatalog.DOGS[0], true)
		hud.update_status("Урок", 3, 2, false)
		await _settle()
		_check(not hud._help_card.visible and hud._current_portrait.definition == cat and hud._current_name.text.contains(cat.display_name), "%s: the current cat is identified without opening a guide" % cat.id)
		_check(not hud._power_hint.is_visible_in_tree() and not hud._camera_hint.is_visible_in_tree(), "%s: detailed instructions stay folded" % cat.id)
		await _click(hud._help_button)
		_check(hud._help_card.visible and hud._help_portrait.definition == cat, "%s: requested help shows the matching portrait" % cat.id)
		_check(hud._help_description.text == cat.description and not cat.description.is_empty(), "%s: explains the effect instead of only its key" % cat.id)
		hud.update_status("Урок", 2, 2, true)
		_check(not hud._help_card.visible, "%s: launch clears the explanation from the field" % cat.id)
	hud.set_loadout(CharacterCatalog.CATS[0], CharacterCatalog.DOGS[0])
	hud.update_status("Урок", 2, 2, false)
	_check(not hud._help_card.visible, "Repeated cats do not automatically reopen an already shown explanation")
	await _test_buttons(hud)
	_test_input_hints(hud)
	await _test_layouts(hud)
	hud.set_loadout(CharacterCatalog.CATS[0], CharacterCatalog.DOGS[0])
	hud.show_result(true, 2, 3)
	_check(not hud._help_card.visible and not hud._help_button.visible and not hud._camera_button.visible, "Result hides gameplay help controls")
	_check(not hud._pause_details.is_visible_in_tree(), "Result hides pause-only squad details")
	var touch_after_result := InputEventScreenTouch.new()
	touch_after_result.pressed = true
	hud._input(touch_after_result)
	var mouse_after_result := InputEventMouseButton.new()
	mouse_after_result.pressed = true
	mouse_after_result.button_index = MOUSE_BUTTON_LEFT
	hud._input(mouse_after_result)
	_check(hud._hint.text.is_empty() and hud._power_hint.text.is_empty(), "Changing the input device on the result screen does not restore gameplay instructions")
	hud.queue_free()
	await _settle()
	GameLocalization.apply_locale("ru")
	await _test_real_ability_states()
	GameLocalization.apply_locale(original_locale)
	print("HUD help checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_buttons(hud: GameHUD) -> void:
	hud.update_status("Урок", 2, 2, true)
	var camera_events: Array[bool] = []
	var ability_events: Array[bool] = []
	hud.camera_reset_requested.connect(func() -> void: camera_events.append(true))
	hud.ability_requested.connect(func() -> void: ability_events.append(true))
	await _click(hud._help_button)
	_check(hud._help_card.visible, "Mouse reopens the current cat's explanation during flight")
	_check(hud._help_card.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud._help_portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Explanation and portrait do not consume aiming gestures")
	hud.update_status("Урок", 2, 1, true)
	_check(hud._help_card.visible, "A target update does not dismiss manually opened help")
	await _click(hud._camera_button)
	_check(camera_events == [true] and ability_events.is_empty(), "Whole-yard button requests only the camera reset")
	await _tap(hud._help_button)
	_check(not hud._help_card.visible, "Touch can close the explanation again")
	hud.set_campaign(false, false, 0)
	hud.set_loadout(CharacterCatalog.CATS[0], CharacterCatalog.DOGS[0])
	_check(not hud._help_card.visible, "Sandbox starts with compact help")
	await _tap(hud._help_button)
	_check(hud._help_card.visible, "Sandbox retains access to the same explanation")
	hud.set_campaign(true, true, 3)
	hud.show_pause(true)
	await _settle()
	_check(hud._pause_details.is_visible_in_tree() and hud._queue_label.is_visible_in_tree() and hud._score_hint.is_visible_in_tree(), "Pause exposes the ordered squad and star thresholds")
	_check(hud._queue_label.text.contains("Рыжик") and hud._score_hint.text.contains("≤ 3"), "Moving details into pause preserves their contents")
	hud.show_pause(false)
	_check(not hud._queue_label.is_visible_in_tree() and not hud._score_hint.is_visible_in_tree(), "Returning to the field folds squad and reward details")


func _test_input_hints(hud: GameHUD) -> void:
	hud.set_loadout(CharacterCatalog.CATS[0], CharacterCatalog.DOGS[0])
	hud.set_touch_ui(true)
	hud.set_tutorial_hint("Шаг 2/2. Нажми на игровое поле в полёте, до удара.")
	_check(not hud._ability_button.text.contains("E") and not hud._power_hint.text.contains("E") and not hud._hint.text.contains("E"), "Touch mode removes keyboard advice from the action, power and lesson")
	_check(hud._camera_hint.text.begins_with("Два пальца"), "Touch mode teaches pinch and pan")
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.pressed = true
	emulated.button_index = MOUSE_BUTTON_LEFT
	hud._input(emulated)
	_check(hud._touch_ui, "Synthetic mouse events do not replace touch instructions")
	var keyboard := InputEventKey.new()
	keyboard.pressed = true
	keyboard.keycode = KEY_E
	hud._input(keyboard)
	_check(hud._ability_button.text.ends_with("E") and hud._power_hint.text.contains("нажми E") and hud._hint.text.contains("игровое поле"), "A physical keyboard restores the shortcut while the lesson teaches screen activation")
	_check(hud._camera_hint.text.begins_with("Колесо мыши"), "Desktop mode explains the mouse wheel")
	hud.set_touch_ui(true)
	hud.set_loadout(CharacterCatalog.find_cat(&"zigzag"), CharacterCatalog.DOGS[0])
	_check(not hud._ability_button.visible and hud._ability_status.text == "Автоматически" and hud._power_hint.text.contains("после запуска"), "Passive cat identifies automatic flight and retains the detailed explanation")


func _test_layouts(hud: GameHUD) -> void:
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		for locale: String in GameLocalization.SUPPORTED_LOCALES:
			GameLocalization.apply_locale(locale)
			hud.set_loadout(CharacterCatalog.find_cat(&"homing"), CharacterCatalog.DOGS[0])
			hud.update_status("Урок", 3, 2, false)
			hud.set_tutorial_hint("")
			await _settle()
			var bounds := root.get_visible_rect()
			for control: Control in [hud._level_label, hud._stats, hud._camera_button, hud._help_button, hud._pause_button, hud._current_portrait, hud._current_name, hud._ability_status, hud._ability_button]:
				_check(bounds.encloses(control.get_global_rect()), "%s %s: compact control stays on screen" % [viewport_size, locale])
			var action := hud._ability_button.get_global_rect()
			_check(action.position.x > bounds.get_center().x and is_equal_approx(action.end.x, bounds.end.x - hud._margin.get_theme_constant("margin_right")), "%s %s: ability stays at the right screen edge" % [viewport_size, locale])
			_check(not action.intersects(hud._current_card.get_global_rect()) and not action.intersects(hud._hint.get_global_rect()), "%s %s: ability does not overlap the cat or lesson" % [viewport_size, locale])
			_check(not hud._hint.is_visible_in_tree() or hud._hint.text.is_empty(), "%s %s: campaign has no permanent generic instruction" % [viewport_size, locale])
			await _click(hud._help_button)
			await _settle()
			var card := hud._help_card.get_global_rect()
			_check(card.position.x >= 0.0 and card.end.x <= root.get_visible_rect().size.x and card.end.y < 400.0, "%s %s: help stays on screen above the slingshot" % [viewport_size, locale])
			_check(hud._help_description.get_global_rect().end.x <= card.end.x, "%s %s: translated effect fits inside the card" % [viewport_size, locale])
			_check(not hud._camera_button.get_global_rect().intersects(hud._help_button.get_global_rect()), "%s %s: help and camera buttons do not overlap" % [viewport_size, locale])
			_check(not hud._help_button.get_global_rect().intersects(hud._pause_button.get_global_rect()), "%s %s: help and pause buttons do not overlap" % [viewport_size, locale])
			hud.show_pause(true)
			await _settle()
			for control: Control in [hud._queue_label, hud._score_hint, hud._overlay_menu_button, hud._resume_button]:
				_check(control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()), "%s %s: pause details and navigation stay on screen" % [viewport_size, locale])
			hud.show_pause(false)


func _test_real_ability_states() -> void:
	root.size = Vector2i(1280, 720)
	for activate: bool in [true, false]:
		var game := GAME_SCENE.instantiate() as GameRound
		game.level = LevelDefinition.new()
		game.level.shots = 3
		game.level.dog_positions = PackedVector2Array([Vector2(1150, 585)])
		game.campaign_mode = true
		root.add_child(game)
		await _settle()
		game.set_paused(false)
		var hud := game.hud
		_check(hud._ability_state == GameHUD.AbilityState.BEFORE_LAUNCH and hud._ability_status.text == "Запусти кота" and hud._ability_button.disabled, "A loaded active cat asks for a launch")
		game.slingshot.launch_from_pull(Vector2(-85, 45) if activate else Vector2(-60, -20))
		var cat := game._active_cat
		_check(hud._ability_state == GameHUD.AbilityState.READY and hud._ability_status.text == "Готово" and not hud._ability_button.disabled, "A real launch makes the ability ready")
		if activate:
			await _tap(hud._ability_button)
			_check(cat.ability_spent and hud._ability_state == GameHUD.AbilityState.USED and hud._ability_status.text == "Использовано" and hud._ability_button.disabled, "Touch activation displays used and disables a second activation")
		else:
			for frame in 120:
				await physics_frame
				if cat.has_contacted():
					break
			_check(cat.has_contacted() and not cat.ability_spent, "The projectile reaches the real ground without using its ability")
			_check(hud._ability_state == GameHUD.AbilityState.CONTACTED and hud._ability_status.text == "После удара недоступно" and hud._ability_button.disabled, "Physical contact explains why the unspent ability is unavailable")
			await _click(hud._ability_button)
			_check(not cat.ability_spent, "Clicking the unavailable ability after contact cannot activate it")
		game.queue_free()
		await _settle()
	await create_timer(0.2).timeout


func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle()


func _tap(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle()


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
