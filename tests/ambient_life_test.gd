extends SceneTree
## Живой декор не участвует в игре, подчиняется паузе и неподвижен в редакторе.

const BACKDROP := preload("res://scripts/world/backdrop.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for biome: StringName in LevelDefinition.BIOMES:
		await _test_world(biome)
		await _test_editor(biome)
	print("Ambient life checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_world(biome: StringName) -> void:
	seed(76381)
	var expected_random := _random_sequence()
	seed(76381)
	var backdrop := BACKDROP.new()
	backdrop.set_biome(biome)
	root.add_child(backdrop)
	await create_timer(0.08).timeout
	var ambient := backdrop.get_node("AmbientLife") as AmbientLife
	_check(ambient.biome == biome, "Decor uses the selected biome: " + String(biome))
	_check(_only_decoration(backdrop), "Decor has no physics or input handlers: " + String(biome))
	_check(backdrop.animation_time > 0.0 and is_equal_approx(ambient._time, backdrop.animation_time), "Every biome follows the backdrop clock")
	_check(_random_sequence() == expected_random, "Creating and animating decor leaves the gameplay RNG unchanged")
	paused = true
	var frozen := _snapshot(backdrop)
	await create_timer(0.08, true).timeout
	_check(_snapshot(backdrop) == frozen, "Pause freezes all decorative transforms and clocks: " + String(biome))
	paused = false
	var stopped_time: float = backdrop.animation_time
	await create_timer(0.04).timeout
	_check(backdrop.animation_time > stopped_time, "Decor resumes after pause")
	var node_count := _node_count(backdrop)
	seed(76381)
	ambient.advance(3600.0, 3600.0, Rect2(-320, -20, 1920, 720))
	_check(_node_count(backdrop) == node_count and _only_decoration(backdrop), "Long animation does not accumulate gameplay objects")
	_check(_random_sequence() == expected_random, "Advancing decor leaves the gameplay RNG unchanged")
	backdrop.queue_free()
	await process_frame


func _test_editor(biome: StringName) -> void:
	var canvas := LevelCanvas.new()
	canvas.size = Vector2(960, 720)
	canvas.draft = LevelDefinition.new()
	canvas.draft.biome = String(biome)
	root.add_child(canvas)
	var backdrop := canvas._backdrop
	_check(StringName(backdrop.get("biome")) == biome, "Editor displays the selected biome")
	var frozen := _snapshot(backdrop)
	await create_timer(0.08).timeout
	_check(_snapshot(backdrop) == frozen, "Editor keeps the entire landscape still: " + String(biome))
	_check(_only_decoration(backdrop), "Editor decor cannot intercept editing input")
	canvas.queue_free()
	await process_frame


func _only_decoration(node: Node) -> bool:
	if node is CollisionObject2D or node is CollisionShape2D or node is CollisionPolygon2D or node is Joint2D:
		return false
	if node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input() or node.is_processing_shortcut_input():
		return false
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child: Node in node.get_children():
		if not _only_decoration(child):
			return false
	return true


func _snapshot(backdrop: Node2D) -> Array:
	var ambient := backdrop.get_node("AmbientLife") as AmbientLife
	var result: Array = [backdrop.get("animation_time"), ambient._time, ambient._cloud_x.duplicate()]
	_append_transforms(backdrop, result)
	return result


func _append_transforms(node: Node, result: Array) -> void:
	if node is Node2D:
		result.append((node as Node2D).transform)
		result.append((node as Node2D).visible)
	for child: Node in node.get_children():
		_append_transforms(child, result)


func _node_count(node: Node) -> int:
	var result: int = 1
	for child: Node in node.get_children():
		result += _node_count(child)
	return result


func _random_sequence() -> PackedInt64Array:
	var result := PackedInt64Array()
	for index in 4:
		result.append(randi())
	return result


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
