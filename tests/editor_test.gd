extends SceneTree
## Проверки редактора с настоящей маршрутизацией событий мыши и касаний.

const APP_SCENE := preload("res://scenes/app.tscn")
const BUILTIN_LEVEL := preload("res://levels/level_01.tres")

var _checks: int = 0
var _failures: int = 0
var _saved_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := APP_SCENE.instantiate() as GameApp
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	await _settle()
	_click(app.campaign.editor_button, true)
	await _settle()
	var editor: LevelEditor = app.editor
	_check(is_instance_valid(editor) and editor.is_visible_in_tree(), "Editor opens from the app")
	_check(editor.draft != BUILTIN_LEVEL and editor.draft.dog_positions == BUILTIN_LEVEL.dog_positions, "Editor starts with an independent built-in level")
	await _test_replace_confirmation(editor)
	await _test_mouse_editing(editor)
	await _test_touch_editing(editor)
	await _test_save_load(editor)
	await _test_rules(editor)
	await _test_preview(app, editor)
	await _test_layout(app, editor)
	var music_playback_ref: WeakRef = weakref((app.get_node("BackgroundMusic") as AudioStreamPlayer).get_stream_playback())
	app.queue_free()
	await _settle()
	# Микшер освобождает поток отдельно от быстрых headless-кадров дерева.
	var audio_deadline := Time.get_ticks_msec() + 1000
	while music_playback_ref.get_ref() != null and Time.get_ticks_msec() < audio_deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(music_playback_ref.get_ref() == null, "Closing the editor releases the application audio playback")
	for path in _saved_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Editor checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_replace_confirmation(editor: LevelEditor) -> void:
	editor.new_level()
	await _settle()
	await _choose_tool(editor, LevelCanvas.Tool.DOG)
	_canvas_click(editor.canvas, Vector2(800, 560))
	var original: LevelDefinition = editor.draft
	var new_button: Button
	for node in editor.find_children("*", "Button", true, false):
		if (node as Button).text == "Новый":
			new_button = node as Button
			break
	_check(new_button != null, "New level action is available in the editor")
	if new_button == null:
		return
	_click(new_button)
	await _settle()
	_check(editor._confirm.visible and editor.draft == original, "Replacing an unsaved draft asks for confirmation")
	editor._confirm.get_cancel_button().pressed.emit()
	await _settle()
	_check(not editor._confirm.visible and editor.draft == original and editor.draft.dog_positions.size() == 1, "Cancel keeps the unsaved draft")
	_click(new_button)
	await _settle()
	editor._confirm.get_ok_button().pressed.emit()
	await _settle()
	_check(not editor._confirm.visible and editor.draft != original and editor.draft.dog_positions.is_empty(), "Confirm replaces the draft with a new level")


