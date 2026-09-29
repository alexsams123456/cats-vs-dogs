extends SceneTree
## Эффект поражения отделён от тела, счётчика целей и защитных механик.

const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")
const GAME_SCENE := preload("res://scenes/main.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kind: StringName in [&"scout", &"armored", &"jumper"]:
		await _test_variant(kind)
	await _test_shelter()
	await _test_round()
	# Аудиосервер завершает освобождение потоков удалённого раунда асинхронно.
	await create_timer(0.3).timeout
	print("Dog defeat checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_variant(kind: StringName) -> void:
	var world := Node2D.new()
	world.position = Vector2(45, 30)
	root.add_child(world)
	var dog := _spawn_dog(world, kind)
	dog.rotation = 0.34
	var origin := dog.global_position
	var defeated_count: Array[int] = [0]
	dog.defeated.connect(func() -> void: defeated_count[0] += 1)
	dog.receive_hit(dog.impact_threshold - 1.0)
	await _settle()
	_check(_effects(world).is_empty() and not dog.is_destroyed, "Слабое попадание не запускает исчезновение: " + kind)
	if kind == &"armored":
		dog.receive_hit(900.0)
		await _settle()
		_check(not dog.shield_active and not dog.is_destroyed and defeated_count[0] == 0, "Щит принимает первый удар без поражения")
		_check(_effects(world).is_empty(), "Потеря щита не создаёт эффект смерти")
		await create_timer(dog.hit_cooldown_seconds + 0.03).timeout
	if kind == &"jumper":
		dog.apply_frost(2.4)
	dog.receive_hit(900.0)
	dog.receive_hit(900.0)
	dog.destroy()
	_check(dog.is_destroyed, "Урон отмечает поражение немедленно: " + kind)
	await _settle()
	var effects := _effects(world)
	_check(not is_instance_valid(dog) and defeated_count[0] == 1, "Физическое тело удалено, сигнал поражения один: " + kind)
	_check(effects.size() == 1, "Повторные попадания дают один эффект: " + kind)
	if effects.size() == 1:
		var effect := effects[0]
		_check(effect.definition == CharacterCatalog.find_dog(kind), "Эффект сохраняет рисунок породы: " + kind)
		_check(effect.global_position.is_equal_approx(origin) and is_equal_approx(effect.initial_rotation, 0.34), "Эффект начинается в позе поражённой собаки: " + kind)
		_check(effect.find_children("*", "CollisionObject2D").is_empty() and not effect.is_in_group(&"targets"), "У эффекта нет коллизий и статуса цели: " + kind)
		if kind == &"scout":
			var before_pause := effect.elapsed
			paused = true
			await create_timer(0.18, true).timeout
			_check(is_equal_approx(effect.elapsed, before_pause), "Пауза замораживает эффект")
			paused = false
			await create_timer(0.08).timeout
			_check(effect.elapsed > before_pause, "Продолжение возобновляет эффект")
		await create_timer(HeroHitEcho.LIFETIME + 0.05).timeout
		_check(_effects(world).is_empty(), "Эффект самостоятельно освобождается: " + kind)
	world.queue_free()
	await _settle()


func _test_shelter() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.position = Vector2(700, 530)
	house.freeze = true
	world.add_child(house)
	var dog := _spawn_dog(world, &"scout")
	dog.enter_shelter(house)
	dog.receive_hit(2000.0)
	await _settle()
	_check(not dog.is_destroyed and _effects(world).is_empty(), "Удар по защищённой собаке не показывает её поражение")
	house.destroy()
	await _settle()
	_check(is_instance_valid(dog) and not dog.is_sheltered() and _effects(world).is_empty(), "Разрушение конуры освобождает собаку без ложной смерти")
	dog.receive_hit(900.0)
	await _settle()
	_check(not is_instance_valid(dog) and _effects(world).size() == 1, "Открытая собака получает эффект после следующего удара")
	var effect_ref: WeakRef = weakref(_effects(world)[0]) if not _effects(world).is_empty() else null
	world.queue_free()
	await _settle()
	_check(effect_ref == null or effect_ref.get_ref() == null, "Закрытие сцены очищает незавершённый эффект")


func _test_round() -> void:
	var level := LevelDefinition.new()
	level.dog_positions = PackedVector2Array([Vector2(860, 595), Vector2(1070, 595)])
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = level
	root.add_child(game)
	await _settle()
	var dogs: Array[DogTarget] = []
	for actor in game.actors.get_children():
		if actor is DogTarget:
			dogs.append(actor)
	dogs[0].destroy()
	dogs[0].destroy()
	await _settle()
	_check(game.dogs_left == 1 and game.state == GameRound.RoundState.READY, "Прямое уничтожение уменьшает счётчик один раз")
	_check(_effects(game.actors).size() == 1, "Прямое уничтожение использует тот же эффект, что и попадание")
	dogs[1].receive_hit(900.0)
	await _settle()
	_check(game.dogs_left == 0 and game.state == GameRound.RoundState.WON, "Последняя цель даёт победу до завершения анимации")
	_check(_effects(game.actors).size() == 2, "Два поражения сохраняют независимые эффекты после победы")
	_check(get_nodes_in_group(&"targets").is_empty(), "Визуальные остатки не сохраняют физических целей")
	await create_timer(HeroHitEcho.LIFETIME + 0.05).timeout
	_check(_effects(game.actors).is_empty() and game.state == GameRound.RoundState.WON, "После эффектов победа остаётся окончательной")
	game.queue_free()
	await _settle()


func _spawn_dog(world: Node2D, kind: StringName) -> DogTarget:
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(kind)
	dog.position = Vector2(300, 300)
	dog.freeze = true
	world.add_child(dog)
	return dog


func _effects(world: Node) -> Array[HeroHitEcho]:
	var result: Array[HeroHitEcho] = []
	for child in world.get_children():
		if child is HeroHitEcho:
			result.append(child)
	return result


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
