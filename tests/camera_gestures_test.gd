extends SceneTree
## Real viewport input checks; synthetic touches do not replace a device test.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const HOME := Vector2(640, 360)
const FIRST := Vector2(540, 350)
const SECOND := Vector2(740, 350)

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := await _new_game()
	var camera := game.get_node("Camera2D") as GameCamera
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Round starts at normal scale")
	_check(camera.position.is_equal_approx(HOME), "Round starts at the original center")
	_test_zoom_and_pan(game, camera)
	_test_coincident_fingers(camera)
	_test_aim_interruption(game, camera)
	_test_extra_finger(game, camera)
	_test_gui(game, camera)
	_test_cancellation(game, camera)
	await _test_resize(game, camera)
	await _test_finished_overlay(game, camera)
	await _dispose_game(game)
	await _test_shot_after_zoom(false)
	await _test_shot_after_zoom(true)
	print("Camera gesture checks: %d passed, %d failed" % [_checks - _failures, _failures])
	await create_timer(0.3).timeout
	quit(1 if _failures else 0)


func _test_zoom_and_pan(game: GameRound, camera: GameCamera) -> void:
	camera.reset_view()
	var hud_rect := game.hud._pause_button.get_global_rect()
	var midpoint := (FIRST + SECOND) * 0.5
	var anchor := _world_point(camera, midpoint)
	_begin_pinch()
	_drag(FIRST - Vector2(50, 0), 20)
	_drag(SECOND + Vector2(50, 0), 21)
	_check(is_equal_approx(camera.zoom.x, 1.5), "Spreading fingers scales by their distance ratio")
	_check(_world_point(camera, midpoint).distance_to(anchor) < 0.1, "World point stays under the pinch midpoint")
	var pan := Vector2(40, 25)
	_drag(FIRST - Vector2(50, 0) + pan, 20)
	_drag(SECOND + Vector2(50, 0) + pan, 21)
	_check(is_equal_approx(camera.zoom.x, 1.5), "Moving both fingers together preserves scale")
	_check(_world_point(camera, midpoint + pan).distance_to(anchor) < 0.1, "Moving both fingers pans the anchored world point")
	_check(game.hud._pause_button.get_global_rect().is_equal_approx(hud_rect), "Zoom and pan leave the HUD in screen coordinates")
	_end_pinch()

	camera.reset_view()
	_begin_pinch()
	_drag(Vector2(40, 350), 20)
	_drag(Vector2(1240, 350), 21)
	_check(is_equal_approx(camera.zoom.x, camera.max_zoom), "Spreading is limited by maximum zoom")
	_drag(Vector2(630, 350), 20)
	_drag(Vector2(650, 350), 21)
	_check(is_equal_approx(camera.zoom.x, camera.min_zoom), "Pinching is limited by minimum zoom")
	_check(camera.position.distance_to(HOME) < 0.1, "Minimum zoom returns the full overview to its home center")
	_end_pinch()

	camera.reset_view()
	_begin_pinch()
	_drag(FIRST - Vector2(50, 0), 20)
	_drag(SECOND + Vector2(50, 0), 21)
	_drag(Vector2(5000, 4000), 20)
	_drag(Vector2(5300, 4000), 21)
	_check_view_bounds(camera, "Pan cannot leave the overview bounds")
	_end_pinch()
	camera.reset_view()
	_wheel(midpoint, MOUSE_BUTTON_WHEEL_UP)
	_check(camera.zoom.x > 1.0, "Mouse wheel zooms in on desktop")
	_check(_world_point(camera, midpoint).distance_to(anchor) < 0.1, "Wheel keeps the world point under the cursor")
	_check(game.shots_left == 4, "Camera gestures do not consume ammunition")


func _test_coincident_fingers(camera: GameCamera) -> void:
	camera.reset_view()
	var center := (FIRST + SECOND) * 0.5
	_touch(center, 20, true)
	_touch(center, 21, true)
	_drag(center + Vector2(1, 0), 21)
	_check(camera.zoom.is_equal_approx(Vector2.ONE) and camera.position.is_equal_approx(HOME), "Coincident fingers and a tiny movement keep a finite, unchanged view")
	_drag(center + Vector2(50, 0), 21)
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Separating nearly coincident fingers establishes a baseline without a zoom jump")
	_drag(center + Vector2(75, 0), 21)
	_check(is_equal_approx(camera.zoom.x, 1.5) and camera.position.is_finite(), "The same pinch resumes normal scaling once fingers separate")
	_end_pinch()


