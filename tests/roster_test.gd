extends SceneTree
## Menu integration and physical behavior of each special character.

const APP_SCENE := preload("res://scenes/app.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const BLOCK_SCENE := preload("res://scenes/actors/wooden_block.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_menu()
	await _test_bomb()
	await _test_shield()
	await _test_zigzag()
	await _test_jumper()
	print("Roster checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_menu() -> void:
	var app := APP_SCENE.instantiate() as GameApp
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	await create_timer(0.4).timeout
	_check(is_instance_valid(app.campaign) and app.menu == null and app.game == null, "App starts in campaign without requiring hero choices")
	app.show_sandbox()
	await _transition()
	_check(is_instance_valid(app.menu) and app.campaign == null, "Sandbox explicitly opens the hero roster")
	_check(CharacterCatalog.CATS.size() == 10 and app.menu.page_count == 4, "Ten cats are available across four menu pages")
	_check(app.menu.card_buttons.size() == 3 and app.menu.previous_page_button.disabled, "First page shows three cat cards and disables backward navigation")
	var ids: Array[StringName] = []
	for page in app.menu.page_count:
		app.menu.show_page(page)
		await _transition()
		for button: Button in app.menu.card_buttons:
			var id := StringName(button.get_meta("character_id"))
			_check(not ids.has(id) and CharacterCatalog.find_cat(id).id == id, "Menu exposes a distinct catalog cat: %s" % id)
			ids.append(id)
	_check(ids.size() == 10 and app.menu.card_buttons.size() == 1 and app.menu.next_page_button.disabled, "Last page contains the tenth cat and disables forward navigation")
	_click(app.menu.card_buttons[0], true)
	_check(app.menu.selected_cat_id == &"homing", "Touch can select the tenth cat")
	_click(app.menu.previous_page_button, false)
	await _transition()
	_check(app.menu.current_page == 2 and app.menu.selected_cat_id == &"homing", "Mouse page navigation preserves the chosen cat")
	_click(app.menu.next_page_button, true)
	await _transition()
	_check(app.menu.current_page == 3, "Touch navigates to the last cat page")
	app.menu.show_species(&"dog")
	_check(app.menu.page_count == 1, "Dog roster remains on a single page")
	app.menu.show_species(&"cat")
	_check(app.menu.current_page == 3 and app.menu.card_buttons[0].button_pressed, "Returning to cats reveals the selected tenth cat")
	app.menu.show_page(0)
	await _transition()
	_click(app.menu.card_buttons[1], false)
	_check(app.menu.selected_cat_id == &"bomb", "Mouse selects bomb cat")
	_click(app.menu.species_buttons[&"dog"], true)
	await process_frame
	await process_frame
	_click(app.menu.card_buttons[1], true)
	_check(app.menu.selected_dog_id == &"armored", "Touch selects shield dog")
	_click(app.menu.play_button, true)
	await _transition()
	_check(app.menu == null and is_instance_valid(app.game), "Play enters a round")
	_check(app.game.slingshot.loaded_projectile.definition.id == &"bomb", "Chosen cat appears in sling")
	for dog in get_nodes_in_group("targets"):
		_check(dog.definition.id == &"armored", "Chosen dog appears in level")
	_check(not app.game.slingshot.loaded_projectile.can_activate_ability(), "Loaded cat cannot explode")
	app.game.slingshot.launch_from_pull(Vector2(80, 20))
	_check(not app.game.hud._ability_button.disabled, "Bomb button enabled after launch")
	app.game.set_paused(true)
	app.game.use_ability()
	_check(not app.game.hud._ability_button.disabled, "Pause prevents spending the bomb ability")
	app.game.set_paused(false)
	_click(app.game.hud._ability_button, true)
	_check(app.game.hud._ability_button.disabled, "Touch activates bomb exactly once")
	await process_frame
	app.game.restart()
	await _transition()
	_check(app.game.shots_left == 4 and app.game.cat_definition.id == &"bomb", "Restart preserves roster and restores shots")
	var departing_cat: CatProjectile = app.game.slingshot.loaded_projectile
	app.game.slingshot.launch_from_pull(Vector2(80, 20))
	departing_cat.freeze = true
	departing_cat.position = Vector2(-450, 200)
	await create_timer(0.1).timeout
	_check(not is_instance_valid(departing_cat) and app.game.hud._ability_button.disabled, "Out-of-bounds bomb immediately disables its button")
	app.game.set_paused(true)
	app.game.return_to_menu()
	await _transition()
	_check(not paused and is_instance_valid(app.menu) and app.campaign == null, "Returning from a paused sandbox round opens its hero roster")
	_check(app.menu.selected_cat_id == &"bomb" and app.menu.selected_dog_id == &"armored", "Menu remembers both choices")
	app.menu.show_species(&"cat")
	app.menu.select_character(&"zigzag")
	app.menu.show_species(&"dog")
	app.menu.select_character(&"jumper")
	app.menu.play_button.pressed.emit()
	await _transition()
	_check(app.game.cat_definition.id == &"zigzag" and app.game.dog_definition.id == &"jumper", "New choices replace previous roster")
	app.queue_free()
	await _transition()


func _test_bomb() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var near_dog := _dog(arena, &"scout", Vector2(480, 300))
	var far_dog := _dog(arena, &"scout", Vector2(800, 300))
	var block := BLOCK_SCENE.instantiate() as WoodenBlock
	block.position = Vector2(320, 300)
	block.gravity_scale = 0.0
	arena.add_child(block)
	var bomb := _cat(arena, &"bomb", Vector2(400, 300))
	_check(not bomb.activate_ability(), "Bomb rejects activation before launch")
	bomb.launch(Vector2.ZERO)
	_check(bomb.activate_ability(), "Bomb activates in flight")
	_check(not bomb.activate_ability(), "Bomb cannot activate twice")
	await create_timer(0.1).timeout
	_check(not is_instance_valid(near_dog), "Explosion defeats a nearby dog")
	_check(not is_instance_valid(block), "Explosion destroys a nearby block")
	_check(is_instance_valid(far_dog), "Explosion has a limited radius")
	_check(not is_instance_valid(bomb), "Exploded cat is removed")
	# A collision must trigger the same effect without pressing the ability button.
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(400, 500)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(200, 20)
	shape.shape = rectangle
	floor_body.add_child(shape)
	arena.add_child(floor_body)
	var impact_bomb := _cat(arena, &"bomb", Vector2(400, 420))
	impact_bomb.launch(Vector2(0, 250))
	await create_timer(0.4).timeout
	_check(not is_instance_valid(impact_bomb), "Bomb explodes automatically on impact")
	arena.queue_free()
	await _transition()


func _test_shield() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var dog := _dog(arena, &"armored", Vector2(500, 300))
	dog.receive_hit(700.0)
	await process_frame
	_check(is_instance_valid(dog) and not dog.is_destroyed, "Shield absorbs first strong hit")
	dog.receive_hit(700.0)
	_check(not dog.is_destroyed, "One contact cannot consume shield and dog together")
	await create_timer(0.35).timeout
	dog.receive_hit(700.0)
	await _transition()
	_check(not is_instance_valid(dog), "Second separated hit defeats unshielded dog")
	arena.queue_free()
	await _transition()


func _test_zigzag() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var origin := Vector2(100, 100)
	var velocity := Vector2(850, -300)
	var normal := velocity.normalized().orthogonal()
	var classic := _cat(arena, &"classic", origin)
	var zigzag := _cat(arena, &"zigzag", origin)
	for cat: CatProjectile in [classic, zigzag]:
		cat.gravity_scale = 1.0
		cat.collision_layer = 0
		cat.collision_mask = 0
		cat.launch(velocity)
	var minimum_offset := 0.0
	var maximum_offset := 0.0
	var maximum_prediction_error := 0.0
	var previous_direction := 0.0
	var reversals := 0
	var pause_checked := false
	while zigzag._flight_age < zigzag.wave_duration + 0.25:
		await physics_frame
		var displacement := zigzag.position - classic.position
		var sideways := displacement.dot(normal)
		minimum_offset = minf(minimum_offset, sideways)
		maximum_offset = maxf(maximum_offset, sideways)
		# The ordinary cat supplies elapsed flight time, excluding paused frames.
		var elapsed := (classic.position.x - origin.x) / velocity.x
		maximum_prediction_error = maxf(maximum_prediction_error, displacement.distance_to(zigzag.trajectory_offset(elapsed, velocity)))
		var sideways_speed := (zigzag.linear_velocity - classic.linear_velocity).dot(normal)
		if absf(sideways_speed) > 20.0:
			var direction := signf(sideways_speed)
			if previous_direction != 0.0 and direction != previous_direction:
				reversals += 1
			previous_direction = direction
		if not pause_checked and zigzag._flight_age >= 0.4:
			paused = true
			await process_frame
			var paused_position := zigzag.position
			var paused_age := zigzag._flight_age
			await create_timer(0.12).timeout
			_check(zigzag.position == paused_position and zigzag._flight_age == paused_age, "Pause stops the zigzag trajectory and wave duration")
			paused = false
			pause_checked = true
	_check(minimum_offset < -25.0 and maximum_offset > 25.0, "Zigzag moves visibly to both sides of the ballistic trajectory")
	_check(maximum_offset - minimum_offset > 100.0 and reversals >= 3, "Zigzag spans more than two cat diameters and reverses several times")
	_check(maximum_prediction_error < CatProjectile.RADIUS, "Zigzag aiming prediction stays within one cat radius of its physical path")
	_check(absf(classic.linear_velocity.x - velocity.x) < 1.0, "Classic keeps its unmodified ballistic trajectory")
	_check(not zigzag.can_activate_ability(), "Automatic zigzag needs no extra button")
	var velocity_after_wave := zigzag.linear_velocity - classic.linear_velocity
	await create_timer(0.2).timeout
	_check((zigzag.linear_velocity - classic.linear_velocity).distance_to(velocity_after_wave) < 1.0, "Wave force ends after its bounded duration")
	arena.queue_free()
	await _transition()


func _test_jumper() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(500, 625)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(500, 10)
	collision.shape = shape
	floor_body.add_child(collision)
	arena.add_child(floor_body)
	var dog := _dog(arena, &"jumper", Vector2(500, 590))
	dog.gravity_scale = 1.0
	await create_timer(1.0).timeout
	_check(absf(dog.position.y - 595.0) < 8.0, "Jumper waits on the ground before a shot")
	var cat := _cat(arena, &"classic", Vector2(280, 570))
	cat.launch(Vector2(280, 0))
	var playback_reference: WeakRef = weakref((cat.get_node("Voice") as CatVoice).get_stream_playback())
	await create_timer(0.15).timeout
	_check(is_instance_valid(dog) and dog.linear_velocity.y < -80.0, "Approaching cat makes jumper evade upwards")
	arena.queue_free()
	await _transition()
	# Stopping playback fades it out on the audio thread; headless frames can finish first.
	await create_timer(0.1).timeout
	_check(playback_reference.get_ref() == null, "Freed cat releases playback after the audio mixer drains")


func _cat(parent: Node, id: StringName, position: Vector2) -> CatProjectile:
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.find_cat(id)
	cat.position = position
	cat.gravity_scale = 0.0
	parent.add_child(cat)
	return cat


func _dog(parent: Node, id: StringName, position: Vector2) -> DogTarget:
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(id)
	dog.position = position
	dog.gravity_scale = 0.0
	parent.add_child(dog)
	return dog


func _transition() -> void:
	await process_frame
	await process_frame
	await process_frame


func _click(button: Button, touch: bool) -> void:
	var center := button.get_global_rect().get_center()
	for pressed in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = center
			event.index = 0
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = center
			event.pressed = pressed
			root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