func _test_mouse_editing(editor: LevelEditor) -> void:
	editor.new_level()
	await _settle()
	_check(editor.draft.title == "Новый двор" and editor.draft.shots == 4 and editor.draft.dog_positions.is_empty() and editor.draft.block_positions.is_empty(), "New level starts with clear data")
	_check(editor.play_button.disabled, "An empty level cannot start a preview")
	await _choose_tool(editor, LevelCanvas.Tool.DOG)
	_canvas_click(editor.canvas, Vector2(803, 563))
	_check(editor.draft.dog_positions.size() == 1 and editor.draft.dog_positions[0] == Vector2(800, 560), "Mouse places a dog on the grid")
	_check(editor.canvas.tool == LevelCanvas.Tool.SELECT, "Placement returns to selection")
	_check(not editor.play_button.disabled and not editor.undo_button.disabled, "A valid edit enables play and undo")
	var start := _canvas_point(editor.canvas, Vector2(800, 560))
	_mouse_button(start, true)
	_mouse_motion(_canvas_point(editor.canvas, Vector2(860, 510)))
	_mouse_motion(_canvas_point(editor.canvas, Vector2(903, 483)))
	_mouse_button(_canvas_point(editor.canvas, Vector2(903, 483)), false)
	_check(editor.draft.dog_positions[0] == Vector2(900, 480), "Mouse drags the selected dog")
	_click(editor.undo_button)
	_check(editor.draft.dog_positions[0] == Vector2(800, 560), "One undo restores the whole drag")
	_click(editor.redo_button)
	_check(editor.draft.dog_positions[0] == Vector2(900, 480), "Redo restores the completed drag")
	await _choose_tool(editor, LevelCanvas.Tool.POST)
	_canvas_click(editor.canvas, Vector2(1050, 520))
	_check(editor.draft.block_positions.size() == 1 and editor.draft.block_sizes[0] == Vector2(40, 140), "Post tool adds a matching position and size")
	_click(editor._rotate_button)
	_check(editor.draft.block_sizes[0] == Vector2(140, 40), "Rotation swaps block dimensions")
	editor.undo()
	_check(editor.draft.block_sizes[0] == Vector2(40, 140), "Undo restores the original block orientation")
	editor.redo()
	_canvas_click(editor.canvas, editor.draft.block_positions[0])
	editor._fields[2].value = 200
	_check(editor.draft.block_sizes[0] == Vector2(200, 40), "Width control resizes the selected block")
	editor.undo()
	_check(editor.draft.block_sizes[0] == Vector2(140, 40), "Undo restores a width edit")
	_canvas_click(editor.canvas, editor.draft.block_positions[0])
	editor._fields[3].value = 60
	_check(editor.draft.block_sizes[0] == Vector2(140, 60), "Height control resizes the selected block")
	editor.undo()
	_check(editor.draft.block_sizes[0] == Vector2(140, 40), "Undo restores a height edit")
	var beam_start := editor.draft.block_positions[0]
	_mouse_button(_canvas_point(editor.canvas, beam_start), true)
	_mouse_button(_canvas_point(editor.canvas, Vector2(beam_start.x, 615)), false)
	_click(editor._rotate_button)
	_check(editor.draft.block_sizes[0] == Vector2(40, 140) and editor.draft.block_positions[0].y + editor.draft.block_sizes[0].y * 0.5 <= 620, "Rotating at the ground keeps the entire block above the surface")
	editor.undo()
	_check(editor.draft.block_sizes[0] == Vector2(140, 40) and editor.draft.block_positions[0].y == 600, "Undo restores both position and dimensions after a boundary rotation")
	_canvas_click(editor.canvas, editor.draft.block_positions[0])
	_click(editor._delete_button)
	_check(editor.draft.block_positions.is_empty() and editor.draft.block_sizes.is_empty(), "Delete removes both block arrays together")
	editor.undo()
	_check(editor.draft.block_positions.size() == 1 and editor.draft.block_sizes[0] == Vector2(140, 40), "Undo restores a deleted block")
	await _choose_tool(editor, LevelCanvas.Tool.BOX)
	_canvas_click(editor.canvas, Vector2(650, 550))
	_check(editor.redo_button.disabled, "A new edit clears the abandoned redo branch")
	_check(BUILTIN_LEVEL.dog_positions.size() > 1 and BUILTIN_LEVEL.dog_positions[0] != editor.draft.dog_positions[0], "Editing keeps the built-in resource unchanged")


