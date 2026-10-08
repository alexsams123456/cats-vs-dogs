extends SceneTree
## Снимки редактора и пробного боя с воспроизведением мыши и касаний.


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	await create_timer(0.3).timeout
	_click(app.campaign.editor_button, true)
	await create_timer(0.3).timeout
	var editor: LevelEditor = app.editor
	editor.new_level()
	editor.title_edit.text = "Башня дружных собак у старого забора возле садика!"
	editor.title_edit.text_changed.emit(editor.title_edit.text)
	editor.shots_input.value = 5
	await process_frame
	await _place(editor, LevelCanvas.Tool.POST, Vector2(860, 550))
	await _place(editor, LevelCanvas.Tool.POST, Vector2(1020, 550), true)
	await _place(editor, LevelCanvas.Tool.BEAM, Vector2(940, 470))
	await _place(editor, LevelCanvas.Tool.DOG, Vector2(940, 435), true)
	await _place(editor, LevelCanvas.Tool.DOG, Vector2(1120, 590))
	await _place(editor, LevelCanvas.Tool.BOX, Vector2(650, 580))
	var origin := editor.canvas.global_position + editor.canvas.world_to_local(Vector2(650, 580))
	var destination := editor.canvas.global_position + editor.canvas.world_to_local(Vector2(700, 580))
	_mouse(origin, true)
	var motion := InputEventMouseMotion.new()
	motion.position = destination
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	_mouse(destination, false)
	editor._show_library()
	await _save_preview("editor-library", Vector2i(1280, 720))
	editor._library_dialog.hide()
	editor._confirm_replace(editor.new_level)
	await _save_preview("editor-confirm", Vector2i(1280, 720))
	editor._confirm.get_cancel_button().pressed.emit()
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		await _save_preview("editor", viewport_size)
		_click(editor.play_button, true)
		await _save_preview("editor-play", viewport_size, 0.5)
		app.game.set_paused(true)
		await _save_preview("editor-pause", viewport_size)
		_click(app.game.hud._overlay_menu_button, true)
		await create_timer(0.3).timeout
		if app.editor != editor or not editor.is_visible_in_tree():
			push_error("Preview did not return to the editor")
			quit(1)
			return
	print("Saved editor and custom level previews to .artifacts/")
	app.queue_free()
	await process_frame
	quit()


func _place(editor: LevelEditor, tool: LevelCanvas.Tool, point: Vector2, touch: bool = false) -> void:
	var scroll := editor.tool_buttons[tool].get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(editor.tool_buttons[tool])
	await process_frame
	await process_frame
	_click(editor.tool_buttons[tool], touch)
	var position := editor.canvas.global_position + editor.canvas.world_to_local(point)
	_press(position, true, touch)
	_press(position, false, touch)


func _click(button: Button, touch: bool = false) -> void:
	var center := button.get_global_rect().get_center()
	_press(center, true, touch)
	_press(center, false, touch)


func _press(position: Vector2, pressed: bool, touch: bool) -> void:
	if not touch:
		_mouse(position, pressed)
		return
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = 0
	event.pressed = pressed
	root.push_input(event, true)


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func _save_preview(screen: String, viewport_size: Vector2i, delay: float = 0.3) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://.artifacts/preview-%s-%dx%d.png" % [screen, viewport_size.x, viewport_size.y]
	if image.save_png(path) != OK:
		push_error("Could not save " + path)
		quit(1)
