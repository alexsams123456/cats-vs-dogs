extends SceneTree
## Simple Web polygons must preserve source geometry, alpha and local transforms.

const AMBIENT := preload("res://scripts/world/ambient_life.gd")
const ACTIVITY := preload("res://scripts/world/background_activity.gd")
var _shapes: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(-25, -15), Vector2(27, -12), Vector2(3, 26)]),
	PackedVector2Array([Vector2(0, -25), Vector2(19, 0), Vector2(0, 29), Vector2(-19, 0)]),
	PackedVector2Array([Vector2(-6, 0), Vector2(-1, -3), Vector2(6, 0), Vector2(0, 3)]),
	PackedVector2Array([Vector2.ZERO, Vector2(24, 0), Vector2(24, -13.2), Vector2(0, -4.8)]),
]
const COLORS: Array[Color] = [Color("dca99c"), Color(0.2, 0.7, 0.9, 0.6), Color(0.97, 0.98, 0.9, 0.18)]
const SCALES: Array[Vector2] = [Vector2.ONE * 0.62, Vector2.ONE, Vector2.ONE * 2.0, Vector2.ONE, Vector2(-1.3, 0.8)]
const ANGLES: Array[float] = [0.0, 0.0, 0.0, 0.43, -0.37]
var _checks: int = 0
var _failures: int = 0


class AmbientProbe:
	extends AMBIENT
	var points := PackedVector2Array([Vector2(-25, -15), Vector2(27, -12), Vector2(3, 26)])
	var tint: Color = COLORS[0]
	var polygon_count: int = 1
	var paint_transform := Transform2D(0.19, Vector2(0.13, 0.27))
	func _ready() -> void:
		pass
	func _draw() -> void:
		for index in polygon_count:
			draw_set_transform_matrix(Transform2D(0, Vector2((index % 8) * 40, (index / 8) * 30)) * paint_transform)
			_paint_polygon(points, tint)


class ActivityProbe:
	extends ACTIVITY
	var points := PackedVector2Array([Vector2(-25, -15), Vector2(27, -12), Vector2(3, 26)])
	var tint: Color = COLORS[0]
	var polygon_count: int = 1
	var paint_transform := Transform2D(0.19, Vector2(0.13, 0.27))
	func _ready() -> void:
		pass
	func _draw() -> void:
		for index in polygon_count:
			draw_set_transform_matrix(Transform2D(0, Vector2((index % 8) * 40, (index / 8) * 30)) * paint_transform)
			_paint_polygon(points, tint)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for source: GDScript in [AMBIENT, ACTIVITY]:
		var drawing := source.new() as Node2D
		_check(drawing.use_batched_polygons == OS.has_feature("web"), "Polygon batching defaults to Web only")
		for enabled in [false, true]:
			drawing.use_batched_polygons = enabled
			for count in [2, 3, 4, 5]:
				var points := PackedVector2Array()
				points.resize(count)
				_check(drawing._can_batch_polygon(points) == (enabled and count in [3, 4]), "Polygon guard preserves native fallback: enabled %s, %d vertices" % [enabled, count])
		drawing.free()
	if "--capture-polygons" in OS.get_cmdline_user_args():
		await _test_graphics()
	print("Web polygon checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _test_graphics() -> void:
	var sheet := Image.create(800, 400, false, Image.FORMAT_RGBA8)
	for source_index in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(200, 200)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var drawing: Node2D = AmbientProbe.new() if source_index == 0 else ActivityProbe.new()
		drawing.position = Vector2(100, 100)
		viewport.add_child(drawing)
		for shape_index in _shapes.size():
			drawing.points = _shapes[shape_index]
			for color_index in COLORS.size():
				drawing.tint = COLORS[color_index]
				for transform_index in SCALES.size():
					drawing.scale = SCALES[transform_index]
					drawing.rotation = ANGLES[transform_index]
					drawing.use_batched_polygons = false
					drawing.queue_redraw()
					var original := await _capture(viewport)
					drawing.use_batched_polygons = true
					drawing.queue_redraw()
					var batched := await _capture(viewport)
					_compare(original, batched, "source %d shape %d color %d transform %d" % [source_index, shape_index, color_index, transform_index])
					if source_index == 0 and color_index == 1 and transform_index == 4:
						sheet.blit_rect(original, Rect2i(0, 0, 200, 200), Vector2i(shape_index * 200, 0))
						sheet.blit_rect(batched, Rect2i(0, 0, 200, 200), Vector2i(shape_index * 200, 200))
		await _test_batch_count(viewport, drawing)
		viewport.queue_free()
		await process_frame
	sheet.save_png("res://.artifacts/web-polygons-native-top-batched-bottom.png")


func _test_batch_count(viewport: SubViewport, drawing: Node2D) -> void:
	viewport.size = Vector2i(400, 340)
	drawing.position = Vector2(25, 20)
	drawing.scale = Vector2.ONE
	drawing.rotation = 0.0
	drawing.paint_transform = Transform2D.IDENTITY
	drawing.points = PackedVector2Array([Vector2.ZERO, Vector2(18, 2), Vector2(10, 16)])
	drawing.polygon_count = 80
	drawing.use_batched_polygons = false
	drawing.queue_redraw()
	await _capture(viewport)
	var original_calls := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	drawing.use_batched_polygons = true
	drawing.queue_redraw()
	await _capture(viewport)
	var batched_calls := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_check(original_calls >= 80 and batched_calls > 0 and batched_calls < original_calls / 5.0, "80 simple polygons reduce canvas draw calls: %d -> %d" % [original_calls, batched_calls])


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _compare(original: Image, batched: Image, label: String) -> void:
	var difference: float = 0.0
	var painted: int = 0
	var changed: int = 0
	for y in original.get_height():
		for x in original.get_width():
			var a := original.get_pixel(x, y)
			var b := batched.get_pixel(x, y)
			var delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
			difference += delta
			if maxf(a.a, b.a) > 0.01:
				painted += 1
			if delta > 0.02:
				changed += 1
	var mean := difference / (maxi(painted, 1) * 4.0)
	var changed_fraction := float(changed) / maxi(painted, 1)
	_check(painted > 0 and mean < 0.002 and changed_fraction < 0.01, "Batched geometry matches source: %s (mean %.6f, changed %.3f%%)" % [label, mean, changed_fraction * 100.0])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	else:
		print("PASS: " + message)