func _test_aim_interruption(game: GameRound, camera: GameCamera) -> void:
	camera.reset_view()
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	_touch(anchor, 20, true)
	_drag(anchor + Vector2(-45, 25), 20)
	_check(game.slingshot.is_dragging, "First finger can pull the cat before pinching")
	_touch(anchor + Vector2(220, -50), 21, true)
	_check(not game.slingshot.is_dragging, "Second finger cancels the active slingshot pull")
	_check(game.slingshot.loaded_projectile.global_position.is_equal_approx(game.slingshot.global_position), "Pinch cancellation returns the cat to the pouch")
	_check(game.shots_left == 4 and game.state == GameRound.RoundState.READY, "Starting a pinch does not launch the cat")
	_touch(anchor + Vector2(220, -50), 21, false)
	_drag(anchor + Vector2(-80, 50), 20)
	_touch(anchor + Vector2(-80, 50), 20, false)
	_check(game.shots_left == 4 and not game.slingshot.is_dragging, "Remaining finger cannot fire after the pinch")
	_touch(anchor, 22, true)
	_check(game.slingshot.is_dragging, "A fresh touch can aim after all pinch fingers lift")
	_touch(anchor, 22, false, true)


func _test_extra_finger(game: GameRound, camera: GameCamera) -> void:
	camera.reset_view()
	_begin_pinch()
	_drag(FIRST - Vector2(50, 0), 20)
	_drag(SECOND + Vector2(50, 0), 21)
	var previous_zoom := camera.zoom
	var previous_position := camera.position
	_touch(Vector2(640, 500), 22, true)
	_drag(Vector2(650, 530), 22)
	_check(camera.zoom.is_equal_approx(previous_zoom) and camera.position.is_equal_approx(previous_position), "A third finger does not replace the active pair")
	_touch(FIRST - Vector2(50, 0), 20, false)
	_check(camera.zoom.is_equal_approx(previous_zoom) and camera.position.is_equal_approx(previous_position), "Replacing a lifted pinch finger does not jump the camera")
	_drag(Vector2(670, 550), 22)
	_check(not camera.zoom.is_equal_approx(previous_zoom), "The remaining pair continues the gesture")
	_touch(SECOND + Vector2(50, 0), 21, false)
	_touch(Vector2(670, 550), 22, false)
	_check(game.shots_left == 4, "Three-finger transitions never launch a cat")


func _test_gui(game: GameRound, camera: GameCamera) -> void:
	camera.reset_view()
	var button_center := game.hud._pause_button.get_global_rect().get_center()
	_touch(button_center, 20, true)
	_touch(SECOND, 21, true)
	_drag(SECOND + Vector2(120, 0), 21)
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "A finger starting on HUD cannot join a pinch")
	_touch(SECOND + Vector2(120, 0), 21, false)
	_touch(button_center, 20, false)
	_check(paused, "HUD pause still responds to an ordinary touch")
	game.set_paused(false)
	_wheel(button_center, MOUSE_BUTTON_WHEEL_UP)
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Mouse wheel over HUD does not zoom")


func _test_cancellation(game: GameRound, camera: GameCamera) -> void:
	camera.reset_view()
	_begin_pinch()
	_touch(FIRST, 20, false, true)
	_drag(SECOND + Vector2(200, 0), 21)
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Canceled touch clears the entire pinch")
	_end_pinch()
	for focus_loss in [false, true]:
		_begin_pinch()
		if focus_loss:
			game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			game.set_paused(true)
		_check(paused, "Pause/focus loss pauses the round")
		_drag(SECOND + Vector2(200, 0), 21)
		_check(camera.zoom.is_equal_approx(Vector2.ONE), "Paused gameplay ignores finger movement")
		game.set_paused(false)
		_drag(SECOND + Vector2(300, 0), 21)
		_check(camera.zoom.is_equal_approx(Vector2.ONE), "Resume does not restore stale fingers")
		_end_pinch()
	_begin_pinch()
	_drag(SECOND + Vector2(80, 0), 21)
	_check(camera.zoom.x > 1.0, "A new pinch works after cancellation and focus recovery")
	_end_pinch()


func _test_resize(game: GameRound, camera: GameCamera) -> void:
	for viewport_size in [Vector2i(1600, 720), Vector2i(960, 720), Vector2i(1280, 720)]:
		camera.reset_view()
		_begin_pinch()
		root.size = viewport_size
		await _settle()
		var previous_zoom := camera.zoom
		_drag(SECOND + Vector2(200, 0), 21)
		_check(camera.zoom.is_equal_approx(previous_zoom), "Resize clears stale fingers at %s" % viewport_size)
		_end_pinch()
		camera.reset_view()
		_begin_pinch()
		_drag(FIRST - Vector2(50, 0), 20)
		_drag(SECOND + Vector2(50, 0), 21)
		_check(is_equal_approx(camera.zoom.x, 1.5), "New pinch works after resizing to %s" % viewport_size)
		_check_view_bounds(camera, "Camera bounds hold at %s" % viewport_size)
		_end_pinch()
	_check(game.shots_left == 4, "Resizing does not release a cat")


