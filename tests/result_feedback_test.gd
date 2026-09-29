extends SceneTree
## Праздник не задерживает действия, не меняет результат и останавливается вместе с игрой.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_locale := TranslationServer.get_locale()
	GameLocalization.apply_locale("ru")
	var hud := GameHUD.new()
	root.add_child(hud)
	hud.set_campaign(true, true, 2)
	hud.set_loadout(CharacterCatalog.CATS[0], CharacterCatalog.DOGS[0])
	hud.set_result_cast(PackedStringArray(["frost", "ghost", "homing", "bomb"]))
	hud.show_result(true, 2, 3)
	await _layout()
	var celebration := hud._result_celebration
	_check(celebration.is_visible_in_tree() and celebration.cast.size() == 3, "Victory shows a bounded team")
	_check(celebration.cast[0].id == &"frost" and celebration.cast[2].id == &"homing", "Celebration uses the authored squad")
	_check(hud._result_detail.text.begins_with("★★★\n"), "The earned score remains visible")
	_check(celebration.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Artwork never captures input")
	var next_events: Array[bool] = []
	var menu_events: Array[bool] = []
	hud.next_requested.connect(func() -> void: next_events.append(true))
	hud.menu_requested.connect(func() -> void: menu_events.append(true))
	await _click(hud._next_button, false)
	await _click(hud._overlay_menu_button, true)
	_check(next_events == [true] and menu_events == [true], "Mouse and touch can leave before the celebration ends")
	paused = true
	var before := celebration.elapsed
	await create_timer(0.08, true).timeout
	_check(is_equal_approx(before, celebration.elapsed), "Tree pause freezes the victory art")
	paused = false
	await create_timer(0.08).timeout
	_check(celebration.elapsed > before, "Unpausing resumes the scene")
	celebration.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	before = celebration.elapsed
	await create_timer(0.08).timeout
	_check(is_equal_approx(before, celebration.elapsed), "Losing focus freezes the scene")
	celebration.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.08).timeout
	_check(celebration.elapsed > before, "Returning focus resumes the scene")
	var children_before := celebration.get_child_count()
	await create_timer(ResultCelebration.DURATION).timeout
	_check(not celebration.is_processing() and celebration.is_visible_in_tree(), "The finite animation rests on its final picture")
	_check(celebration.get_child_count() == children_before, "Confetti does not accumulate scene objects")
	hud.show_result(false, 3, 0)
	_check(not celebration.visible and not celebration.is_processing() and not hud._next_button.visible, "A loss never celebrates or opens the next level")
	hud.show_pause(true)
	_check(not celebration.visible and hud._overlay_sound.is_visible_in_tree(), "Pause retains sound controls without celebration")
	hud.show_pause(false)
	await _test_layouts(hud)
	hud.set_result_cast(PackedStringArray())
	hud.set_loadout(CharacterCatalog.find_cat(&"magnet"), CharacterCatalog.DOGS[0])
	hud.set_campaign(false, false, 0)
	hud.show_result(true)
	_check(celebration.cast.size() == 1 and celebration.cast[0].id == &"magnet", "Sandbox celebrates its selected cat")
	_check(not hud._next_button.visible, "Sandbox gets no campaign progression")
	hud.queue_free()
	await _layout()
	GameLocalization.apply_locale(original_locale)
	print("Result feedback checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_layouts(hud: GameHUD) -> void:
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		for locale: String in GameLocalization.SUPPORTED_LOCALES:
			GameLocalization.apply_locale(locale)
			for has_next: bool in [true, false]:
				hud.set_campaign(true, has_next, 2)
				hud.show_result(true, 2, 3)
				hud.set_save_warning()
				await _layout()
				for control: Control in [hud._result_title, hud._result_detail, hud._result_celebration, hud._overlay_menu_button]:
					_check(root.get_visible_rect().encloses(control.get_global_rect()), "Result fits %s / %s" % [dimensions, locale])
				if has_next:
					_check(root.get_visible_rect().encloses(hud._next_button.get_global_rect()), "Next remains on screen")
				_check(not hud._result_celebration.get_global_rect().intersects(hud._result_detail.get_global_rect()), "Art and translated result do not overlap")


func _click(button: BaseButton, touch: bool) -> void:
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = button.get_global_rect().get_center()
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = button.get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event, true)
	await _layout()


func _layout() -> void:
	for frame in 4:
		await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
