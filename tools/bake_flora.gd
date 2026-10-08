extends SceneTree

const AMBIENT := preload("res://scripts/world/ambient_life.gd")
const ATLAS := preload("res://scripts/visuals/flora_atlas.gd")


class Sheet extends Node2D:
	var flower: bool
	var source: AmbientLife = AMBIENT.new()

	func _draw() -> void:
		var bounds := ATLAS.FLOWER_BOUNDS if flower else ATLAS.GRASS_BOUNDS
		var count: int = AMBIENT.FLOWER_ROOTS.size() if flower else 18
		for variant in count:
			for frame in ATLAS.FRAMES:
				var tile := variant * ATLAS.FRAMES + frame
				var origin := Vector2(tile % ATLAS.COLUMNS, tile / ATLAS.COLUMNS) * bounds.size * 2.0 - bounds.position * 2.0
				draw_set_transform(origin, 0.0, Vector2.ONE * 2.0)
				if flower:
					source.paint_flower(self, Vector2.ZERO, variant, ATLAS.wind_for(frame))
				else:
					source.paint_grass(self, Vector2.ZERO, variant, ATLAS.wind_for(frame))
		draw_set_transform(Vector2.ZERO)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			source.free()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for flower in [false, true]:
		var bounds := ATLAS.FLOWER_BOUNDS if flower else ATLAS.GRASS_BOUNDS
		var count: int = AMBIENT.FLOWER_ROOTS.size() if flower else 18
		var viewport := SubViewport.new()
		viewport.size = Vector2i(Vector2(ATLAS.COLUMNS, count * ATLAS.FRAMES / ATLAS.COLUMNS) * bounds.size * 2.0)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var sheet := Sheet.new()
		sheet.flower = flower
		viewport.add_child(sheet)
		root.add_child(viewport)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x, y)
				if color.a > 0.0 and color.a < 1.0:
					image.set_pixel(x, y, Color(minf(1, color.r / color.a), minf(1, color.g / color.a), minf(1, color.b / color.a), color.a))
		var path := "res://assets/scenery/%s_atlas.png" % ("flower" if flower else "grass")
		if image.save_png(path) != OK:
			push_error("Cannot save " + path)
			quit(1)
			return
		viewport.queue_free()
		await process_frame
	print("Flora atlas: grass and flowers saved at 2x detail.")
	quit()
