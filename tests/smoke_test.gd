extends SceneTree
## Integration checks run against real scenes and the physics engine, without addons.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	current_scene = game
	await create_timer(1.1).timeout
	_check(game.dogs_left == 2, "Targets survive initial settling")
	_check(get_nodes_in_group("blocks").size() == 4, "Tower and dog house survive initial settling")
	_check(game.shots_left == 4 and game.state == game.RoundState.READY, "Level starts ready")
	_check(not game.slingshot.launch_from_pull(Vector2(2, 1)), "Tiny drag cancels")
	_check(game.shots_left == 4, "Canceled drag costs no shot")
	var anchor: Vector2 = game.slingshot.get_global_transform_with_canvas().origin
	_touch(anchor, 7, true)
	_check(game.slingshot.is_dragging, "Touch starts aiming")
	_touch(anchor + Vector2(-80, 40), 8, false)
	_check(game.slingshot.is_dragging and game.shots_left == 4, "Second finger cannot release a shot")
	_touch(anchor, 7, false, true)
	_check(not game.slingshot.is_dragging and game.shots_left == 4, "Canceled touch returns cat")
	var pause_center: Vector2 = game.hud._pause_button.get_global_rect().get_center()
	_touch(pause_center, 0, true)
	_touch(pause_center, 0, false)
	_check(paused, "Touch can press the pause button without mouse emulation")
	game.set_paused(false)
	_check(not paused, "Resume restarts the tree")
	_mouse(anchor, true)
	_check(game.slingshot.is_dragging, "Mouse starts aiming")
	_mouse(anchor + Vector2(90, 20), false)
	_check(game.shots_left == 3 and game.state == game.RoundState.FLYING, "Mouse releases exactly one shot")
	var cat = get_nodes_in_group("projectiles")[0]
	var start_position: Vector2 = cat.position
	await create_timer(0.2).timeout
	_check(cat.position.x < start_position.x - 40.0, "Released cat moves through physics")
	await _wait_for_ready(game)
	_check(game.state == game.RoundState.READY and game.shots_left == 3, "Next cat loads after a miss")
	# Exercise a real impact independently of trajectory balance.
	var target = get_nodes_in_group("targets")[1]
	target.position = Vector2(600, 595)
	var impact_cat := CAT_SCENE.instantiate() as CatProjectile
	impact_cat.position = target.position + Vector2(110, 0)
	impact_cat.gravity_scale = 0.0
	game.actors.add_child(impact_cat)
	impact_cat.launch(Vector2(-900, 0))
	await create_timer(0.4).timeout
	_check(game.dogs_left < 2, "Fast physical impact defeats a dog")
	for dog in get_nodes_in_group("targets"):
		dog.destroy()
		dog.destroy()
	await process_frame
	await process_frame
	_check(game.dogs_left == 0 and game.state == game.RoundState.WON, "Last target triggers victory once")
	_check(not game.slingshot.launch_from_pull(Vector2(-80, 40)), "Victory prevents further shots")
	var restart_key := InputEventKey.new()
	restart_key.physical_keycode = KEY_R
	restart_key.pressed = true
	root.push_input(restart_key, true)
	await process_frame
	await process_frame
	game = current_scene
	_check(game.shots_left == 4 and game.dogs_left == 2, "Restart restores a clean level")
	anchor = game.slingshot.get_global_transform_with_canvas().origin
	_touch(anchor, 1, true)
	_touch(anchor + Vector2(100, 0), 1, false)
	_check(game.shots_left == 3 and game.state == game.RoundState.FLYING, "Touch release launches exactly one cat")
	await _wait_for_ready(game)
	# Spend every shot on misses and wait for the real turn lifecycle.
	for index in 3:
		_check(game.slingshot.launch_from_pull(Vector2(100, 0)), "Miss %d launches" % (index + 1))
		await _wait_for_ready(game)
	_check(game.state == game.RoundState.LOST and game.shots_left == 0, "Final miss triggers defeat after settling")
	_check(not game.slingshot.launch_from_pull(Vector2(-100, 0)), "Defeat prevents further shots")
	for dog in get_nodes_in_group("targets"):
		dog.destroy()
	await process_frame
	await process_frame
	_check(game.state == game.RoundState.LOST, "Late destruction cannot change a finished result")
	_check(game.hud._hint.text.is_empty(), "Finished round hides aiming instructions")
	print("Smoke checks: %d passed, %d failed" % [_checks - _failures, _failures])
	game.queue_free()
	await process_frame
	# Аудиопоток освобождается потоком микшера после удаления раунда.
	await create_timer(0.3).timeout
	quit(1 if _failures else 0)


func _wait_for_ready(game: Node) -> void:
	var elapsed := 0.0
	while game.state == game.RoundState.FLYING and elapsed < 11.5:
		await create_timer(0.1).timeout
		elapsed += 0.1
	_check(game.state != game.RoundState.FLYING, "Shot always resolves within its timeout")


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _touch(position: Vector2, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
