extends SceneTree
## Play a short repeatable animation demo; --write-movie may record it with audio.


func _initialize() -> void:
	_showcase.call_deferred()


func _showcase() -> void:
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	await create_timer(1.2).timeout
	app.start_game(&"classic", &"jumper")
	await create_timer(1.6).timeout
	await _shot(app.game)
	await create_timer(1.6).timeout
	app.start_game(&"zigzag", &"armored")
	await create_timer(0.9).timeout
	await _shot(app.game)
	await create_timer(1.8).timeout
	app.show_sandbox()
	await create_timer(0.1).timeout
	app.menu.show_species(&"dog")
	await create_timer(1.2).timeout
	app.queue_free()
	await process_frame
	quit()


func _shot(game: GameRound) -> void:
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_mouse(anchor, true)
	for step in 12:
		var motion := InputEventMouseMotion.new()
		motion.position = anchor + Vector2(-90, 48) * (float(step + 1) / 12.0)
		root.push_input(motion, true)
		await create_timer(0.02).timeout
	await create_timer(0.25).timeout
	_mouse(anchor + Vector2(-90, 48), false)
	await create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/animation-flight-%s.png" % game.cat_definition.id)


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)
