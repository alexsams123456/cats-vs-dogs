extends SceneTree
## Optional visual check: Godot --path . --script res://tools/capture_preview.gd


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	app.show_sandbox()
	await create_timer(0.1).timeout
	for size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = size
		app.menu.show_species(&"cat")
		app.menu.select_character(&"bomb")
		await _save_preview("menu-cats", size)
		app.menu.show_species(&"dog")
		app.menu.select_character(&"armored")
		await _save_preview("menu-dogs", size)
		app.start_game(&"bomb", &"armored")
		await _save_preview("game", size)
		app.game.set_paused(true)
		await _save_preview("pause", size)
		app.show_sandbox()
		await create_timer(0.1).timeout
	root.size = Vector2i(1280, 720)
	app.start_game(&"bomb", &"armored")
	await create_timer(0.9).timeout
	_drag_cat(app.game, Vector2(-95, 42))
	await create_timer(0.7).timeout
	var ability_key := InputEventKey.new()
	ability_key.physical_keycode = KEY_E
	ability_key.pressed = true
	root.push_input(ability_key, true)
	await _save_preview("explosion", root.size, 0.12)
	app.start_game(&"zigzag", &"jumper")
	await create_timer(0.9).timeout
	_drag_cat(app.game, Vector2(-95, 42))
	await _save_preview("zigzag", root.size, 0.65)
	print("Saved menu, game, pause and ability previews to .artifacts/")
	app.queue_free()
	await process_frame
	quit()


func _save_preview(screen: String, viewport_size: Vector2i, delay: float = 0.4) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://.artifacts/preview-%s-%dx%d.png" % [screen, viewport_size.x, viewport_size.y]
	if image.save_png(path) != OK:
		push_error("Could not save " + path)
		quit(1)


func _drag_cat(game: GameRound, pull: Vector2) -> void:
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = anchor if pressed else anchor + pull
		event.pressed = pressed
		root.push_input(event, true)
