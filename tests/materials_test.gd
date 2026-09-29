extends SceneTree
## Материалы, укрытия, независимое хранение и составные инструменты редактора.

const BLOCK_SCENE := preload("res://scenes/actors/wooden_block.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const EDITOR_SCENE := preload("res://scenes/editor/level_editor.tscn")

var _checks: int = 0
var _failures: int = 0
var _created_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_level_data()
	_test_storage()
	await _test_material_strength()
	await _test_shelter()
	await _test_removed_shelter()
	await _test_bomb_shelter(false)
	await _test_bomb_shelter(true)
	await _test_round()
	await _test_house_out_of_bounds()
	await _test_editor()
	for path in _created_paths:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(path) == OK, "Удалён только созданный тестом файл")
	print("Materials checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _legacy_level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.title = "Проверка материалов"
	level.dog_positions = PackedVector2Array([Vector2(1100, 595)])
	level.block_positions = PackedVector2Array([Vector2(850, 570), Vector2(950, 570)])
	level.block_sizes = PackedVector2Array([Vector2(50, 100), Vector2(50, 100)])
	return level


func _test_level_data() -> void:
	var level := _legacy_level()
	_check(level.is_valid(), "Старый ресурс без массивов материалов остаётся валидным")
	_check(level.block_material_at(0) == &"wood" and level.dog_house_material_at(0) == &"", "Старые блоки деревянные, старые собаки без укрытия")
	level.normalize_materials()
	_check(level.block_materials == PackedStringArray(["wood", "wood"]) and level.dog_house_materials == PackedStringArray([""]), "Нормализация заполняет совместимые значения")
	level.block_materials = PackedStringArray(["glass"])
	_check(not level.is_valid(), "Частичный массив материалов блоков отклоняется")
	level.block_materials = PackedStringArray(["glass", "unknown"])
	_check(not level.is_valid(), "Неизвестный материал блока отклоняется")
	level.block_materials = PackedStringArray(["", "wood"])
	_check(not level.is_valid(), "Пустой материал отдельного блока отклоняется")
	level.block_materials = PackedStringArray(["glass", "stone"])
	level.dog_house_materials = PackedStringArray(["wood", "metal"])
	_check(not level.is_valid(), "Массив будок должен соответствовать целям")
	level.dog_house_materials = PackedStringArray(["unknown"])
	_check(not level.is_valid(), "Неизвестный материал будки отклоняется")
	level.dog_house_materials = PackedStringArray(["metal"])
	level.dog_house_types = PackedStringArray(["classic"])
	_check(level.is_valid(), "Разные материалы и укрытие сохраняют валидность")
	_check(not BlockMaterials.is_known(&"unknown"), "Каталог не принимает неизвестный ID")
	var copy := level.duplicate(true) as LevelDefinition
	copy.block_materials[0] = "wood"
	copy.dog_house_materials[0] = ""
	copy.dog_house_types[0] = ""
	_check(level.block_material_at(0) == &"glass" and level.dog_house_material_at(0) == &"metal", "Правка копии не меняет материалы оригинала")


func _test_storage() -> void:
	var level := _legacy_level()
	level.block_materials = PackedStringArray(["glass", "stone"])
	level.dog_house_materials = PackedStringArray(["metal"])
	var saved: Dictionary = LevelLibrary.save_level(level)
	_check(saved["error"] == OK, "Материалы сохраняются в пользовательский ресурс")
	if saved["error"] != OK:
		return
	var path: String = saved["path"]
	_created_paths.append(path)
	var loaded := LevelLibrary.load_level(path)
	_check(loaded != null and loaded.block_materials == level.block_materials and loaded.dog_house_materials == level.dog_house_materials, "Повторная загрузка сохраняет материалы блоков и будки")
	if loaded == null:
		return
	loaded.block_materials[1] = "metal"
	loaded.dog_house_materials[0] = "glass"
	var copy_result: Dictionary = LevelLibrary.save_level(loaded)
	_check(copy_result["error"] == OK and copy_result["path"] != path, "Копия получает отдельный путь")
	if copy_result["error"] == OK:
		_created_paths.append(copy_result["path"])
	var unchanged := LevelLibrary.load_level(path)
	_check(unchanged != null and unchanged.block_materials == level.block_materials and unchanged.dog_house_materials == level.dog_house_materials, "Сохранение копии не меняет исходный файл")
	loaded.block_materials[0] = "unknown"
	_check(LevelLibrary.save_level(loaded, path)["error"] == ERR_INVALID_DATA, "Неверный материал не может перезаписать сохранение")


func _test_material_strength() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var thresholds: Array[float] = [345.0, 220.0, 430.0, 520.0]
	var hit_points: Array[int] = [1, 1, 2, 3]
	var masses: Array[float] = []
	for index in BlockMaterials.IDS.size():
		var id: StringName = BlockMaterials.IDS[index]
		var block := BLOCK_SCENE.instantiate() as WoodenBlock
		block.material_id = id
		block.freeze = true
		arena.add_child(block)
		masses.append(block.mass)
		_check(BlockMaterials.get_definition(id) != null and block.hits_left == hit_points[index] and is_equal_approx(block.impact_threshold, thresholds[index]), "Параметры материала применяются до первого удара: " + String(id))
		block.receive_hit(thresholds[index] - 1.0)
		_check(not block.is_destroyed and block.hits_left == hit_points[index], "Слабый удар не повреждает материал: " + String(id))
		block.receive_hit(thresholds[index] + 1.0)
		_check(block.hits_left == hit_points[index] - 1, "Достаточный удар снимает одну единицу прочности: " + String(id))
		if hit_points[index] > 1:
			block.receive_hit(thresholds[index] * 4.0)
			_check(not block.is_destroyed and block.hits_left == hit_points[index] - 1, "Один контакт не расходует остаток прочности: " + String(id))
			await create_timer(block.hit_cooldown_seconds + 0.05).timeout
			block.receive_hit(thresholds[index] * 4.0)
		_check(block.is_destroyed, "Сильный повторный удар разрушает материал: " + String(id))
		await _settle()
	_check(masses[1] < masses[0] and masses[0] < masses[2] and masses[2] < masses[3], "Стекло легче дерева, камень и металл тяжелее")
	arena.queue_free()
	await _settle()


func _test_shelter() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.position = Vector2(700, 350)
	house.freeze = true
	arena.add_child(house)
	var dog := _dog(arena, &"armored", house.position + Vector2(0, 37))
	var collision_layer := dog.collision_layer
	var collision_mask := dog.collision_mask
	dog.enter_shelter(house)
	_check(dog.is_sheltered() and dog.freeze and house.hits_left >= 2, "Будка удерживает собаку и выдерживает минимум два обычных удара")
	dog.receive_hit(2000.0)
	_check(not dog.is_destroyed and dog.shield_active, "Удар сквозь будку не расходует собаку или её щит")
	house.receive_hit(house.impact_threshold + 1.0)
	_check(not house.is_destroyed and dog.is_sheltered(), "Повреждённая будка продолжает защищать собаку")
	house.position += Vector2(60, -20)
	await physics_frame
	await physics_frame
	_check(dog.global_position.distance_to(house.global_position + Vector2(0, 37)) < 1.0, "Собака перемещается вместе с укрытием")
	house.destroy()
	await _settle()
	_check(is_instance_valid(dog) and not dog.is_sheltered() and not dog.freeze and not dog.is_destroyed, "Разрушение будки освобождает живую собаку")
	_check(dog.collision_layer == collision_layer and dog.collision_mask == collision_mask, "После освобождения восстановлены коллизии цели")
	await create_timer(0.3).timeout
	dog.receive_hit(900.0)
	_check(not dog.is_destroyed and not dog.shield_active, "Освобождённый бульдог сохраняет обычную защиту щитом")
	await create_timer(dog.hit_cooldown_seconds + 0.05).timeout
	dog.receive_hit(900.0)
	_check(dog.is_destroyed, "Следующий удар поражает освобождённую цель")
	arena.queue_free()
	await _settle()


func _test_removed_shelter() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.position = Vector2(700, 350)
	house.freeze = true
	arena.add_child(house)
	var dog := _dog(arena, &"jumper", house.position + Vector2(0, 37))
	dog.enter_shelter(house)
	dog.apply_frost(2.0)
	_check(dog.frost_time_left == 0.0, "Будка защищает собаку от заморозки")
	house.queue_free()
	await _settle()
	_check(is_instance_valid(dog) and not dog.is_sheltered() and not dog.freeze and dog.collision_layer != 0, "Удаление будки из дерева также освобождает цель")
	arena.queue_free()
	await _settle()


func _test_bomb_shelter(dog_first: bool) -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.position = Vector2(700, 350)
	house.freeze = true
	var dog: DogTarget
	if dog_first:
		dog = _dog(arena, &"scout", house.position + Vector2(0, 37))
		arena.add_child(house)
	else:
		arena.add_child(house)
		dog = _dog(arena, &"scout", house.position + Vector2(0, 37))
	dog.enter_shelter(house)
	var bomb := CAT_SCENE.instantiate() as CatProjectile
	bomb.definition = CharacterCatalog.find_cat(&"bomb")
	bomb.position = house.position
	bomb.gravity_scale = 0.0
	arena.add_child(bomb)
	bomb.launch(Vector2.ZERO)
	bomb.activate_ability()
	await _settle()
	_check(not is_instance_valid(house), "Взрыв разрушает деревянную будку; порядок цели: " + str(dog_first))
	_check(is_instance_valid(dog) and not dog.is_destroyed and not dog.is_sheltered(), "Тот же взрыв оставляет освобождённую цель живой; порядок цели: " + str(dog_first))
	arena.queue_free()
	await _settle()


func _test_round() -> void:
	var game := MAIN_SCENE.instantiate() as GameRound
	root.add_child(game)
	current_scene = game
	var initial_dogs := game.dogs_left
	var initial_blocks := get_nodes_in_group("blocks").size()
	await create_timer(2.0).timeout
	_check(game.dogs_left == initial_dogs and get_nodes_in_group("blocks").size() == initial_blocks, "Новый встроенный двор устойчив после оседания")
	var protected_dog: DogTarget
	var materials: Array[StringName] = []
	for actor in game.actors.get_children():
		if actor is WoodenBlock and not materials.has(actor.material_id):
			materials.append(actor.material_id)
		if actor is DogTarget and actor.is_sheltered():
			protected_dog = actor
	_check(materials.size() >= 3, "В бою создаются разные материалы уровня")
	_check(protected_dog != null, "Встроенный двор содержит собаку в будке")
	if protected_dog != null:
		protected_dog.shelter.destroy()
		await _settle()
		_check(game.dogs_left == initial_dogs and game.state == GameRound.RoundState.READY, "Разрушение будки не засчитывается как поражение цели")
	game.queue_free()
	await _settle()


func _test_house_out_of_bounds() -> void:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = LevelDefinition.new()
	game.level.shots = 1
	game.level.dog_positions = PackedVector2Array([Vector2(800, 595)])
	game.level.dog_house_materials = PackedStringArray(["wood"])
	root.add_child(game)
	current_scene = game
	var dog := get_nodes_in_group("targets")[0] as DogTarget
	game.slingshot.launch_from_pull(Vector2(-80, 20))
	dog.shelter.global_position = Vector2(2500, 350)
	game._flight_time = GameRound.MAX_FLIGHT_TIME
	game._physics_process(0.02)
	await _settle()
	_check(game.dogs_left == 0 and game.state == GameRound.RoundState.WON, "Укрытие за границей мира на последнем кадре выстрела даёт победу после поражения цели")
	game.queue_free()
	await _settle()


func _test_editor() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	current_scene = editor
	await _settle()
	editor.new_level()
	editor.canvas.material_id = &"stone"
	await _place(editor, LevelCanvas.Tool.TOWER, Vector2(850, 530))
	_check(editor.draft.block_positions.size() == 3 and editor.draft.block_materials == PackedStringArray(["stone", "stone", "stone"]), "Башня мышью создаёт три блока выбранного материала")
	editor.undo()
	_check(editor.draft.block_positions.is_empty() and editor.draft.block_materials.is_empty(), "Одна отмена удаляет целую башню и её материалы")
	editor.redo()
	_check(editor.draft.block_positions.size() == 3 and editor.draft.block_material_at(1) == &"stone", "Возврат восстанавливает башню с материалом")
	editor.canvas.material_id = &"glass"
	await _place(editor, LevelCanvas.Tool.DOG_HOUSE, Vector2(1130, 590), true)
	_check(editor.draft.dog_positions.size() == 1 and editor.draft.dog_house_material_at(0) == &"glass", "Касание добавляет одну собаку со стеклянной будкой")
	_check(editor.canvas.selected_material() == &"glass" and editor.canvas.selected_size() == DogHouse.SIZE, "Выделение будки показывает её материал и полные размеры")
	var old_position := editor.draft.dog_positions[0]
	var origin := _canvas_point(editor.canvas, old_position)
	_press(origin, true, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _canvas_point(editor.canvas, Vector2(1700, 900))
	root.push_input(drag, true)
	_press(drag.position, false, true)
	var house_rect := Rect2(editor.draft.dog_positions[0] + Vector2(0, -37) - DogHouse.SIZE * 0.5, DogHouse.SIZE)
	_check(Rect2(400, 100, 840, 520).encloses(house_rect), "Перетаскивание ограничивает всю будку областью строительства")
	editor.undo()
	_check(editor.draft.dog_positions[0] == old_position and editor.draft.dog_house_material_at(0) == &"glass", "Отмена переноса восстанавливает будку вместе с собакой")
	_canvas_click(editor.canvas, old_position)
	editor.canvas.set_selected_material(&"metal")
	_check(editor.draft.dog_house_material_at(0) == &"metal", "Материал уже поставленной будки меняется")
	editor.undo()
	_check(editor.draft.dog_house_material_at(0) == &"glass", "Материал будки входит в историю правок")
	_canvas_click(editor.canvas, old_position)
	editor.canvas.delete_selected()
	_check(editor.draft.dog_positions.is_empty() and editor.draft.dog_house_materials.is_empty(), "Удаление будки удаляет цель и соответствующий материал")
	editor.undo()
	_check(editor.draft.dog_positions.size() == 1 and editor.draft.dog_house_material_at(0) == &"glass", "Отмена удаления восстанавливает цель с укрытием")
	_canvas_click(editor.canvas, editor.draft.block_positions[0])
	editor.canvas.set_selected_material(&"wood")
	_check(editor.draft.block_material_at(0) == &"wood" and editor.draft.block_material_at(1) == &"stone", "Смена материала влияет только на выделенный блок")
	editor.undo()
	_check(editor.draft.block_material_at(0) == &"stone", "Материал блока восстанавливается отменой")
	editor.canvas.clear_selection()
	editor.draft.block_positions.resize(198)
	editor.draft.block_sizes.resize(198)
	editor.draft.block_sizes.fill(Vector2(20, 20))
	editor.draft.block_materials.clear()
	editor.draft.normalize_materials()
	var history_size := editor._undo_stack.size()
	await _place(editor, LevelCanvas.Tool.TOWER, Vector2(650, 530))
	_check(editor.draft.block_positions.size() == 198 and editor.draft.block_materials.size() == 198, "Башня целиком отклоняется при нехватке лимита блоков")
	_check(editor._undo_stack.size() == history_size, "Отклонённая башня не создаёт частичную правку истории")
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		var scroll := editor.material_picker.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(editor.material_picker)
		await _settle()
		var viewport_rect := root.get_visible_rect()
		_check(viewport_rect.encloses(editor.material_picker.get_global_rect()) and viewport_rect.encloses(editor.play_button.get_global_rect()) and editor.canvas.size.x >= 300, "Материалы и поле доступны в окне %dx%d" % [viewport_size.x, viewport_size.y])
	root.size = Vector2i(1280, 720)
	editor.queue_free()
	await _settle()


func _dog(arena: Node2D, kind: StringName, position: Vector2) -> DogTarget:
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(kind)
	dog.position = position
	dog.gravity_scale = 0.0
	arena.add_child(dog)
	return dog


func _place(editor: LevelEditor, tool: LevelCanvas.Tool, point: Vector2, touch: bool = false) -> void:
	var scroll := editor.tool_buttons[tool].get_parent().get_parent() as ScrollContainer
	scroll.ensure_control_visible(editor.tool_buttons[tool])
	await _settle()
	var center := editor.tool_buttons[tool].get_global_rect().get_center()
	_press(center, true, touch)
	_press(center, false, touch)
	_canvas_click(editor.canvas, point, touch)


func _canvas_point(canvas: LevelCanvas, point: Vector2) -> Vector2:
	return canvas.global_position + canvas.world_to_local(point)


func _canvas_click(canvas: LevelCanvas, point: Vector2, touch: bool = false) -> void:
	var position := _canvas_point(canvas, point)
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
		push_error("FAIL: " + description)
