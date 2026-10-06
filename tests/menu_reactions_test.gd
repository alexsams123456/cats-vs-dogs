extends SceneTree
## Касания живого двора: видимые герои, отмена, окна, страницы и пауза.

const DIMENSIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]
var _checks: int = 0
var _failures: int = 0
var _reactions: Array[StringName] = []
var _menu: CampaignMenu
var _backdrop: MenuBackdrop


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_menu = CampaignMenu.new()
	_menu.profile = PlayerProfile.new("")
	root.add_child(_menu)
	_backdrop = _menu._backdrop
	_backdrop.hero_reacted.connect(func(species: StringName) -> void: _reactions.append(species))
	await _settle()
	for dimensions in DIMENSIONS:
		root.size = dimensions
		await _settle()
		await _test_size(dimensions)
		# Завершить отложенное закрытие подсказок до следующего resize окна.
		await _settle()
	await _test_gestures()
	await _test_navigation()
	await _test_lifetime()
	_menu.queue_free()
	await process_frame
	print("Menu reaction checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_size(dimensions: Vector2i) -> void:
	_backdrop.reset_interactions()
	_reactions.clear()
	var cat := _hero_point(true)
	var dog := _hero_point(false)
	_check(root.get_visible_rect().has_point(cat) and root.get_visible_rect().has_point(dog), "Both heroes remain visible at %s" % dimensions)
	_check(not _menu._home_panel.get_global_rect().has_point(cat) and not _menu._home_panel.get_global_rect().has_point(dog), "Hero centers stay outside the menu panel at %s" % dimensions)
	_click(cat)
	_check(_reactions == [&"cat"], "Mouse tap reacts on the visible cat at %s" % dimensions)
	_touch(dog, true, 4)
	_touch(dog, false, 4)
	_check(_reactions == [&"cat", &"dog"], "Direct touch reacts on the visible dog at %s" % dimensions)
	if "--capture-menu-reactions" in OS.get_cmdline_user_args():
		await create_timer(0.32).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.artifacts")
		var path := "res://.artifacts/menu-reactions-%dx%d.png" % [dimensions.x, dimensions.y]
		_check(root.get_texture().get_image().save_png(path) == OK, "Reaction screenshot saved")
	_backdrop.reset_interactions()
	_reactions.clear()
	# На узком экране часть собаки заходит под карточку: карточка получает ввод.
	var covered_point := _menu._home_panel.get_global_rect().position + Vector2(8, 400)
	_click(covered_point)
	_check(_reactions.is_empty(), "Menu panel never activates a covered hero at %s" % dimensions)
	_click(Vector2(24, 660))
	_check(_reactions.is_empty(), "Empty garden does not react at %s" % dimensions)


func _test_gestures() -> void:
	_backdrop.reset_interactions()
	_reactions.clear()
	var cat := _hero_point(true)
	var dog := _hero_point(false)
	_mouse(cat, false)
	_touch(cat, false, 12)
	_check(_reactions.is_empty(), "A release without a captured press cannot react")
	_mouse(cat, true, InputEvent.DEVICE_ID_EMULATION)
	_mouse(cat, false, InputEvent.DEVICE_ID_EMULATION)
	_check(_reactions.is_empty(), "Synthetic mouse from touch is ignored")
	_touch(cat, true, 2)
	_touch(dog, true, 3)
	_touch(dog, false, 3)
	_check(_reactions.is_empty(), "Second finger cannot choose another hero")
	_click(dog)
	_check(_reactions.is_empty(), "Mouse cannot duplicate an active touch")
	_touch(cat, false, 2)
	_check(_reactions == [&"cat"], "First finger retains its original hero")
	_backdrop.reset_interactions()
	_reactions.clear()
	_touch(Vector2(20, 660), true, 0)
	_touch(dog, true, 1)
	_touch(dog, false, 1)
	_touch(Vector2(20, 660), false, 0)
	_check(_reactions.is_empty(), "A first touch outside heroes prevents a second finger reaction")
	_touch(cat, true, 1)
	_touch(cat, false, 1, true)
	_check(_reactions.is_empty(), "Canceled touch does not start a reaction")
	_touch(cat, true, 8)
	var drag := InputEventScreenDrag.new()
	drag.index = 8
	drag.position = cat + Vector2(90, 0)
	root.push_input(drag, true)
	_touch(cat, false, 8)
	_check(_reactions.is_empty(), "Dragging away and returning does not turn into a tap")
	_mouse(cat, true)
	var motion := InputEventMouseMotion.new()
	motion.position = cat + Vector2(0, 90)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse(cat, false)
	_check(_reactions.is_empty(), "Mouse dragging cancels its tap")
	_touch(cat, true, 1)
	_backdrop.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_touch(cat, false, 1)
	_check(_reactions.is_empty(), "Focus loss cancels the pending touch")
	_touch(cat, true, 1)
	_backdrop._on_resized()
	_touch(cat, false, 1)
	_check(_reactions.is_empty(), "Resize cancels the pending touch")
	_touch(cat, true, 1)
	_menu.hide()
	_menu.show()
	_touch(cat, false, 1)
	_check(_reactions.is_empty(), "Hiding the menu cancels the pending touch")
	_click(_hero_point(true))
	_check(_reactions == [&"cat"], "New input works after cancellation and focus recovery")


func _test_navigation() -> void:
	_backdrop.reset_interactions()
	_reactions.clear()
	var cat := _hero_point(true)
	_touch(cat, true, 0)
	_menu.show_page(&"campaign")
	_menu.show_page(&"home")
	_touch(cat, false, 0)
	_check(_reactions.is_empty(), "Changing pages cancels pending input")
	_click(_menu.campaign_button.get_global_rect().get_center())
	_check(_menu.page == &"campaign", "Mouse still opens the campaign")
	_click(cat)
	_check(_reactions.is_empty(), "Campaign page cannot activate hidden animals")
	_menu.show_page(&"home")
	_touch(_menu.rating_button.get_global_rect().get_center(), true, 0)
	_touch(_menu.rating_button.get_global_rect().get_center(), false, 0)
	_check(_menu.page == &"rating", "Touch still opens the rating")
	_click(cat)
	_check(_reactions.is_empty(), "Rating page cannot activate hidden animals")
	_menu.show_page(&"home")
	await _settle()
	var controls := _menu.find_children("*", "SoundControls", true, false)[0] as SoundControls
	_touch(cat, true, 0)
	controls.open_settings()
	_check(_backdrop._pressed_hero == -1, "Opening sound settings clears a pending gesture immediately")
	_click(cat)
	_touch(cat, false, 0)
	_check(_reactions.is_empty(), "Sound dialog prevents animal input")
	controls.dialog.hide()
	_menu.language_picker.show_popup()
	_click(cat)
	_check(_reactions.is_empty(), "Language popup prevents animal input")
	_menu.language_picker.get_popup().hide()
	_click(_hero_point(true))
	_check(_reactions == [&"cat"], "Input recovers after closing dialogs")


func _test_lifetime() -> void:
	_backdrop.reset_interactions()
	_reactions.clear()
	var children_before := _backdrop.get_child_count()
	_click(_hero_point(true))
	await create_timer(0.24).timeout
	var cat := _hero_point(true)
	_check(_backdrop.hero_at_position(cat) == 0, "Hit testing follows the moving cat")
	for index in 20:
		_click(cat)
	_check(_reactions.size() == 1, "Rapid taps do not restart or stack a reaction")
	_touch(_hero_point(false), true, 0)
	paused = true
	var paused_pose := _backdrop.get_hero_transform(true)
	var paused_time := _backdrop.visual_time
	await create_timer(0.15).timeout
	_check(_backdrop.get_hero_transform(true) == paused_pose and _backdrop.visual_time == paused_time, "Reaction and decoration freeze on pause")
	paused = false
	_touch(_hero_point(false), false, 0)
	_check(_reactions.size() == 1, "Pause cancels an unfinished touch")
	await create_timer(MenuBackdrop.REACTION_DURATION).timeout
	_check(_backdrop._reaction_times[0] < 0.0, "Reaction ends and returns to idle")
	var first_variant: int = _backdrop._reaction_variants[0]
	_click(_hero_point(true))
	_check(_reactions.size() == 2 and _backdrop._reaction_variants[0] != first_variant, "Repeated visits alternate short cat animations")
	_check(_backdrop.get_child_count() == children_before, "Repeated reactions do not accumulate nodes")
	_menu.show_page(&"campaign")
	_check(_backdrop._reaction_times == [-1.0, -1.0], "Leaving home clears reactions and particles")


func _hero_point(cat: bool) -> Vector2:
	return _backdrop.get_global_transform_with_canvas() * _backdrop.get_hero_transform(cat).origin


func _click(point: Vector2) -> void:
	_mouse(point, true)
	_mouse(point, false)


func _mouse(point: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.device = device
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)


func _touch(point: Vector2, pressed: bool, index: int, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	event.index = index
	event.canceled = canceled
	root.push_input(event, true)


func _settle() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.06).timeout


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
