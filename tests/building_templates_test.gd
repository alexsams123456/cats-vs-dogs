extends SceneTree
## Готовые фрагменты, подсказки, история и настоящий ввод; профиль изолирован.

const EDITOR := preload("res://scenes/editor/level_editor.tscn")
const MAIN := preload("res://scenes/main.tscn")

var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _music_playbacks: Array[WeakRef] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture = "--capture-buildings" in OS.get_cmdline_user_args()
	_test_geometry()
	await _test_editor()
	await _test_stability()
	await _test_routes()
	var deadline := Time.get_ticks_msec() + 1000
	while not _music_released() and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(_music_released(), "Пробные бои освобождают аудиопотоки")
	print("Building templates checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_geometry() -> void:
	for index in BuildingTemplates.LEVELS.size():
		var source := BuildingTemplates.LEVELS[index]
		_check(source.is_valid(), "Каждый шаблон содержит валидный игровой уровень")
		_check(LevelLayoutReview.inspect(source).is_empty(), "Готовые постройки не имеют геометрических предупреждений")
		for x: float in [400.0, 820.0, 1240.0]:
			var copy := BuildingTemplates.at_position(index, Vector2(x, 200))
			_check(LevelLayoutReview.BUILD_AREA.encloses(BuildingTemplates.bounds_for(copy)), "Постройка целиком в области строительства даже у края")
			_check(BuildingTemplates.bounds_for(copy).end.y == 620.0, "Любое нажатие ставит постройку на землю")
			_check(copy != source and LevelExchange.decode(LevelExchange.encode(copy)) != null, "Шаблоны независимы и поддерживают обмен")
	var level := BuildingTemplates.LEVELS[1].duplicate(true) as LevelDefinition
	level.block_positions[3] -= Vector2(0, 30)
	_check(_has_issue(level, &"unsupported", 1, 3), "Оторванная стойка верхнего этажа отмечена")
	level.block_positions[3] = level.block_positions[4]
	_check(_has_issue(level, &"overlap", 1, 4), "Пересекающиеся стойки отмечены")
	level.block_positions[3] = Vector2(350, 300)
	_check(_has_issue(level, &"outside", 1, 3), "Объект за границей поля отмечен")
	level.block_positions = PackedVector2Array([Vector2(820, 300), Vector2(820, 280)])
	level.block_sizes = PackedVector2Array([Vector2(100, 20), Vector2(100, 20)])
	level.block_materials = PackedStringArray(["wood", "wood"])
	_check(_has_issue(level, &"unsupported", 1, 0) and _has_issue(level, &"unsupported", 1, 1), "Парящая цепочка блоков не становится опорой сама себе")
	level = LevelDefinition.new()
	level.dog_positions.append(Vector2(820, 595))
	level.dog_house_materials.append("stone")
	level.dog_house_types.append("classic")
	_check(_has_issue(level, &"covered", 0, 0), "Тяжёлая конура требует проверки доступности цели")
	level.dog_house_materials[0] = "wood"
	_check(not _has_issue(level, &"covered", 0, 0), "Деревянная конура не считается плотным укрытием")
	level = BuildingTemplates.LEVELS[0].duplicate(true) as LevelDefinition
	level.dog_positions = PackedVector2Array([Vector2(820, 595)])
	level.dog_kinds = PackedStringArray(["scout"])
	level.block_positions = PackedVector2Array([Vector2(750, 575), Vector2(890, 575), Vector2(820, 520)])
	level.block_sizes = PackedVector2Array([Vector2(30, 90), Vector2(30, 90), Vector2(180, 20)])
	level.block_materials.fill("metal")
	_check(_has_issue(level, &"covered", 0, 0), "Три тяжёлые стороны вокруг цели требуют пробы")
	var before := LevelExchange.encode(level)
	LevelLayoutReview.inspect(level)
	_check(LevelExchange.encode(level) == before, "Проверка не меняет уровень, материалы или отметку победы")
	var empty := LevelDefinition.new()
	_check(LevelLayoutReview.inspect(empty).is_empty(), "Незавершённый пустой черновик безопасен для проверки")
	empty.dog_positions = PackedVector2Array([Vector2(800, 580), Vector2(840, 615)])
	_check(not _has_issue(empty, &"overlap", 0, 1), "Проверка учитывает круглые тела собак вместо квадратных рамок")
	empty.dog_positions[1] = Vector2(820, 590)
	_check(_has_issue(empty, &"overlap", 0, 1), "Настоящее пересечение круглых тел отмечается")
	var limited := LevelDefinition.new()
	limited.block_positions.resize(LevelDefinition.MAX_OBJECTS - 2)
	limited.block_sizes.resize(LevelDefinition.MAX_OBJECTS - 2)
	_check(not BuildingTemplates.placement_error(limited, BuildingTemplates.at_position(0, Vector2(820, 420))).is_empty(), "Лимит блоков учитывает все элементы фрагмента")
	limited = LevelDefinition.new()
	limited.weight_positions.resize(LevelDefinition.MAX_OBJECTS)
	_check(not BuildingTemplates.placement_error(limited, BuildingTemplates.at_position(2, Vector2(820, 420))).is_empty(), "Лимит грузов учитывается до начала добавления")


func _has_issue(level: LevelDefinition, code: StringName, kind: int, index: int) -> bool:
	for issue: Dictionary in LevelLayoutReview.inspect(level):
		if issue.code == code and issue.kind == kind and issue.index == index:
			return true
	return false


func _test_editor() -> void:
	var editor := EDITOR.instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	current_scene = editor
	await _settle()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		await _settle()
		var touch := dimensions.x == 960
		editor.new_level()
		await _settle()
		await _click(editor.buildings_button, touch)
		await _settle()
		_check(editor.building_palette.visible, "Мышь/касание открывают готовые постройки")
		_check(editor.building_palette.size.x <= dimensions.x and editor.building_palette.size.y <= dimensions.y, "Палитра помещается в экран")
		await _shot("palette", dimensions.x)
		await _click(editor.building_palette.cards[0], touch)
		await _settle()
		_check(editor.canvas.tool == LevelCanvas.Tool.BUILDING and not editor.building_palette.visible, "Карточка включает размещение")
		_canvas_click(editor.canvas, Vector2(740, 420), touch)
		await _settle()
		_check(editor.draft.dog_positions.size() == 2 and editor.draft.block_positions.size() == 3, "Одно нажатие добавляет всю постройку без дублирования")
		_check(editor.canvas.tool == LevelCanvas.Tool.SELECT and editor._undo_stack.size() == 1, "Размещение возвращает выбор и создаёт одну запись истории")
		var signature := editor._signature(editor.draft)
		editor.undo()
		_check(editor.draft.dog_positions.is_empty() and editor.draft.block_positions.is_empty(), "Одна отмена удаляет всю постройку")
		editor.redo()
		_check(editor._signature(editor.draft) == signature, "Повтор восстанавливает весь фрагмент")
		editor._choose_building(0)
		_canvas_click(editor.canvas, Vector2(740, 300), touch)
		await _settle()
		_check(editor._signature(editor.draft) == signature and editor._undo_stack.size() == 1, "Занятое место отклоняется без частичной правки")
		_check(editor.canvas.tool == LevelCanvas.Tool.BUILDING and not editor._status.text.is_empty(), "После отказа можно выбрать другое место")
		await _click(editor.buildings_button, touch)
		await _settle()
		await _click(editor.building_palette.cards[2], touch)
		await _settle()
		_canvas_click(editor.canvas, Vector2(1080, 420), touch)
		await _settle()
		_check(editor.draft.weight_positions.size() == 1 and editor.draft.dog_positions.size() == 3, "Ловушка помещается рядом с мостом")
		_check(LevelLayoutReview.inspect(editor.draft).is_empty(), "Две готовые постройки не создают предупреждений")
		await _shot("placed", dimensions.x)
		await _click(editor.review_button, touch)
		await _settle()
		_check(editor.review_dialog.visible and not editor.review_dialog.test_button.disabled, "Проверка предлагает пробный бой")
		await _shot("clean", dimensions.x)
		editor.review_dialog.hide()
		editor._begin_edit()
		editor.draft.block_positions[0] -= Vector2(0, 200)
		editor._finish_edit()
		await _click(editor.review_button, touch)
		await _settle()
		_check(not editor.review_dialog.issue_buttons.is_empty(), "Проверка показывает предупреждение о парящем блоке")
		await _shot("review", dimensions.x)
		await _click(editor.review_dialog.issue_buttons[0], touch)
		await _settle()
		_check(not editor.review_dialog.visible and editor.canvas.selected_kind == 1 and editor.canvas.selected_index == 0, "Нажатие предупреждения выбирает нужный блок")
		editor._show_exchange()
		await _settle()
		_check(not editor.exchange_dialog.review_label.text.is_empty() and not editor.exchange_dialog.save_button.disabled, "Обмен показывает предупреждение и остаётся доступен")
		await _shot("exchange", dimensions.x)
		editor.exchange_dialog.hide()
	editor.new_level()
	await _click(editor.buildings_button, true)
	await _settle()
	await _click(editor.building_palette.cards[1], true)
	await _settle()
	_canvas_click(editor.canvas, Vector2(820, 250), true)
	_check(editor.draft.block_positions.size() == 6 and editor.draft.dog_positions.size() == 2, "Карточка двух этажей добавляет нужный шаблон касанием")
	# Лимиты и составы не должны портиться при пакетном размещении.
	editor.new_level()
	editor.draft.dog_positions.resize(LevelDefinition.MAX_OBJECTS)
	editor.draft.dog_positions.fill(Vector2(450, 595))
	editor._choose_building(2)
	var before := editor._signature(editor.draft)
	_canvas_click(editor.canvas, Vector2(1080, 420), false)
	_check(editor._signature(editor.draft) == before and editor._undo_stack.is_empty(), "Лимит собак отклоняет весь фрагмент без истории")
	editor.new_level()
	editor.draft.dog_positions.append(Vector2(450, 595))
	editor.draft.dog_kinds.append("armored")
	editor.draft.cat_sequence = PackedStringArray(["bomb", "classic", "frost", "magnet"])
	editor.draft.biome = "glacier"
	editor.draft.par_shots = 2
	editor._choose_building(0)
	_canvas_click(editor.canvas, Vector2(820, 420), false)
	_check(editor.draft.dog_kinds == PackedStringArray(["armored", "scout", "scout"]) and editor.draft.is_valid(), "Собственный состав собак расширяется синхронно")
	_check(editor.draft.biome == "glacier" and editor.draft.par_shots == 2 and editor.draft.cat_sequence[0] == "bomb", "Постройка сохраняет правила и состав котов текущего двора")
	var crowded := LevelDefinition.new()
	for index in 25:
		crowded.dog_positions.append(Vector2(800, 300))
	editor._replace_draft(crowded, "")
	editor._show_review()
	_check(editor.review_dialog.issue_buttons.size() == LevelReviewDialog.DISPLAY_LIMIT and editor.review_dialog.message.text.contains(str(LevelReviewDialog.DISPLAY_LIMIT)), "Длинная проверка ограничивает карточки и объясняет продолжение")
	editor.review_dialog.hide()
	for locale: String in GameLocalization.SUPPORTED_LOCALES:
		TranslationServer.set_locale(locale)
		editor._show_buildings()
		await _settle()
		_check(editor.building_palette.size.x <= root.size.x and editor.building_palette.size.y <= root.size.y, "Переведённая палитра помещается в узкое окно: " + locale)
		await _shot("palette-" + locale, 960)
		editor.building_palette.hide()
		editor._show_review()
		await _settle()
		_check(editor.review_dialog.size.x <= root.size.x and editor.review_dialog.size.y <= root.size.y, "Переведённая проверка помещается в узкое окно: " + locale)
		await _shot("review-" + locale, 960)
		editor.review_dialog.hide()
	TranslationServer.set_locale("ru")
	editor.queue_free()
	await _settle()
	root.size = Vector2i(1280, 720)


func _test_stability() -> void:
	for level: LevelDefinition in BuildingTemplates.LEVELS:
		var game := MAIN.instantiate() as GameRound
		game.level = level.duplicate(true) as LevelDefinition
		root.add_child(game)
		_music_playbacks.append(weakref(game.background_music.get_stream_playback()))
		var blocks: Array[Dictionary] = []
		for body in game.actors.get_children():
			if body is WoodenBlock:
				blocks.append({"ref": weakref(body), "point": body.position, "hits": body.hits_left})
		for tick in 600:
			await physics_frame
		_check(game.dogs_left == level.dog_positions.size(), "Все цели переживают 10 секунд ожидания: " + level.title)
		for record: Dictionary in blocks:
			var body := (record.ref as WeakRef).get_ref() as WoodenBlock
			_check(is_instance_valid(body) and not body.is_destroyed and body.hits_left == record.hits and body.position.distance_to(record.point) < 8.0, "Готовая опора не разрушается и не сползает до броска: " + level.title)
		for body in game.actors.get_children():
			if body is HangingWeight:
				_check(body.suspended, "Груз ждёт попадания")
		game.queue_free()
		await _settle()


func _canvas_click(canvas: LevelCanvas, point: Vector2, touch: bool) -> void:
	_events(canvas.global_position + canvas.world_to_local(point), touch)


func _test_routes() -> void:
	for index in BuildingTemplates.LEVELS.size():
		root.size = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)][index]
		for attempt in 2:
			var game := MAIN.instantiate() as GameRound
			game.level = BuildingTemplates.LEVELS[index].duplicate(true) as LevelDefinition
			root.add_child(game)
			current_scene = game
			_music_playbacks.append(weakref(game.background_music.get_stream_playback()))
			var results: Array = []
			game.round_completed.connect(func(won: bool, shots_used: int, stars: int) -> void: results.append([won, shots_used, stars]))
			var releases: Array[int] = [0]
			for body in game.actors.get_children():
				if body is HangingWeight:
					body.released.connect(func() -> void: releases[0] += 1)
			for tick in (66 if attempt == 0 else 600):
				await physics_frame
			await _shot("battle-%d-ready" % index, root.size.x)
			var used := 0
			var pull := Vector2(-70, 78 if index == 2 else 31)
			while game.state == GameRound.RoundState.READY:
				_check(_launch(game, pull, index == 2), "Постройка испытывается настоящим броском")
				used += 1
				for tick in 1200:
					await physics_frame
					if game.state != GameRound.RoundState.FLYING:
						break
				if used >= game.level.shots:
					break
			_check(game.state == GameRound.RoundState.WON and results == [[true, used, 0]], "Готовая постройка проходима после короткого и долгого ожидания: " + game.level.title)
			_check(used <= 2, "Для решения шаблона хватает двух обычных котов")
			if index == 2:
				_check(releases[0] == 1, "Бросок в верёвку освобождает груз ловушки")
			await _shot("battle-%d-result" % index, root.size.x)
			game.queue_free()
			await _settle()


