extends SceneTree
## Web cache must preserve moving scenery and menu art after resize/toggle.

const TREE := preload("res://scripts/world/meadow_tree.gd")
const AMBIENT := preload("res://scripts/world/ambient_life.gd")
const MENU := preload("res://scripts/ui/menu_backdrop.gd")
const FLORA := preload("res://scripts/visuals/flora_atlas.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for name in ["tree_cool", "tree_warm", "cloud"]:
		var texture := load("res://assets/scenery/%s.png" % name) as Texture2D
		_check(texture != null and texture.get_width() <= 800 and texture.get_height() <= 680, "Sharp scenery cache is present and bounded: " + name)
	var cloud := Image.load_from_file("res://assets/scenery/cloud.png")
	var edge_count: int = 0
	var clean_edges: bool = true
	for y in cloud.get_height():
		for x in cloud.get_width():
			var color := cloud.get_pixel(x, y)
			if color.a > 0.25 and color.a < 0.75:
				edge_count += 1
				clean_edges = clean_edges and minf(color.r, minf(color.g, color.b)) > 0.7
	_check(edge_count > 0 and clean_edges, "Cloud keeps bright translucent edges without double alpha multiplication")
	for name in ["grass", "flower"]:
		var texture := load("res://assets/scenery/%s_atlas.png" % name) as Texture2D
		_check(texture != null and texture.get_width() <= 4096 and texture.get_height() <= 4096, "Flora atlas is sharp and within texture limits: " + name)
	if "--capture-scenery" in OS.get_cmdline_user_args():
		await _test_trees()
		await _test_cloud()
		await _test_menu()
		await _test_flora()
	print("Scenery cache checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _test_flora() -> void:
	var source := AMBIENT.new()
	for flower in [false, true]:
		var texture := load("res://assets/scenery/%s_atlas.png" % ("flower" if flower else "grass")) as Texture2D
		var count: int = AMBIENT.FLOWER_ROOTS.size() if flower else 18
		for variant in count:
			var viewport := _viewport(Vector2i(240, 240))
			var drawing := Node2D.new()
			drawing.position = Vector2(120, 190)
			drawing.scale = Vector2.ONE * 2.5
			viewport.add_child(drawing)
			for frame in [0, 31, 63]:
				var wind := FLORA.wind_for(frame)
				var original_paint: Callable = source.paint_flower.bind(drawing, Vector2.ZERO, variant, wind) if flower else source.paint_grass.bind(drawing, Vector2.ZERO, variant, wind)
				drawing.draw.connect(original_paint)
				drawing.queue_redraw()
				var original := await _capture(viewport)
				drawing.draw.disconnect(original_paint)
				var cached_paint := FLORA.paint.bind(drawing, texture, Vector2.ZERO, variant, wind, flower)
				drawing.draw.connect(cached_paint)
				drawing.queue_redraw()
				var cached := await _capture(viewport)
				drawing.draw.disconnect(cached_paint)
				_compare(original, cached, "flora-%s-%d-%d" % [flower, variant, frame])
			viewport.queue_free()
			await process_frame
	source.free()


func _viewport(dimensions: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _test_trees() -> void:
	for warm in [false, true]:
		for zoom in [0.75, 1.0, 2.0]:
			var viewport := _viewport(Vector2i(800, 720))
			var tree := TREE.new()
			tree.use_baked_art = false
			tree.warm_foliage = warm
			tree.position = Vector2(400, 650)
			tree.rotation = 0.02
			tree.scale = Vector2(-zoom if warm else zoom, zoom)
			viewport.add_child(tree)
			var original_transform := tree.transform
			var original := await _capture(viewport)
			tree.use_baked_art = true
			tree._ready()
			tree.queue_redraw()
			var cached := await _capture(viewport)
			_compare(original, cached, "tree-%s-%.2f" % [warm, zoom])
			_check(tree.transform == original_transform, "Cache preserves tree motion transform")
			viewport.queue_free()
			await process_frame


func _test_cloud() -> void:
	var viewport := _viewport(Vector2i(512, 256))
	var source := AMBIENT.new()
	source._build_cloud_shapes()
	var drawing := Node2D.new()
	viewport.add_child(drawing)
	var paint := source.paint_cloud.bind(drawing, Vector2(256, 128), 1.7)
	drawing.draw.connect(paint)
	drawing.queue_redraw()
	var original := await _capture(viewport)
	drawing.draw.disconnect(paint)
	var texture := load("res://assets/scenery/cloud.png") as Texture2D
	drawing.draw.connect(func() -> void: drawing.draw_texture_rect(texture, Rect2(Vector2(256, 128) + Vector2(-128, -80) * 1.7, Vector2(256, 128) * 1.7), false))
	drawing.queue_redraw()
	_compare(original, await _capture(viewport), "cloud")
	viewport.queue_free()
	source.free()
	await process_frame


func _test_menu() -> void:
	var viewport := _viewport(Vector2i(1280, 720))
	var menu := MENU.new()
	menu.use_cached_art = false
	viewport.add_child(menu)
	menu.set_process(false)
	menu._motion.hide()
	menu._sun_face.hide()
	for width in [1280, 1600, 960, 1280]:
		viewport.size = Vector2i(width, 720)
		for showcase in [true, false]:
			menu.showcase_visible = showcase
			menu.use_cached_art = false
			menu.queue_redraw()
			var original := await _capture(viewport)
			menu.use_cached_art = true
			menu.queue_redraw()
			for frame in 12:
				await process_frame
				if menu._cached_size == Vector2i(width, 720) and menu._cached_showcase == showcase and not menu._cache_pending:
					break
			_check(menu._cached_size == Vector2i(width, 720) and menu._cached_showcase == showcase, "Menu refreshes cache after resize/showcase changes")
			_compare(original, await _capture(viewport), "menu-%d-%s" % [width, showcase])
	_check(menu.get_child_count() == 2, "Temporary render viewports are released")
	viewport.queue_free()
	await process_frame


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _compare(original: Image, cached: Image, label: String) -> void:
	cached.save_png("res://.artifacts/scenery-%s.png" % label)
	original.resize(320, 180, Image.INTERPOLATE_LANCZOS)
	cached.resize(320, 180, Image.INTERPOLATE_LANCZOS)
	var difference: float = 0.0
	for y in 180:
		for x in 320:
			var a := original.get_pixel(x, y)
			var b := cached.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / (320.0 * 180.0 * 3.0)
	_check(mean < 0.006, "Scenery matches source: %s (mean %.5f)" % [label, mean])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	else:
		print("PASS: " + message)
