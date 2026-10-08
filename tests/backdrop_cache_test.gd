extends SceneTree
## Verify Web scenery resources, biome changes and rendered parity with source art.

const BACKDROP := preload("res://scripts/world/backdrop.gd")
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var drawing := BACKDROP.new()
	drawing.use_baked_art = true
	viewport.add_child(drawing)
	drawing.set_process(false)
	drawing.get_node("AmbientLife").hide()
	for biome: StringName in [&"backyard", &"mountain", &"glacier", &"backyard"]:
		drawing.set_biome(biome)
		_check(drawing._baked_tiles.size() == 3 and drawing._baked_biome == biome, "Biome has all three cached tiles")
		for tile: Texture2D in drawing._baked_tiles:
			_check(tile.get_height() == 1840 and tile.get_width() <= 3804, "Sharp tile stays within 4096 px texture limits")
	if "--capture-backdrops" in OS.get_cmdline_user_args():
		for biome: StringName in [&"backyard", &"mountain", &"glacier"]:
			drawing.set_biome(biome)
			for width in [1280, 1600, 960]:
				viewport.size = Vector2i(width, 720)
				# Includes the first tile seam at x = -300 in the wide view.
				viewport.canvas_transform = Transform2D(0, Vector2(400, 0))
				drawing.use_baked_art = false
				drawing.queue_redraw()
				var original := await _capture(viewport)
				drawing.use_baked_art = true
				drawing.queue_redraw()
				var cached := await _capture(viewport)
				cached.save_png("res://.artifacts/backdrop-%s-%d.png" % [biome, width])
				original.resize(320, 180, Image.INTERPOLATE_LANCZOS)
				cached.resize(320, 180, Image.INTERPOLATE_LANCZOS)
				var difference: float = 0.0
				for y in 180:
					for x in 320:
						var a := original.get_pixel(x, y)
						var b := cached.get_pixel(x, y)
						difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				var mean := difference / (320.0 * 180.0 * 3.0)
				_check(mean < 0.006, "Cached %s %d matches procedural scenery (mean %.5f)" % [biome, width, mean])
	viewport.queue_free()
	await process_frame
	print("Backdrop cache checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
	else:
		print("PASS: " + message)
