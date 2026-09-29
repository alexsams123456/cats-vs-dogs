extends SceneTree
## Правила редактора, мышь/касания и прокрутка в трёх размерах; профиль не изменяется.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	app.show_editor()
	await _settle()
	var editor := app.editor
	editor.new_level()
	var save_path := "user://levels/test_editor_rules_%d.tres" % Time.get_ticks_usec()
	editor.current_path = save_path
	await _settle()
	var palette := editor.rules_button.get_parent().get_parent() as ScrollContainer
	palette.ensure_control_visible(editor.tool_buttons[LevelCanvas.Tool.DOG])
	await _settle()
	await _click(editor.tool_buttons[LevelCanvas.Tool.DOG], true)
	var point := editor.canvas.global_position + editor.canvas.world_to_local(Vector2(900, 560))
	_pointer(root, point, true, true)
	_pointer(root, point, false, true)
	_check(editor.draft.dog_positions.size() == 1, "Touch places a target")
	palette.ensure_control_visible(editor.dog_kind_picker)
	await _settle()
	await _choose(editor.dog_kind_picker, 2, true)
	_check(editor.draft.dog_kinds == PackedStringArray(["armored"]), "Touch and keyboard select the target kind")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		await _settle()
		editor.biome_picker.item_selected.emit(0)
		palette.ensure_control_visible(editor.rules_button)
		await _settle()
		await _click(editor.rules_button, viewport_size.x == 960)
		await _settle()
		_check(editor._rules_dialog.visible, "Rules open with mouse/touch")
		await _choose(editor.biome_picker, 1, viewport_size.x == 960)
		editor.par_input.value = 2
		if editor.draft.cat_sequence.is_empty():
			await _click(editor.cat_roster_toggle, viewport_size.x == 960)
			await _settle()
		await _choose(editor.cat_pickers[0], 7, viewport_size.x == 960)
		_check(editor.draft.biome == "mountain" and editor.draft.cat_sequence[0] == "frost", "Scenery and numbered cat order follow picker input")
		await _save("editor-rules-%d" % viewport_size.x)
		if _failures > 0:
			app.queue_free()
			await process_frame
			await create_timer(0.25).timeout
			if FileAccess.file_exists(save_path):
				DirAccess.remove_absolute(save_path)
			quit(1)
			return
		editor._rules_dialog.hide()
		palette.ensure_control_visible(editor.dog_kind_picker)
		await _save("editor-target-%d" % viewport_size.x)
		editor.save_level()
		editor.open_level(save_path)
		editor.request_play()
		await _settle()
		_check(app.game.level.cat_sequence[0] == "frost" and app.game.level.dog_kinds[0] == "armored" and app.game.level.par_shots == 2 and app.game.level.biome == "mountain", "Saved rules carry into the preview")
		_check(app.game.slingshot.loaded_projectile.definition.id == &"frost", "Preview loads the assigned first cat")
		await _save("editor-rules-play-%d" % viewport_size.x)
		app.game.return_to_menu()
		await _settle()
		_check(app.editor == editor and editor.is_visible_in_tree(), "Preview returns to the same editor")
		editor.canvas.selected_kind = 0
		editor.canvas.selected_index = 0
		editor._update_selection()
	editor.shots_input.value = 20
	for locale: String in GameLocalization.SUPPORTED_LOCALES:
		GameLocalization.apply_locale(locale)
		editor._show_rules()
		await _settle()
		var rules_scroll := editor._rules_dialog.get_child(0) as ScrollContainer
		# AcceptDialog adds an internal button row; the custom content is found by type.
		for child in editor._rules_dialog.get_children():
			if child is ScrollContainer:
				rules_scroll = child
		_check(rules_scroll != null, "Rules expose a scrollable content area")
		if rules_scroll != null:
			rules_scroll.scroll_vertical = 0
			await _settle()
			_check(editor._rules_dialog.size.x < root.size.x and editor._rules_dialog.size.y < root.size.y, "Translated rules fit " + locale)
			await _save("editor-rules-locale-" + locale)
			rules_scroll.ensure_control_visible(editor.cat_pickers[19])
			await _settle()
			_check(rules_scroll.get_global_rect().encloses(editor.cat_pickers[19].get_global_rect()), "The twentieth throw remains accessible in " + locale)
			if locale == "ru":
				await _choose(editor.cat_pickers[19], 9, true)
				_check(editor.draft.cat_sequence[19] == "homing", "Scrolled final throw accepts input")
				await _save("editor-rules-last-throw")
		editor._rules_dialog.hide()
	GameLocalization.apply_locale("ru")
	app.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("Editor rules capture: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _choose(picker: OptionButton, index: int, touch: bool) -> void:
	await _click(picker, touch)
	await _settle()
	var popup := picker.get_popup()
	var context := "%s at %dx%d" % [picker.text, root.size.x, root.size.y]
	_check(popup.visible, "Picker opens through input: " + context)
	if not popup.visible:
		return
	if popup.item_count == 3 and index == 1:
		# У биомов три одинаковые строки; центр списка — вторая строка.
		# Здесь выбор завершается именно мышью/касанием, без клавиатуры.
		var point := Vector2(popup.position) + Vector2(popup.size) * 0.5
		_pointer(root, point, true, touch)
		_pointer(root, point, false, touch)
	else:
		for step in popup.item_count + 1:
			if popup.get_focused_item() == index:
				break
			_key(KEY_DOWN)
		_check(popup.get_focused_item() == index, "Keyboard focuses the requested option: " + context)
		_key(KEY_ENTER)
	await _settle()
	_check(not popup.visible and picker.selected == index, "Selection confirms and closes the picker: " + context)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)


func _click(control: Control, touch: bool) -> void:
	var center := control.get_global_rect().get_center()
	if control.get_window() != root:
		center += Vector2(control.get_window().position)
	if not touch:
		var motion := InputEventMouseMotion.new()
		motion.window_id = root.get_window_id()
		motion.position = root.get_final_transform() * center
		motion.global_position = motion.position
		Input.parse_input_event(motion)
		Input.flush_buffered_events()
		await process_frame
		await process_frame
	_pointer(root, center, true, touch)
	_pointer(root, center, false, touch)


func _pointer(viewport: Viewport, point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.window_id = root.get_window_id()
		event.position = root.get_final_transform() * point
		event.index = 0
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	else:
		var event := InputEventMouseButton.new()
		event.window_id = root.get_window_id()
		event.position = root.get_final_transform() * point
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _settle() -> void:
	await create_timer(0.35).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _save(label: String) -> void:
	await _settle()
	if DisplayServer.get_name() == "headless":
		return
	var error := root.get_texture().get_image().save_png("res://.artifacts/%s.png" % label)
	_check(error == OK, "Screenshot saved: " + label)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
