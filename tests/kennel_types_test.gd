extends SceneTree
## Виды конур: совместимость ресурсов, геометрия, защита и история редактора.

const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const EDITOR_SCENE := preload("res://scenes/editor/level_editor.tscn")

var _checks: int = 0
var _failures: int = 0
var _created_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_compatibility()
	_test_storage()
	await _test_shelters()
	await _test_round()
	await _test_editor()
	for path in _created_paths:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(path) == OK, "Удалён созданный тестом ресурс")
	print("Kennel type checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _four_houses() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.title = "Четыре конуры"
	level.dog_positions = PackedVector2Array([Vector2(500, 595), Vector2(700, 595), Vector2(910, 595), Vector2(1130, 595)])
	level.dog_house_materials = PackedStringArray(["wood", "glass", "stone", "metal"])
	level.dog_house_types = PackedStringArray(["classic", "barrel", "igloo", "fortress"])
	return level


func _test_compatibility() -> void:
	var legacy := LevelDefinition.new()
	legacy.dog_positions = PackedVector2Array([Vector2(700, 595), Vector2(1050, 595)])
	legacy.dog_house_materials = PackedStringArray(["wood", ""])
	_check(legacy.is_valid(), "Ресурс со старой будкой без списка видов остаётся валидным")
	_check(legacy.dog_house_type_at(0) == &"classic" and legacy.dog_house_type_at(1) == &"", "Старые будки становятся классическими, открытые собаки остаются открытыми")
	legacy.normalize_materials()
	_check(legacy.dog_house_types == PackedStringArray(["classic", ""]) and legacy.is_valid(), "Нормализация сохраняет совместимость старого уровня")
	legacy.dog_house_types = PackedStringArray(["barrel"])
	_check(not legacy.is_valid(), "Частичный список видов отклоняется")
	legacy.dog_house_types = PackedStringArray(["unknown", ""])
	_check(not legacy.is_valid(), "Неизвестный вид конуры отклоняется")
	legacy.dog_house_types = PackedStringArray(["classic", "igloo"])
	_check(not legacy.is_valid(), "Вид конуры без материала укрытия отклоняется")
	legacy.dog_house_types = PackedStringArray(["", ""])
	_check(not legacy.is_valid(), "Явно пустой вид существующей конуры отклоняется")
	legacy.dog_house_materials.clear()
	legacy.dog_house_types.clear()
	legacy.normalize_materials()
	_check(legacy.is_valid() and legacy.dog_house_types == PackedStringArray(["", ""]), "Старый уровень без укрытий не получает их при нормализации")
	var mixed := _four_houses()
	_check(mixed.is_valid(), "Разные конуры и материалы могут находиться на одном уровне")
	for house_type: StringName in DogHouseTypes.IDS:
		mixed.dog_house_types.fill(String(house_type))
		_check(mixed.is_valid(), "Вид сочетается со всеми четырьмя материалами: " + String(house_type))


func _test_storage() -> void:
	var level := _four_houses()
	var saved: Dictionary = LevelLibrary.save_level(level)
	_check(saved["error"] == OK, "Все четыре вида сохраняются")
	if saved["error"] != OK:
		return
	var path: String = saved["path"]
	_created_paths.append(path)
	var loaded := LevelLibrary.load_level(path)
	_check(loaded != null and loaded.dog_house_types == level.dog_house_types and loaded.dog_house_materials == level.dog_house_materials, "Загрузка сохраняет вид отдельно от материала")
	if loaded == null:
		return
	loaded.dog_house_types[0] = "fortress"
	loaded.dog_house_materials[1] = "wood"
	var copied: Dictionary = LevelLibrary.save_level(loaded)
	_check(copied["error"] == OK and copied["path"] != path, "Сохранение изменённой копии создаёт отдельный файл")
	if copied["error"] == OK:
		_created_paths.append(copied["path"])
	var unchanged := LevelLibrary.load_level(path)
	_check(unchanged != null and unchanged.dog_house_types == level.dog_house_types and unchanged.dog_house_materials == level.dog_house_materials, "Правки копии не меняют исходные виды и материалы")
	loaded.dog_house_types[0] = "unknown"
	_check(LevelLibrary.save_level(loaded, path)["error"] == ERR_INVALID_DATA, "Некорректный вид не перезаписывает существующий уровень")


func _test_shelters() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var sizes: Array[Vector2] = []
	var hit_points: Dictionary = {}
	for house_type: StringName in DogHouseTypes.IDS:
		var house := HOUSE_SCENE.instantiate() as DogHouse
		house.house_type = house_type
		house.material_id = &"wood"
		house.freeze = true
		house.position = Vector2(700, 350)
		arena.add_child(house)
		sizes.append(house.size)
		hit_points[house_type] = house.hits_left
		var shape: Shape2D = house.get_node("CollisionShape2D").shape
		var collision_bounds := _collision_bounds(shape)
		_check(Rect2(-house.size * 0.5, house.size).encloses(collision_bounds) and collision_bounds.size.x >= house.size.x * 0.8 and collision_bounds.size.y >= house.size.y * 0.8 and house.size == DogHouse.size_for(house_type), "Коллизия соответствует геометрии вида: " + String(house_type))
		var dog := DOG_SCENE.instantiate() as DogTarget
		dog.definition = CharacterCatalog.find_dog(&"scout")
		dog.gravity_scale = 0.0
		arena.add_child(dog)
		var collision_layer := dog.collision_layer
		var collision_mask := dog.collision_mask
		dog.enter_shelter(house)
		_check(dog.is_sheltered() and dog.global_position.is_equal_approx(house.to_global(house.dog_offset())), "Собака занимает вход нужной конуры: " + String(house_type))
		dog.receive_hit(3000.0)
		dog.apply_frost(2.0)
		_check(not dog.is_destroyed and dog.frost_time_left == 0.0 and dog.freeze, "Укрытие защищает от удара и заморозки: " + String(house_type))
		house.position += Vector2(60, -20)
		house.rotation = 0.4
		await physics_frame
		await physics_frame
		_check(dog.global_position.distance_to(house.to_global(DogHouse.offset_for(house_type))) < 1.0 and is_equal_approx(dog.global_rotation, house.global_rotation), "Собака следует за смещением и поворотом конуры: " + String(house_type))
		house.receive_hit(house.impact_threshold * 20.0)
		await _settle()
		_check(not is_instance_valid(house) and is_instance_valid(dog) and not dog.is_sheltered() and not dog.is_destroyed, "Разрушение освобождает живую собаку: " + String(house_type))
		_check(not dog.freeze and dog.collision_layer == collision_layer and dog.collision_mask == collision_mask, "После освобождения восстанавливаются физика и коллизии: " + String(house_type))
		dog.receive_hit(1000.0)
		_check(dog.is_destroyed, "Открытая собака доступна для следующего попадания: " + String(house_type))
		await _settle()
	_check(sizes[0] != sizes[1] and sizes[0] != sizes[2] and sizes[0] != sizes[3] and sizes[1] != sizes[2] and sizes[1] != sizes[3] and sizes[2] != sizes[3], "Четыре вида имеют разные габариты")
	_check(hit_points[&"barrel"] < hit_points[&"classic"] and hit_points[&"classic"] < hit_points[&"fortress"], "При одном материале бочка легче разрушается, крепость прочнее обычной конуры")
	var glass := HOUSE_SCENE.instantiate() as DogHouse
	glass.house_type = &"igloo"
	glass.material_id = &"glass"
	glass.freeze = true
	arena.add_child(glass)
	var metal := HOUSE_SCENE.instantiate() as DogHouse
	metal.house_type = &"igloo"
	metal.material_id = &"metal"
	metal.position.x = 300.0
	metal.freeze = true
	arena.add_child(metal)
	_check(glass.size == metal.size and glass.dog_offset() == metal.dog_offset(), "Материал не меняет геометрию и посадку собаки")
	_check(glass.mass < metal.mass and glass.hits_left < metal.hits_left and glass.impact_threshold < metal.impact_threshold, "Выбранный материал сохраняет влияние на массу и прочность конуры")
	arena.queue_free()
	await _settle()


func _test_round() -> void:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = _four_houses()
	root.add_child(game)
	current_scene = game
	await create_timer(1.0).timeout
	var found_types: Array[StringName] = []
	var sheltered := 0
	for actor in game.actors.get_children():
		if actor is DogHouse:
			found_types.append(actor.house_type)
		if actor is DogTarget and actor.is_sheltered():
			sheltered += 1
			_check(actor.global_position.distance_to(actor.shelter.to_global(actor.shelter.dog_offset())) < 1.0, "Бой размещает собаку во входе её конуры")
	_check(found_types.size() == 4 and sheltered == 4 and game.dogs_left == 4, "Бой создаёт все виды и сохраняет цели после оседания")
	for house_type: StringName in DogHouseTypes.IDS:
		_check(found_types.has(house_type), "В бой перенесён вид " + String(house_type))
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		await _settle()
		var ground_screen_y: float = (game.get_global_transform_with_canvas() * Vector2(0, 620)).y
		_check(game.hud._ability_button.get_global_rect().position.y >= ground_screen_y, "Кнопка способности находится под землёй и не закрывает конуры в окне %dx%d" % [viewport_size.x, viewport_size.y])
	root.size = Vector2i(1280, 720)
	await _settle()
	game.queue_free()
	await _settle()


func _test_editor() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	current_scene = editor
	await _settle()
	editor.new_level()
	var positions := _four_houses().dog_positions
	for index in DogHouseTypes.IDS.size():
		editor.canvas.clear_selection()
		editor.house_type_picker.select(index)
		editor.house_type_picker.item_selected.emit(index)
		editor.canvas.material_id = BlockMaterials.IDS[index]
		await _place(editor, LevelCanvas.Tool.DOG_HOUSE, positions[index], index % 2 == 1)
		_check(editor.draft.dog_positions.size() == index + 1 and editor.draft.dog_house_type_at(index) == DogHouseTypes.IDS[index], "Выбор вида и мышь/касание добавляют одну соответствующую конуру")
		_check(editor.canvas.selected_size() == DogHouse.size_for(DogHouseTypes.IDS[index]) and editor.canvas.selected_house_type() == DogHouseTypes.IDS[index], "Выделение сообщает геометрию и вид конуры")
	_check(editor.draft.dog_house_materials == PackedStringArray(["wood", "glass", "stone", "metal"]), "Выбор формы не подменяет материал")
	_canvas_click(editor.canvas, editor.draft.dog_positions[1])
	editor.canvas.move_selected(Vector2(1240, 100))
	var old_position := editor.draft.dog_positions[1]
	var history_size := editor._undo_stack.size()
	editor.canvas.set_selected_house_type(&"fortress")
	var adjusted := editor.draft.dog_positions[1]
	var dimensions := DogHouse.size_for(&"fortress")
	var bounds := Rect2(adjusted - DogHouse.offset_for(&"fortress") - dimensions * 0.5, dimensions)
	_check(LevelCanvas.BUILD_AREA.encloses(bounds) and adjusted != old_position, "Смена маленькой конуры у границы сдвигает большую целиком в область строительства")
	_check(editor._undo_stack.size() == history_size + 1 and editor.draft.dog_house_material_at(1) == &"glass", "Смена вида создаёт одну правку и сохраняет материал")
	editor.undo()
	_check(editor.draft.dog_house_type_at(1) == &"barrel" and editor.draft.dog_positions[1] == old_position, "Отмена возвращает вид и координаты до ограничения границей")
	editor.redo()
	_check(editor.draft.dog_house_type_at(1) == &"fortress" and editor.draft.dog_positions[1] == adjusted, "Возврат восстанавливает вид и безопасные координаты")
	_canvas_click(editor.canvas, adjusted)
	editor.canvas.set_selected_material(&"stone")
	_check(editor.draft.dog_house_type_at(1) == &"fortress", "Смена материала не меняет выбранную форму")
	editor.undo()
	editor.undo()
	var path := "user://levels/test_kennel_editor_%d.tres" % Time.get_ticks_usec()
	_created_paths.append(path)
	editor.current_path = path
	editor.save_level()
	var loaded := LevelLibrary.load_level(path)
	_check(loaded != null and loaded.dog_house_types == editor.draft.dog_house_types and loaded.dog_house_materials == editor.draft.dog_house_materials, "Редактор сохраняет четыре вида и независимые материалы")
	_canvas_click(editor.canvas, editor.draft.dog_positions[2])
	editor.canvas.delete_selected()
	_check(editor.draft.dog_positions.size() == 3 and editor.draft.dog_house_types == PackedStringArray(["classic", "barrel", "fortress"]), "Удаление убирает вид вместе с соответствующей собакой")
	editor.undo()
	_check(editor.draft.dog_house_types == PackedStringArray(["classic", "barrel", "igloo", "fortress"]) and editor.draft.is_valid(), "Отмена удаления восстанавливает согласованные данные")
	editor.canvas.clear_selection()
	await _place(editor, LevelCanvas.Tool.DOG, Vector2(780, 360), true)
	editor.canvas.set_selected_house_type(&"igloo")
	_check(editor.draft.dog_house_type_at(4) == &"" and editor.draft.dog_house_material_at(4) == &"", "Смена вида не превращает открытую собаку в конуру")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		await _settle()
		var scroll := editor.house_type_picker.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(editor.house_type_picker)
		await _settle()
		_check(scroll.get_global_rect().encloses(editor.house_type_picker.get_global_rect()) and root.get_visible_rect().encloses(editor.play_button.get_global_rect()) and editor.canvas.size.x >= 300.0, "Выбор вида и пробный бой доступны в окне %dx%d" % [viewport_size.x, viewport_size.y])
	root.size = Vector2i(1280, 720)
	editor.queue_free()
	await _settle()


func _collision_bounds(shape: Shape2D) -> Rect2:
	if shape is RectangleShape2D:
		return Rect2(-shape.size * 0.5, shape.size)
	if shape is ConvexPolygonShape2D and not shape.points.is_empty():
		var bounds := Rect2(shape.points[0], Vector2.ZERO)
		for point: Vector2 in shape.points:
			bounds = bounds.expand(point)
		return bounds
	return Rect2()


func _place(editor: LevelEditor, tool: LevelCanvas.Tool, point: Vector2, touch: bool = false) -> void:
	var scroll := editor.tool_buttons[tool].get_parent().get_parent() as ScrollContainer
	await _settle()
	scroll.ensure_control_visible(editor.tool_buttons[tool])
	await _settle()
	var center := editor.tool_buttons[tool].get_global_rect().get_center()
	_press(center, true, touch)
	_press(center, false, touch)
	await process_frame
	_canvas_click(editor.canvas, point, touch)
	await _settle()


func _canvas_click(canvas: LevelCanvas, point: Vector2, touch: bool = false) -> void:
	var position := canvas.global_position + canvas.world_to_local(point)
	_press(position, true, touch)
	_press(position, false, touch)


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


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
