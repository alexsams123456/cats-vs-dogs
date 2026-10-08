extends SceneTree
## Mixed rosters, contextual lessons and scoring exercise real round scenes.

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_validation()
	await _test_authored_campaign()
	await _test_sequence_and_result()
	await _test_aim_lesson()
	await _test_shelter_lesson()
	await _test_loss_and_legacy()
	await _test_final_shot_settles()
	# Let the audio driver release playback after the final launched cat is freed.
	await create_timer(0.2).timeout
	print("Round campaign checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_validation() -> void:
	var level := _level()
	_check(level.is_valid(), "Complete mixed rosters and scoring are valid")
	for roster in [PackedStringArray(["classic"]), PackedStringArray(["classic", "missing", "bomb"]), PackedStringArray(["classic", "", "bomb"]), PackedStringArray(["classic", "scout", "bomb"])]:
		var invalid := level.duplicate(true) as LevelDefinition
		invalid.cat_sequence = roster
		_check(not invalid.is_valid(), "Cat sequence rejects wrong count, unknown, empty or dog IDs")
	for roster in [PackedStringArray(["scout"]), PackedStringArray(["scout", "missing"]), PackedStringArray(["scout", ""]), PackedStringArray(["scout", "classic"])]:
		var invalid := level.duplicate(true) as LevelDefinition
		invalid.dog_kinds = roster
		_check(not invalid.is_valid(), "Dog sequence rejects wrong count, unknown, empty or cat IDs")
	for lesson in [&"", &"aim", &"ability", &"shelter"]:
		level.tutorial = lesson
		_check(level.is_valid(), "Known lesson is valid: %s" % lesson)
	level.tutorial = &"unknown"
	_check(not level.is_valid(), "Unknown lesson rejected")
	level.tutorial = &""
	for par in [-1, 4]:
		level.par_shots = par
		_check(not level.is_valid(), "Scoring limits stay within available shots")
	level.par_shots = 1
	_check(level.stars_for_shots(1) == 3 and level.stars_for_shots(2) == 2 and level.stars_for_shots(3) == 1, "Three score thresholds reward shot economy")
	level.cat_sequence = PackedStringArray()
	level.dog_kinds = PackedStringArray()
	level.par_shots = 0
	_check(level.is_valid() and level.stars_for_shots(1) == 0, "Legacy levels remain valid without scoring or authored rosters")


func _test_authored_campaign() -> void:
	for level in CampaignCatalog.LEVELS:
		_check(level.is_valid() and level.shots >= 2 and level.cat_sequence.size() == level.shots, level.title + ": several authored cats fill every shot")
		_check(level.dog_positions.size() >= 2 and level.dog_kinds.size() == level.dog_positions.size(), level.title + ": several authored dogs fill every target")
		var game := _round(level)
		await _transition()
		_check(game.slingshot.loaded_projectile.definition.id == StringName(level.cat_sequence[0]), level.title + ": campaign starts with its own cat")
		var dogs := get_nodes_in_group("targets")
		_check(dogs.size() == level.dog_kinds.size(), level.title + ": every authored target is present")
		for index in dogs.size():
			_check(dogs[index].definition.id == StringName(level.dog_kinds[index]), level.title + ": target kind follows the level")
		await _remove(game)


func _test_sequence_and_result() -> void:
	var definition := _level()
	definition.tutorial = &"ability"
	var game := _round(definition)
	var results: Array = []
	var next_events: Array = []
	game.round_completed.connect(func(won: bool, shots: int, stars: int) -> void: results.append([won, shots, stars]))
	game.next_requested.connect(func() -> void: next_events.append(true))
	await _transition()
	_check(game.slingshot.loaded_projectile.definition.id == &"magnet", "First authored cat overrides menu selection")
	_check(_reserve_kinds(game) == PackedStringArray(["bomb", "classic"]), "Visible reserve keeps the authored order after the loaded cat")
	_check(game.hud._queue_label.text.contains("Магнит → Искра → Рыжик") and not game.hud._queue_label.is_visible_in_tree(), "HUD retains the ordered squad in folded pause details")
	var dogs := get_nodes_in_group("targets")
	_check(dogs[0].definition.id == &"scout" and dogs[1].definition.id == &"armored", "Distinct dog kinds share one yard")
	_check(game.hud._hint.text.begins_with("Шаг 1/2"), "Ability lesson first asks for a shot")
	game.use_ability()
	_check(not game._tutorial_ability_used, "Ability lesson does not advance before a real activation")
	game.hud.next_requested.emit()
	_check(next_events.is_empty(), "Next level cannot be requested before victory")
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_touch(anchor, true)
	_touch(anchor + Vector2(85, 10), false)
	_check(game.shots_left == 2 and game.hud._hint.text.begins_with("Шаг 2/2"), "Touch launches once and advances the ability lesson")
	_check(game.hud._queue_label.text == "Далее: Искра → Рыжик", "Flying cat is excluded from remaining queue")
	_check(_reserve_kinds(game) == PackedStringArray(["bomb", "classic"]), "Launching keeps all unspent cats visible in reserve")
	game.set_paused(true)
	game.use_ability()
	_check(not game._tutorial_ability_used, "Pause cannot complete the ability lesson")
	game.set_paused(false)
	game.use_ability()
	_check(game._tutorial_ability_used and game.hud._hint.text.begins_with("Приём сработал"), "Real ability signal completes the lesson")
	# Resolve a miss directly: physics settling itself is covered by the smoke suite.
	game._finish_shot()
	game._finish_shot()
	_check(game.shots_left == 2 and game.slingshot.loaded_projectile.definition.id == &"bomb", "One resolved miss loads exactly the second cat")
	_check(_reserve_kinds(game) == PackedStringArray(["classic"]), "Loading the next cat removes exactly that cat from the visible reserve")
	_check(game.hud._current_name.text.contains("Искра") and game.hud._ability_state == GameHUD.AbilityState.BEFORE_LAUNCH and game.hud._ability_button.text.contains("Взорвать"), "HUD changes the current cat, launch guidance and action together")
	game.slingshot.launch_from_pull(Vector2(85, 10))
	for dog in get_nodes_in_group("targets"):
		dog.destroy()
		dog.destroy()
	await _transition()
	_check(results == [[true, 2, 2]], "Victory emits exactly one scored result with actual shots spent")
	_check(game.hud._next_button.visible and game.hud._overlay_menu_button.text == "В главное меню", "Campaign victory exposes next level and main menu")
	_check(game.hud._result_detail.text.contains("★★☆") and game.hud._result_detail.text.contains("≤ 1"), "Result displays earned stars and explicit thresholds")
	game.hud._next_button.pressed.emit()
	_check(next_events.size() == 1, "Next button forwards one request after victory")
	await _remove(game)
	game = _round(definition)
	_check(game.slingshot.loaded_projectile.definition.id == &"magnet" and game.shots_left == 3, "A fresh attempt restores the original authored sequence")
	_check(not game._tutorial_ability_used and definition.cat_sequence[0] == "magnet", "Restart restores lesson without mutating the level resource")
	await _remove(game)


func _test_aim_lesson() -> void:
	var definition := _level()
	definition.tutorial = &"aim"
	var game := _round(definition)
	await _transition()
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_mouse(anchor, true)
	await physics_frame
	await process_frame
	_check(game.hud._hint.text.begins_with("Шаг 2/2"), "A real mouse grab advances aiming guidance")
	_mouse(anchor + Vector2(1, 0), false)
	await physics_frame
	await process_frame
	_check(game.shots_left == 3 and game.hud._hint.text.begins_with("Шаг 1/2"), "Tiny canceled drag returns to grab guidance without spending a shot")
	_mouse(anchor, true)
	_mouse(anchor + Vector2(85, 10), false)
	_check(game.hud._hint.text.begins_with("Выстрел получился"), "Release completes aiming lesson only after actual launch")
	await _remove(game)


func _test_shelter_lesson() -> void:
	var definition := _level()
	definition.tutorial = &"shelter"
	definition.dog_house_materials = PackedStringArray(["wood", ""])
	definition.dog_positions[0] = Vector2(900, 595)
	var game := _round(definition)
	await _transition()
	_check(game.hud._hint.text.begins_with("Шаг 1/2"), "Shelter lesson starts with destruction task")
	var house: DogHouse
	for actor in game.actors.get_children():
		if actor is DogHouse:
			house = actor
	_check(house != null, "Lesson yard creates the physical shelter")
	house.receive_hit(10000.0)
	await _transition()
	_check(game.dogs_left == 2 and game._tutorial_shelter_opened, "Destruction signal advances lesson while sheltered dog survives")
	_check(game.hud._hint.text.begins_with("Шаг 2/2"), "Released dog prompts the next concrete action")
	await _remove(game)


func _test_loss_and_legacy() -> void:
	var definition := _level()
	definition.shots = 1
	definition.cat_sequence = PackedStringArray()
	definition.dog_kinds = PackedStringArray()
	var game := _round(definition)
	var results: Array = []
	game.round_completed.connect(func(won: bool, shots: int, stars: int) -> void: results.append([won, shots, stars]))
	_check(game.slingshot.loaded_projectile.definition.id == &"homing", "Empty sequence uses menu cat selection")
	for dog in get_nodes_in_group("targets"):
		_check(dog.definition.id == &"jumper", "Empty dog roster uses menu dog selection")
	game.slingshot.launch_from_pull(Vector2(85, 10))
	game._finish_shot()
	game._finish_shot()
	_check(results == [[false, 1, 0]], "Loss emits once and awards zero stars")
	_check(not game.hud._next_button.visible, "Loss hides next-level action")
	for dog in get_nodes_in_group("targets"):
		dog.destroy()
	await _transition()
	_check(results.size() == 1 and game.state == GameRound.RoundState.LOST, "Late dog destruction cannot award a victory")
	_check(game.hud._hint.text.is_empty(), "Finished lesson stays hidden on later physics frames")
	await _remove(game)


func _test_final_shot_settles() -> void:
	var definition := LevelDefinition.new()
	definition.shots = 1
	definition.dog_positions = PackedVector2Array([Vector2(900, 595)])
	definition.cat_sequence = PackedStringArray(["classic"])
	definition.dog_kinds = PackedStringArray(["scout"])
	var game := _round(definition)
	await create_timer(0.9).timeout
	game.slingshot.launch_from_pull(Vector2(-82, 36))
	# Advance only the round timer to its boundary; the projectile still follows
	# a real trajectory and must be allowed to make its physical impact.
	game._flight_time = GameRound.MAX_FLIGHT_TIME - 0.1
	await create_timer(0.25).timeout
	_check(game.state == GameRound.RoundState.FLYING and game.shots_left == 0, "The last moving projectile is not cut off by the next-cat timeout")
	await create_timer(1.2 / Slingshot.FLIGHT_SPEED_SCALE).timeout
	_check(game.state == GameRound.RoundState.WON, "A real impact after the timer boundary still wins the final shot")
	await _remove(game)
	definition.dog_positions = PackedVector2Array([Vector2(1100, 595)])
	game = _round(definition)
	await create_timer(0.9).timeout
	game.slingshot.launch_from_pull(Vector2(80, 15))
	for tick in 900:
		if game.state != GameRound.RoundState.FLYING:
			break
		await physics_frame
	_check(game.state == GameRound.RoundState.LOST, "A missed final shot still ends when the yard settles")
	await _remove(game)


func _level() -> LevelDefinition:
	var level := LevelDefinition.new()
	level.title = "Проверка отряда"
	level.shots = 3
	level.par_shots = 1
	level.cat_sequence = PackedStringArray(["magnet", "bomb", "classic"])
	level.dog_kinds = PackedStringArray(["scout", "armored"])
	level.dog_positions = PackedVector2Array([Vector2(1050, 595), Vector2(1190, 595)])
	return level


func _reserve_kinds(game: GameRound) -> PackedStringArray:
	var kinds := PackedStringArray()
	for cat in game.cat_queue.cats:
		kinds.append(String(cat.id))
	return kinds


func _round(level: LevelDefinition) -> GameRound:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = level
	game.cat_definition = CharacterCatalog.find_cat(&"homing")
	game.dog_definition = CharacterCatalog.find_dog(&"jumper")
	game.campaign_mode = true
	game.has_next_level = true
	root.add_child(game)
	current_scene = game
	return game


func _remove(game: GameRound) -> void:
	game.queue_free()
	await _transition()


func _transition() -> void:
	await process_frame
	await process_frame


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 11
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
