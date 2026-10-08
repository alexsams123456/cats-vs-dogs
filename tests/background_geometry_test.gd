extends SceneTree
## Кэш геометрии сохраняет прежний рисунок эллипсов фоновых сценок.

const ACTIVITY := preload("res://scripts/world/background_activity.gd")
const CENTERS := [Vector2.ZERO, Vector2(-320, -83), Vector2(387, 294), Vector2(1340, 620)]
const RADII := [Vector2.ONE, Vector2(5, 2.3), Vector2(11, 17), Vector2(23, 14), Vector2(78, 17)]
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for center: Vector2 in CENTERS:
		for radius: Vector2 in RADII:
			var original := _original_ellipse(center, radius)
			var cached := ACTIVITY._ellipse_points(center, radius)
			var maximum_error: float = 0.0
			if original.size() == cached.size():
				for index in original.size():
					maximum_error = maxf(maximum_error, original[index].distance_to(cached[index]))
			else:
				maximum_error = INF
			_check(maximum_error <= 0.0001, "Cached ellipse preserves the original contour at %s / %s" % [center, radius])
			_check(Geometry2D.triangulate_polygon(cached).size() == 54, "Cached ellipse remains a complete 20-vertex polygon")
	var activity := ACTIVITY.new()
	root.add_child(activity)
	_check(activity._kite_string.size() == 21 and activity._kite_tail.size() == 17, "Kite buffers keep the original sample counts")
	activity.free()
	print("Background geometry checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _original_ellipse(center: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in 20:
		var angle := float(index) * TAU / 20
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
