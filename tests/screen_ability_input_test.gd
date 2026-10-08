extends SceneTree
## Viewport presses activate flight abilities; GUI and launch gestures keep ownership.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const ACTIVE_IDS: Array[StringName] = [
	&"classic", &"bomb", &"splitter", &"heavy", &"wind", &"magnet", &"frost", &"ghost", &"homing",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"SFX"), true)
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = viewport_size
		for touch: bool in [false, true]:
			for id: StringName in ACTIVE_IDS:
				await _test_press(id, touch)
		await _test_unavailable()
	print("Screen ability input checks: %d passed, %d failed" % [_checks - _failures, _failures])
	await create_timer(0.3).timeout
	quit(1 if _failures else 0)


func _new_game(id: StringName) -> GameRound:
	var game := MAIN_SCENE.instantiate() as GameRound
	game.level = LevelDefinition.new()
	game.level.shots = 2
	game.level.cat_sequence = PackedStringArray([String(id), "classic"])
	game.level.dog_positions = PackedVector2Array([Vector2(1120, 550)])
	game.level.block_positions = PackedVector2Array()
	game.level.block_sizes = PackedVector2Array()
	game.level.tutorial = &"ability"
	root.add_child(game)
	for frame in 4:
		await process_frame
	return game


func _test_press(id: StringName, touch: bool) -> void:
	var game := await _new_game(id)
	var cat := game.slingshot.loaded_projectile
	var emissions: Array[int] = [0]
	cat.ability_used.connect(func() -> void: emissions[0] += 1)
	var field := Vector2(root.size.x * 0.7, 260)
	var label := "%s %s %s" % [root.size, id, "touch" if touch else "mouse"]
	_press(field, touch, true)
	_press(field, touch, false)
	_check(emissions[0] == 0 and game.shots_left == 2, label + ": field press before launch does not spend ability or ammo")
	_launch(game, touch)
	_check(game.state == GameRound.RoundState.FLYING and game.shots_left == 1 and emissions[0] == 0, label + ": launch release starts flight without activating")

	game.set_paused(true)
	_press(field, touch, true)
	_press(field, touch, false)
	_check(emissions[0] == 0, label + ": pause blocks screen activation")
	game.set_paused(false)

	_mouse(field, true, MOUSE_BUTTON_RIGHT)
	_mouse(field, false, MOUSE_BUTTON_RIGHT)
	_mouse(field, true, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_mouse(field, false, MOUSE_BUTTON_LEFT, InputEvent.DEVICE_ID_EMULATION)
	_touch(field, true, true)
	_touch(field, false, true)
	_press(field, touch, false)
	_check(emissions[0] == 0, label + ": secondary buttons, emulation, cancellation and release do not activate")

	var help := game.hud._help_button.get_global_rect().get_center()
	_press(help, touch, true)
	_press(help, touch, false)
	_check(game.hud._help_card.visible and emissions[0] == 0, label + ": GUI help press does not activate")
	_press(help, touch, true)
	_press(help, touch, false)

	if "--capture-screen-ability" in OS.get_cmdline_user_args() and id == &"classic":
		game.hud._help_button.button_pressed = true
		game.hud._toggle_help()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.artifacts/screen-ability-%s-%dx%d.png" % ["touch" if touch else "mouse", root.size.x, root.size.y])
		game.hud._help_button.button_pressed = false
		game.hud._toggle_help()

	_press(field, touch, true)
	_check(emissions[0] == 1 and game._tutorial_ability_used, label + ": field press immediately activates the actual ability and lesson")
	_press(field, touch, false)
	_press(field + Vector2(30, 0), touch, true)
	_press(field + Vector2(30, 0), touch, false)
	_check(emissions[0] == 1 and game.shots_left == 1, label + ": release and repeated press cannot activate twice or launch again")
	game.queue_free()
	for frame in 4:
		await process_frame


func _test_unavailable() -> void:
	var game := await _new_game(&"classic")
	var cat := game.slingshot.loaded_projectile
	_launch(game, false)
	cat._has_contacted = true
	var field := Vector2(root.size.x * 0.7, 260)
	for touch: bool in [false, true]:
		_press(field, touch, true)
		_press(field, touch, false)
	_check(not cat.ability_spent and not game._tutorial_ability_used, "Screen input respects the contact lock")
	game.queue_free()
	await process_frame
	await process_frame
	game = await _new_game(&"zigzag")
	cat = game.slingshot.loaded_projectile
	_launch(game, true)
	for touch: bool in [false, true]:
		_press(field, touch, true)
		_press(field, touch, false)
	_check(not cat.ability_spent and game.shots_left == 1, "Automatic zigzag remains automatic after screen presses")
	game.queue_free()
	await process_frame
	await process_frame


func _launch(game: GameRound, touch: bool) -> void:
	var transform := game.slingshot.get_canvas_transform()
	var anchor := transform * game.slingshot.global_position
	var pull := anchor + Vector2(-70, 35)
	_press(anchor, touch, true)
	if touch:
		var drag := InputEventScreenDrag.new()
		drag.index = 4
		drag.position = pull
		root.push_input(drag, true)
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = pull
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
	_press(pull, touch, false)


func _press(position: Vector2, touch: bool, pressed: bool) -> void:
	if touch:
		_touch(position, pressed)
	else:
		_mouse(position, pressed)


func _touch(position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 4
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _mouse(position: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	event.device = device
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
