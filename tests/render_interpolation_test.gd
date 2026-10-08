extends SceneTree
## Rendering smoothing must leave physical motion and immediate aim intact.

const CAT := preload("res://scenes/actors/cat_projectile.tscn")
const MAIN := preload("res://scenes/main.tscn")
var _failures: int = 0
var _checks: int = 0


class MovingDot extends RigidBody2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 5.0, Color.WHITE, true, -1, true)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(ProjectSettings.get_setting("physics/common/physics_interpolation"), "Project enables visual physics interpolation")
	_check(Engine.physics_ticks_per_second == 60, "Physics keeps 60 ticks per second")
	var game := MAIN.instantiate()
	_check(game.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Camera and live decor are not interpolated")
	_check(game.get_node("Actors").physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "Physical actors are interpolated")
	game.free()
	var cat := CAT.instantiate() as CatProjectile
	root.add_child(cat)
	cat.freeze = true
	cat.position = Vector2(100, 100)
	_check(cat.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Loaded cat responds to aim immediately")
	cat.gravity_scale = 0.0
	cat.linear_damp = 0.0
	# This test inspects transforms only; audio lifecycle is covered separately.
	cat.meow_count = CatProjectile.MAX_MEOWS
	cat.launch(Vector2(120, 0))
	_check(cat.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "Flight enables visual interpolation")
	_check(cat.position == Vector2(100, 100) and cat.linear_velocity == Vector2(120, 0), "Smoothing changes neither launch position nor velocity")
	cat.queue_free()
	await process_frame
	if "--capture-interpolation" in OS.get_cmdline_user_args():
		await _test_rendered_motion()
	print("Render interpolation checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _test_rendered_motion() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 200)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = true
	root.add_child(viewport)
	var dot := MovingDot.new()
	dot.position = Vector2(80, 100)
	dot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	dot.gravity_scale = 0.0
	dot.linear_damp = 0.0
	dot.linear_velocity = Vector2(120, 0)
	viewport.add_child(dot)
	dot.reset_physics_interpolation()
	for frame in 6:
		await process_frame
	var positions: Array[float] = []
	for frame in 30:
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var weight: float = 0.0
		var total: float = 0.0
		for y in range(92, 108):
			for x in 220:
				var brightness := image.get_pixel(x, y).a
				total += brightness
				weight += float(x) * brightness
		positions.append(weight / maxf(total, 0.001))
	var moving_frames: int = 0
	for index in range(1, positions.size()):
		if positions[index] - positions[index - 1] > 0.2:
			moving_frames += 1
	_check(moving_frames >= 24, "120 Hz rendering advances smoothly between 60 Hz physics ticks (%d/29)" % moving_frames)
	viewport.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	else:
		print("PASS: " + message)
