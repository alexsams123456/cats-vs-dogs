extends SceneTree
## Стартовые постройки сохраняют опоры при нескольких физических шагах на кадр.

const MAIN := preload("res://scenes/main.tscn")
const FIRST_LEVEL := preload("res://levels/campaign/01_first_throw.tres")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var capture := "--capture-start" in OS.get_cmdline_user_args()
	# A small gap avoids simultaneous contact correction across every floor.
	for first in FIRST_LEVEL.block_positions.size():
		var first_rect := Rect2(FIRST_LEVEL.block_positions[first] - FIRST_LEVEL.block_sizes[first] * 0.5, FIRST_LEVEL.block_sizes[first]).grow(0.25)
		for second in range(first + 1, FIRST_LEVEL.block_positions.size()):
			var second_rect := Rect2(FIRST_LEVEL.block_positions[second] - FIRST_LEVEL.block_sizes[second] * 0.5, FIRST_LEVEL.block_sizes[second]).grow(0.25)
			_check(not first_rect.intersects(second_rect), "First level bodies %d and %d have clearance at startup" % [first, second])
	for attempt in 6:
		var game := MAIN.instantiate() as GameRound
		var campaign := attempt % 2 == 0
		if campaign:
			game.level = FIRST_LEVEL.duplicate(true) as LevelDefinition
			game.campaign_mode = true
		if capture:
			root.size = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)][attempt / 2]
		root.add_child(game)
		current_scene = game
		var records: Array[Dictionary] = []
		for actor in game.actors.get_children():
			if actor is WoodenBlock or actor is DogHouse:
				records.append({"body": weakref(actor), "position": actor.position, "drift": 0.0, "rotation": 0.0})
		for tick in 600:
			await physics_frame
			for record in records:
				var body := (record.body as WeakRef).get_ref() as DestructibleBody
				if is_instance_valid(body):
					record.drift = maxf(record.drift, body.position.distance_to(record.position))
					record.rotation = maxf(record.rotation, absf(body.rotation))
		for index in records.size():
			var record: Dictionary = records[index]
			var body := (record.body as WeakRef).get_ref() as DestructibleBody
			var label := "%s start %d body %d" % ["Campaign" if campaign else "Sandbox", attempt, index]
			_check(is_instance_valid(body) and not body.is_destroyed, label + " survives without a shot")
			if is_instance_valid(body):
				_check(is_zero_approx(body.damage_ratio()), label + " receives no startup damage")
			_check(record.drift < 8.0, label + " retains its support throughout startup (drift %.2f)" % record.drift)
			_check(record.rotation < 0.1, label + " stays upright (rotation %.3f)" % record.rotation)
		_check(game.dogs_left == 2 and game.state == GameRound.RoundState.READY and game.shots_left == game.level.shots, "Waiting does not defeat dogs or spend shots")
		if capture:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.artifacts/start-%d.png" % attempt)
		game.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.2, true, false, true).timeout
	print("First level stability: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