func _test_finished_overlay(game: GameRound, camera: GameCamera) -> void:
	camera.reset_view()
	for dog in get_nodes_in_group("targets"):
		dog.destroy()
	await _settle()
	_check(game.state == GameRound.RoundState.WON and not game.hud._overlay.visible, "Victory waits before displaying the result overlay")
	_wheel(Vector2(150, 250), MOUSE_BUTTON_WHEEL_UP)
	_check(camera.zoom.is_equal_approx(Vector2.ONE), "Result overlay blocks wheel input outside its card")
	_touch(Vector2(80, 300), 20, true)
	_touch(Vector2(280, 300), 21, true)
	_drag(Vector2(30, 300), 20)
	_drag(Vector2(330, 300), 21)
	_check(camera.zoom.is_equal_approx(Vector2.ONE) and camera.position.is_equal_approx(HOME), "Result overlay blocks new camera gestures")
	_touch(Vector2(30, 300), 20, false)
	_touch(Vector2(330, 300), 21, false)
	await create_timer(GameHUD.VICTORY_DELAY + GameHUD.RESULT_FADE_DURATION).timeout
	_check(game.hud._overlay.visible, "Victory displays the result after its short delay")


func _test_shot_after_zoom(touch: bool) -> void:
	var game := await _new_game()
	var camera := game.get_node("Camera2D") as GameCamera
	var center := Vector2(400, 400)
	_touch(center - Vector2(100, 0), 20, true)
	_touch(center + Vector2(100, 0), 21, true)
	_drag(center - Vector2(150, 0), 20)
	_drag(center + Vector2(150, 0), 21)
	_end_pinch()
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	var offset := Vector2(48, -24)
	var cat := game.slingshot.loaded_projectile
	var name := "Touch" if touch else "Mouse"
	if touch:
		_touch(anchor, 4, true)
		_drag(anchor + offset, 4)
	else:
		_mouse(anchor, true)
		_mouse_motion(anchor + offset)
	_check(game.slingshot.is_dragging, name + " can aim after zooming")
	var world_pull := offset / camera.zoom
	_check(cat.global_position.distance_to(game.slingshot.global_position + world_pull) < 0.1, name + " aiming converts screen movement to world coordinates")
	if touch:
		_mouse(anchor, true, InputEvent.DEVICE_ID_EMULATION)
		_mouse(anchor + offset, false, InputEvent.DEVICE_ID_EMULATION)
		_check(game.slingshot.is_dragging and game.shots_left == 4, "Emulated mouse release cannot interrupt an active touch")
		_touch(anchor + offset, 4, false)
	else:
		_mouse(anchor + offset, false)
	_check(game.shots_left == 3 and game.state == GameRound.RoundState.FLYING, name + " launches exactly one cat after zooming")
	_check(cat.linear_velocity.distance_to(-world_pull * game.slingshot.launch_speed) < 0.1, name + " launch power uses the world-space pull")
	await _dispose_game(game)


func _check_view_bounds(camera: GameCamera, description: String) -> void:
	var view_size := root.get_visible_rect().size
	var overview := Rect2(HOME - view_size / (2.0 * camera.min_zoom), view_size / camera.min_zoom)
	var visible := Rect2(camera.position - view_size / (2.0 * camera.zoom), view_size / camera.zoom)
	_check(overview.grow(0.1).encloses(visible), description)


func _world_point(camera: GameCamera, position: Vector2) -> Vector2:
	return camera.get_canvas_transform().affine_inverse() * position


func _new_game() -> GameRound:
	var game := MAIN_SCENE.instantiate() as GameRound
	root.add_child(game)
	current_scene = game
	await _settle()
	return game


func _dispose_game(game: GameRound) -> void:
	paused = false
	game.queue_free()
	await _settle()


func _settle() -> void:
	for frame in 4:
		await process_frame


func _begin_pinch() -> void:
	_touch(FIRST, 20, true)
	_touch(SECOND, 21, true)


func _end_pinch() -> void:
	_touch(FIRST, 20, false)
	_touch(SECOND, 21, false)


func _touch(position: Vector2, index: int, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)


func _drag(position: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = position
	event.index = index
	root.push_input(event, true)


func _mouse(position: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device
	root.push_input(event, true)


func _mouse_motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func _wheel(position: Vector2, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