func _test_touch_editing(editor: LevelEditor) -> void:
	editor.new_level()
	await _settle()
	await _choose_tool(editor, LevelCanvas.Tool.DOG, true)
	_canvas_click(editor.canvas, Vector2(700, 500), true)
	_check(editor.draft.dog_positions.size() == 1, "Touch placement creates exactly one dog")
	var original := editor.draft.dog_positions[0]
	_touch(_canvas_point(editor.canvas, original), true, 2)
	_touch(_canvas_point(editor.canvas, Vector2(1100, 300)), true, 3)
	_touch_motion(_canvas_point(editor.canvas, Vector2(1150, 350)), 3)
	_touch(_canvas_point(editor.canvas, Vector2(1150, 350)), false, 3)
	_check(editor.draft.dog_positions[0] == original, "A second finger cannot move or finish the active drag")
	_touch_motion(_canvas_point(editor.canvas, Vector2(780, 440)), 2)
	_touch(_canvas_point(editor.canvas, Vector2(800, 420)), false, 2)
	_check(editor.draft.dog_positions[0] == Vector2(800, 420), "The owning finger can finish its drag")
	editor.undo()
	_check(editor.draft.dog_positions[0] == original, "Touch drag creates a single history entry")
	_touch(_canvas_point(editor.canvas, original), true, 4)
	_touch_motion(_canvas_point(editor.canvas, Vector2(900, 350)), 4)
	_touch(_canvas_point(editor.canvas, Vector2(900, 350)), false, 4, true)
	_check(editor.draft.dog_positions[0] == original, "Canceled touch restores the object origin")
	_check(not editor.redo_button.disabled, "Canceled drag keeps the existing redo history")
	_mouse_button(_canvas_point(editor.canvas, original), true)
	_mouse_motion(_canvas_point(editor.canvas, Vector2(950, 400)))
	editor.canvas.cancel_drag()
	_mouse_button(_canvas_point(editor.canvas, Vector2(950, 400)), false)
	_check(editor.draft.dog_positions[0] == original, "Canceled mouse drag restores the object origin")
	_mouse_button(_canvas_point(editor.canvas, original), true)
	_mouse_motion(_canvas_point(editor.canvas, Vector2(950, 400)))
	_mouse_motion(_canvas_point(editor.canvas, original + Vector2.ONE))
	_mouse_button(_canvas_point(editor.canvas, original + Vector2.ONE), false)
	_check(editor.draft.dog_positions[0] == original and not editor.redo_button.disabled, "Dragging away and back restores the exact origin without a history entry")
	await _choose_tool(editor, LevelCanvas.Tool.DOG, true)
	var fake_mouse := InputEventMouseButton.new()
	fake_mouse.button_index = MOUSE_BUTTON_LEFT
	fake_mouse.position = _canvas_point(editor.canvas, Vector2(1100, 550))
	fake_mouse.device = -1
	fake_mouse.pressed = true
	root.push_input(fake_mouse, true)
	fake_mouse = fake_mouse.duplicate() as InputEventMouseButton
	fake_mouse.pressed = false
	root.push_input(fake_mouse, true)
	_check(editor.draft.dog_positions.size() == 1, "Synthetic mouse events do not duplicate touch edits")
	_click_control(editor.title_edit, true)
	_click_control(editor.shots_input, true)
	_check(editor.draft.dog_positions.size() == 1, "Editor controls do not place objects on the canvas")
	editor.canvas.set_tool(LevelCanvas.Tool.SELECT)
	_mouse_button(_canvas_point(editor.canvas, original), true)
	_mouse_motion(_canvas_point(editor.canvas, Vector2(1500, 900)))
	_mouse_button(_canvas_point(editor.canvas, Vector2(1500, 900)), false)
	_check(editor.draft.dog_positions[0] == Vector2(1215, 595), "Release outside the canvas clamps the dog to the build area")
	editor.undo()
	editor.canvas.grid_enabled = false
	_mouse_button(_canvas_point(editor.canvas, original), true)
	_mouse_button(_canvas_point(editor.canvas, Vector2(737, 467)), false)
	_check(editor.draft.dog_positions[0].is_equal_approx(Vector2(737, 467)), "Disabling the grid permits precise movement")
	editor.canvas.grid_enabled = true


func _test_save_load(editor: LevelEditor) -> void:
	var test_path := "user://levels/test_editor_%s.tres" % Time.get_ticks_usec()
	_saved_paths.append(test_path)
	editor.current_path = test_path
	editor.title_edit.text = "Проверка редактора"
	editor.title_edit.text_changed.emit(editor.title_edit.text)
	editor.shots_input.value = 7
	var saved_dog := editor.draft.dog_positions[0]
	_click(editor.save_button, true)
	_check(FileAccess.file_exists(test_path), "Save button writes a level resource")
	var stored := LevelLibrary.load_level(test_path)
	_check(stored != null and stored.title == "Проверка редактора" and stored.shots == 7, "Saved resource contains the edited title and shot count")
	_canvas_click(editor.canvas, saved_dog)
	editor.canvas.delete_selected()
	_check(stored != null and stored.dog_positions.size() == 1, "Editing a draft does not mutate a previously loaded resource")
	editor.open_level(test_path)
	await _settle()
	_check(editor.draft.dog_positions.size() == 1 and editor.draft.dog_positions[0] == saved_dog and editor.draft.shots == 7, "Opening a saved level restores its data")
	_check(editor.draft != stored, "Opening creates an independent editable resource")
	await _choose_tool(editor, LevelCanvas.Tool.BEAM)
	_canvas_click(editor.canvas, Vector2(1050, 500))
	_check(editor.draft.block_sizes.size() == 1 and editor.draft.block_sizes[0] == Vector2(180, 20), "A loaded level remains editable")
	editor.save_level(true)
	var copy_path := editor.current_path
	if copy_path != test_path and not copy_path.is_empty():
		_saved_paths.append(copy_path)
	_check(copy_path != test_path and FileAccess.file_exists(copy_path), "Save as copy creates another resource")
	var original := LevelLibrary.load_level(test_path)
	_check(original != null and original.block_positions.is_empty(), "Saving a copy preserves the original file")
	editor.open_level(test_path)
	await _settle()


