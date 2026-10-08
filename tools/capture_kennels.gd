extends SceneTree
## Виды конур в редакторе и бою; синтетический ввод и настоящие столкновения.

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")

var _failed: bool = false


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
	editor._show_library()
	await create_timer(0.2).timeout
	await _save_preview("library", Vector2i(1280, 720))
	_click(editor._library_list.get_child(1) as BaseButton, true)
	await create_timer(0.2).timeout
	_verify(editor.draft.title == "Двор конур" and editor.draft.dog_house_types.size() == 4, "Встроенный двор конур открывается из библиотеки касанием")
	editor.new_level()
	editor.title_edit.text = "Четыре вида конур"
	editor.title_edit.text_changed.emit(editor.title_edit.text)
	editor.shots_input.value = 12
	var positions: Array[Vector2] = [Vector2(500, 595), Vector2(700, 595), Vector2(910, 595), Vector2(1130, 595)]
	for index in DogHouseTypes.IDS.size():
		editor.canvas.clear_selection()
		editor.house_type_picker.select(index)
		editor.house_type_picker.item_selected.emit(index)
		editor.canvas.material_id = BlockMaterials.IDS[index]
		await _place(editor, positions[index], index % 2 == 1)
	_verify(editor.draft.dog_house_types == PackedStringArray(["classic", "barrel", "igloo", "fortress"]), "Мышь и касания размещают четыре разных вида")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var scroll := editor.house_type_picker.get_parent().get_parent() as ScrollContainer
		scroll.scroll_vertical = 0
		await _save_preview("editor", viewport_size)
		_click(editor.play_button, viewport_size.x != 1280)
		await create_timer(1.1).timeout
		var game: GameRound = app.game
		if game == null:
			_verify(false, "Кнопка испытания запускает бой")
			break
		var residents := 0
		for actor in game.actors.get_children():
			if actor is DogTarget and actor.is_sheltered():
				residents += 1
		_verify(residents == 4 and game.dogs_left == 4, "Четыре конуры устойчивы после начала боя")
		await _save_preview("battle", viewport_size, 0.05)
		game.set_paused(true)
		if viewport_size.x == 960:
			await _save_preview("pause", viewport_size, 0.05)
		_click(game.hud._overlay_menu_button, true)
		await create_timer(0.3).timeout
		_verify(app.editor == editor and editor.is_visible_in_tree(), "Возврат сохраняет черновик с четырьмя конурами")
	root.size = Vector2i(1280, 720)
	for index in DogHouseTypes.IDS.size():
		await _physical_release(app, editor, index)
	app.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("Kennel previews: %s. Images: .artifacts/preview-kennels-*.png" % ("FAILED" if _failed else "passed"))
	quit(1 if _failed else 0)


func _physical_release(app: GameApp, editor: LevelEditor, index: int) -> void:
	editor.new_level()
	editor.house_type_picker.select(index)
	editor.house_type_picker.item_selected.emit(index)
	# Один материал отделяет различия формы от прочности покрытия.
	editor.canvas.material_id = &"glass"
	await _place(editor, Vector2(900, 595), index % 2 == 1)
	_click(editor.play_button, index % 2 == 1)
	await create_timer(0.7).timeout
	var game: GameRound = app.game
	if game == null:
		_verify(false, "Запущена площадка для разрушения конуры")
		return
	var dog := get_nodes_in_group("targets")[0] as DogTarget
	var house: DogHouse = dog.shelter
	var type_name := String(DogHouseTypes.IDS[index])
	_verify(house != null and house.house_type == DogHouseTypes.IDS[index], "Физическая площадка использует вид " + type_name)
	if house == null:
		game.return_to_menu()
		await create_timer(0.2).timeout
		return
	await _save_preview(type_name + "-sheltered", Vector2i(1280, 720), 0.05)
	var cat: CatProjectile = game.slingshot.loaded_projectile
	var anchor: Vector2 = game.slingshot.get_global_transform_with_canvas().origin
	var shots := game.shots_left
	_press(anchor, true, index % 2 == 1)
	_press(anchor + Vector2(-95, 0), false, index % 2 == 1)
	_verify(cat.was_launched and game.shots_left == shots - 1, "Мышь/касание запускает ровно одного кота: " + type_name)
	# После настоящего жеста фиксируем траекторию, чтобы проверять столкновение,
	# а не баланс прицеливания для каждого размера конуры.
	cat.position = house.position + Vector2(-180, -25)
	cat.gravity_scale = 0.0
	# Умеренный удар об иглу отделяет разрушение от опасного скольжения
	# освобождённой собаки по земле после более сильного толчка.
	cat.linear_velocity = Vector2(450 if index == 2 else 1800, 0)
	cat.angular_velocity = 0.0
	await create_timer(0.35 if index == 2 else 0.2).timeout
	_verify(not is_instance_valid(house), "Физическое попадание разрушает вид " + type_name)
	_verify(is_instance_valid(dog) and not dog.is_destroyed and not dog.is_sheltered(), "Разрушенная конура освобождает живую собаку: " + type_name)
	await _save_preview(type_name + "-released", Vector2i(1280, 720), 0.02)
	if is_instance_valid(cat):
		cat.queue_free()
	if is_instance_valid(dog) and not dog.is_sheltered():
		var finisher := CAT_SCENE.instantiate() as CatProjectile
		finisher.position = dog.position + Vector2(110, 0)
		finisher.gravity_scale = 0.0
		game.actors.add_child(finisher)
		finisher.launch(Vector2(-1600, 0))
		await create_timer(0.15).timeout
		_verify(not is_instance_valid(dog) or dog.is_destroyed, "Следующее физическое попадание поражает открытую цель: " + type_name)
	game.return_to_menu()
	await create_timer(0.2).timeout


func _place(editor: LevelEditor, point: Vector2, touch: bool) -> void:
	var button: Button = editor.tool_buttons[LevelCanvas.Tool.DOG_HOUSE]
	var scroll := button.get_parent().get_parent() as ScrollContainer
	# Описание выбранного вида меняет минимальную высоту колонки отложенно.
	await _settle_layout()
	scroll.ensure_control_visible(button)
	await _settle_layout()
	_click(button, touch)
	_verify(editor.canvas.tool == LevelCanvas.Tool.DOG_HOUSE, "Мышь/касание выбирает инструмент конуры")
	await process_frame
	var position := editor.canvas.global_position + editor.canvas.world_to_local(point)
	_press(position, true, touch)
	_press(position, false, touch)
	await _settle_layout()


func _click(button: BaseButton, touch: bool = false) -> void:
	var center := button.get_global_rect().get_center()
	# AcceptDialog является отдельным Viewport: его локальные координаты
	# нельзя передавать корневому окну как координаты основного интерфейса.
	_press(center, true, touch, button.get_viewport())
	_press(center, false, touch, button.get_viewport())


func _press(position: Vector2, pressed: bool, touch: bool, input_viewport: Viewport = null) -> void:
	var target_viewport: Viewport = root if input_viewport == null else input_viewport
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.index = 0
		event.pressed = pressed
		target_viewport.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		target_viewport.push_input(event, true)


func _settle_layout() -> void:
	await process_frame
	await process_frame
	await process_frame
	await process_frame


func _save_preview(screen: String, viewport_size: Vector2i, delay: float = 0.3) -> void:
	await create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var path := "res://.artifacts/preview-kennels-%s-%dx%d.png" % [screen, viewport_size.x, viewport_size.y]
	_verify(screenshot.save_png(path) == OK, "Сохранён снимок " + path)


func _verify(condition: bool, description: String) -> void:
	if not condition:
		_failed = true
		push_error(description)