func _launch(game: GameRound, pull: Vector2, touch: bool) -> bool:
	if not _capture:
		return game.slingshot.launch_from_pull(pull)
	var transform := game.slingshot.get_global_transform_with_canvas()
	var end := transform * pull
	var before := game.shots_left
	_pointer(transform.origin, true, touch)
	if touch:
		var event := InputEventScreenDrag.new()
		event.index = 0
		event.position = end
		root.push_input(event, true)
	else:
		var event := InputEventMouseMotion.new()
		event.position = end
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(event, true)
	_pointer(end, false, touch)
	return game.shots_left == before - 1


func _pointer(point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _music_released() -> bool:
	for playback in _music_playbacks:
		if playback.get_ref() != null:
			return false
	return true


func _click(button: Button, touch: bool) -> void:
	var scroll: ScrollContainer
	var ancestor := button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			scroll = ancestor
			break
		ancestor = ancestor.get_parent()
	if scroll != null:
		scroll.ensure_control_visible(button)
		await _settle()
	var point := button.get_global_rect().get_center()
	if button.get_window() != root:
		point += Vector2(button.get_window().position)
	_events(point, touch)


func _events(point: Vector2, touch: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = point
			event.index = 0
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			root.push_input(event, true)


func _settle() -> void:
	for frame in 8:
		await process_frame


func _shot(stage: String, width: int) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.artifacts/buildings-%d-%s.png" % [width, stage]) == OK, "Снимок редактора: " + stage)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