func _test_rules(editor: LevelEditor) -> void:
	_check(editor.draft.cat_sequence.is_empty() and editor.draft.dog_kinds.is_empty(), "Ordinary editing preserves legacy sandbox hero selection")
	editor._show_rules()
	await _settle()
	_check(editor._rules_dialog.visible, "Rules open separately from the construction field")
	editor.biome_picker.item_selected.emit(2)
	_check(editor.draft.biome == "glacier" and editor.canvas._backdrop.biome == &"glacier", "Choosing scenery updates both the draft and canvas")
	editor.undo()
	_check(editor.draft.biome == "backyard" and editor.canvas._backdrop.biome == &"backyard", "Undo restores the previous scenery")
	editor.redo()
	editor.par_input.value = 3
	_check(editor.draft.par_shots == 3 and editor.draft.stars_for_shots(3) == 3 and editor.draft.stars_for_shots(4) == 2, "The star rule uses the selected shot threshold")
	editor.cat_roster_toggle.button_pressed = true
	editor.cat_pickers[0].item_selected.emit(1)
	editor.cat_pickers[1].item_selected.emit(7)
	_check(editor.draft.cat_sequence[0] == "bomb" and editor.draft.cat_sequence[1] == "frost", "Each numbered throw selects its own cat")
	editor.shots_input.value = 9
	_check(editor.draft.cat_sequence.size() == 9 and editor.draft.cat_sequence[0] == "bomb" and editor.draft.cat_sequence[1] == "frost" and editor.draft.cat_sequence[8] == "classic", "Extra shots extend the chosen roster with the default cat")
	editor.shots_input.value = 1
	_check(editor.draft.cat_sequence == PackedStringArray(["bomb"]) and editor.draft.par_shots == 1, "Reducing shots keeps the remaining order and a valid star threshold")
	editor.undo()
	_check(editor.draft.cat_sequence.size() == 9 and editor.draft.cat_sequence[1] == "frost" and editor.draft.par_shots == 3 and editor.par_input.value == 3, "Undo restores removed cats and the visible star threshold")
	editor.shots_input.value = 7
	editor._rules_dialog.hide()
	editor.canvas.selected_kind = 0
	editor.canvas.selected_index = 0
	editor._update_selection()
	editor.dog_kind_picker.item_selected.emit(3)
	_check(editor.draft.dog_kinds == PackedStringArray(["jumper"]), "The selected dog's kind can be assigned directly")
	_check(editor.dog_kind_picker.is_item_disabled(0) and editor.dog_kind_picker.selected == 3, "Sandbox is a disabled placeholder and the selected dog kind matches the draft")
	editor.canvas.set_tool(LevelCanvas.Tool.DOG)
	editor.canvas._add_object(Vector2(950, 540))
	_check(editor.draft.dog_kinds == PackedStringArray(["jumper", "scout"]), "Adding a dog preserves existing assignments and appends the default dog")
	editor.dog_kind_picker.item_selected.emit(2)
	editor.canvas.selected_index = 0
	editor.canvas.delete_selected()
	_check(editor.draft.dog_kinds == PackedStringArray(["armored"]), "Deleting a dog removes its own kind instead of shifting unrelated assignments")
	editor.undo()
	_check(editor.draft.dog_kinds == PackedStringArray(["jumper", "armored"]), "Undo restores the deleted dog's assignment")
	editor.undo()
	editor.undo()
	_check(editor.draft.dog_kinds == PackedStringArray(["jumper"]) and editor.draft.is_valid(), "Undo returns to a valid original target roster")
	editor.save_level()
	var saved_path := editor.current_path
	editor.open_level(saved_path)
	_check(editor.draft.biome == "glacier" and editor.draft.par_shots == 3 and editor.draft.cat_sequence[0] == "bomb" and editor.draft.dog_kinds[0] == "jumper", "Explicit saving and opening preserve the complete rules")
	editor.cat_roster_toggle.button_pressed = false
	editor.dog_roster_toggle.button_pressed = false
	_check(editor.draft.cat_sequence.is_empty() and editor.draft.dog_kinds.is_empty(), "Both rosters can explicitly return to sandbox hero selection")
	editor.undo()
	editor.undo()
	await _settle()


