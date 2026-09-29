extends SceneTree
## Графическая проверка материалов и будок: реальные столкновения, мышь и касания.

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")

var _failed: bool = false


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
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
	editor.title_edit.text = "Будка и башня: четыре материала"
	editor.title_edit.text_changed.emit(editor.title_edit.text)
	editor.shots_input.value = 5
	await process_frame
	editor.canvas.material_id = &"stone"
	await _place(editor, LevelCanvas.Tool.TOWER, Vector2(1080, 540))
	var roof_position := editor.draft.block_positions[2]
	_canvas_click(editor.canvas, roof_position)
	editor.canvas.set_selected_material(&"glass")
	_canvas_click(editor.canvas, editor.draft.block_positions[1])
	editor.canvas.set_selected_material(&"metal")
	await _place(editor, LevelCanvas.Tool.DOG, Vector2(1080, 590), true)
	editor.canvas.material_id = &"wood"
	await _place(editor, LevelCanvas.Tool.DOG_HOUSE, Vector2(790, 595), true)
	_verify(editor.draft.dog_positions.size() == 2 and editor.draft.block_positions.size() == 3, "Мышь и касание размещают башню и собаку в будке")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		var scroll := editor.material_picker.get_parent().get_parent() as ScrollContainer
		scroll.scroll_vertical = 0
		await _save_preview("editor", viewport_size)
		_click(editor.play_button, viewport_size.x != 1280)
		await create_timer(1.1).timeout
		var game: GameRound = app.game
		if game == null:
			_verify(false, "Кнопка испытания запускает бой")
			break
		game.set_paused(false)
		await _save_preview("sheltered", viewport_size, 0.05)
		var dog: DogTarget
		for actor in game.actors.get_children():
			if actor is DogTarget and actor.is_sheltered():
				dog = actor
		if dog == null:
			_verify(false, "В бою есть собака в будке")
			break
		var house: DogHouse = dog.shelter
		var shots := game.shots_left
		var cat: CatProjectile = game.slingshot.loaded_projectile
		var anchor: Vector2 = game.slingshot.get_global_transform_with_canvas().origin
		var touch: bool = viewport_size.x != 1280
		_press(anchor, true, touch)
		_press(anchor + Vector2(-95, 0), false, touch)
		_verify(game.shots_left == shots - 1 and cat.was_launched, "Жест запускает ровно одного кота в окне %dx%d" % [viewport_size.x, viewport_size.y])
		# Начальную траекторию задаём после настоящего жеста: проверяем столкновение,
		# не привязываясь к текущему балансу рогатки или размерам окна.
		cat.position = house.position + Vector2(-160, -18)
		cat.gravity_scale = 0.0
		cat.linear_velocity = Vector2(1600, 0)
		cat.angular_velocity = 0.0
		await create_timer(0.18).timeout
		_verify(not is_instance_valid(house), "Физическое попадание разрушает будку")
		_verify(is_instance_valid(dog) and not dog.is_destroyed and not dog.is_sheltered(), "После попадания собака выходит из будки живой")
		await _save_preview("released", viewport_size, 0.02)
		if is_instance_valid(cat):
			cat.queue_free()
		if is_instance_valid(dog):
			var finisher := CAT_SCENE.instantiate() as CatProjectile
			finisher.position = dog.position + Vector2(110, 0)
			finisher.gravity_scale = 0.0
			game.actors.add_child(finisher)
			finisher.launch(Vector2(-1600, 0))
			await create_timer(0.15).timeout
			_verify(not is_instance_valid(dog) or dog.is_destroyed, "Следующее физическое попадание поражает открытую цель")
		game.set_paused(true)
		await _save_preview("pause", viewport_size, 0.05)
		_click(game.hud._overlay_menu_button, true)
		await create_timer(0.3).timeout
		_verify(app.editor == editor and editor.is_visible_in_tree(), "Возврат сохраняет черновик строений")
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Material previews: %s. Images: .artifacts/preview-materials-*.png" % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)


func _place(editor: LevelEditor, tool: LevelCanvas.Tool, point: Vector2, touch: bool = false) -> void:
	var scroll := editor.tool_buttons[tool].get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(editor.tool_buttons[tool])
	await process_frame
	await process_frame
	_click(editor.tool_buttons[tool], touch)
	_canvas_click(editor.canvas, point, touch)


func _canvas_click(canvas: LevelCanvas, point: Vector2, touch: bool = false) -> void:
	var position := canvas.global_position + canvas.world_to_local(point)
	_press(position, true, touch)
	_press(position, false, touch)


func _click(button: BaseButton, touch: bool = false) -> void:
	var center := button.get_global_rect().get_center()
	_press(center, true, touch)
	_press(center, false, touch)


func _press(position: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _save_preview(screen: String, viewport_size: Vector2i, delay: float = 0.3) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://.artifacts/preview-materials-%s-%dx%d.png" % [screen, viewport_size.x, viewport_size.y]
	_verify(image.save_png(path) == OK, "Сохранён снимок " + path)


func _verify(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error(description)