func _test_preview(app: GameApp, editor: LevelEditor) -> void:
	var draft: LevelDefinition = editor.draft
	var dog_positions := draft.dog_positions.duplicate()
	_click(editor.play_button, true)
	await _settle()
	_check(is_instance_valid(app.game) and not editor.is_visible_in_tree(), "Play enters a round and hides the editor")
	_check(app.game.level != draft and app.game.level.dog_positions == dog_positions and app.game.shots_left == 7, "Preview uses an independent copy of the draft")
	_check(app.game.level.biome == "glacier" and app.game.level.par_shots == 3 and app.game.slingshot.loaded_projectile.definition.id == &"bomb", "Preview applies the scenery, star rule and first assigned cat")
	app.game.slingshot.launch_from_pull(Vector2(80, 20))
	_check(app.game.shots_left == 6, "The preview uses the edited shot limit")
	app.game.restart()
	await _settle()
	_check(app.game.shots_left == 7 and app.game.level.dog_positions == dog_positions, "Restart keeps the custom level and restores its shots")
	app.game.set_paused(true)
	app.game.return_to_menu()
	await _settle()
	_check(not paused and app.editor == editor and editor.is_visible_in_tree() and app.game == null, "Returning from a paused preview restores the same editor")
	_check(editor.draft == draft and editor.draft.dog_positions == dog_positions, "Preview physics does not change the editable draft")
	editor._request_menu()
	await _settle()
	_check(is_instance_valid(app.campaign) and app.menu == null and not editor.is_visible_in_tree(), "Leaving the editor opens the campaign")
	app.show_editor()
	await _settle()
	_check(app.editor == editor and editor.draft == draft, "Menu transitions keep the current draft")
	app.show_menu()
	await _settle()
	app.start_game(&"classic", &"scout")
	await _settle()
	_check(app.game.level.shots == BUILTIN_LEVEL.shots and app.game.level.dog_positions == BUILTIN_LEVEL.dog_positions, "Normal play still uses the built-in level")
	app.game.return_to_menu()
	await _settle()
	_check(is_instance_valid(app.menu) and app.campaign == null and not editor.is_visible_in_tree(), "Returning from sandbox play opens its hero roster")
	app.show_editor()
	await _settle()


func _test_layout(_app: GameApp, editor: LevelEditor) -> void:
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		await _settle()
		var viewport_rect := root.get_visible_rect()
		var buttons: Array[Button] = [editor.save_button, editor.play_button, editor.undo_button, editor.redo_button, editor._rotate_button, editor._delete_button]
		var visible := true
		for button in buttons:
			visible = visible and viewport_rect.encloses(button.get_global_rect())
		for field in editor._fields:
			visible = visible and viewport_rect.encloses(field.get_global_rect())
		var palette := editor.tool_buttons[0].get_parent().get_parent() as ScrollContainer
		for button in editor.tool_buttons:
			palette.ensure_control_visible(button)
			await _settle()
			visible = visible and palette.get_global_rect().encloses(button.get_global_rect())
		palette.scroll_vertical = 0
		_check(visible and editor.canvas.size.x > 300 and editor.canvas.size.y > 200, "Editor controls and canvas fit %dx%d" % [viewport_size.x, viewport_size.y])
		var probe := Vector2(970, 500)
		_check(editor.canvas.local_to_world(editor.canvas.world_to_local(probe)).is_equal_approx(probe), "Canvas mapping survives %dx%d" % [viewport_size.x, viewport_size.y])
		editor._show_rules()
		await _settle()
		_check(editor._rules_dialog.size.x <= viewport_size.x and editor._rules_dialog.size.y <= viewport_size.y, "Rules dialog fits %dx%d" % [viewport_size.x, viewport_size.y])
		editor._rules_dialog.hide()
	root.size = Vector2i(1280, 720)


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
	await process_frame


func _canvas_point(canvas: LevelCanvas, point: Vector2) -> Vector2:
	return canvas.global_position + canvas.world_to_local(point)


func _canvas_click(canvas: LevelCanvas, point: Vector2, touch: bool = false) -> void:
	var position := _canvas_point(canvas, point)
	if touch:
		_touch(position, true)
		_touch(position, false)
	else:
		_mouse_button(position, true)
		_mouse_button(position, false)


func _choose_tool(editor: LevelEditor, tool: LevelCanvas.Tool, touch: bool = false) -> void:
	var button := editor.tool_buttons[tool]
	var scroll := button.get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(button)
	await _settle()
	_click(button, touch)


func _click(button: Button, touch: bool = false) -> void:
	_click_control(button, touch)


func _click_control(control: Control, touch: bool = false) -> void:
	var center := control.get_global_rect().get_center()
	if touch:
		_touch(center, true)
		_touch(center, false)
	else:
		_mouse_button(center, true)
		_mouse_button(center, false)


func _mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _touch(position: Vector2, pressed: bool, pointer: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.index = pointer
	event.canceled = canceled
	root.push_input(event, true)


func _touch_motion(position: Vector2, pointer: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = pointer
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
