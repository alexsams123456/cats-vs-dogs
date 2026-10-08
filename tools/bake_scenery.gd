extends SceneTree
## Snapshot the original trees and cloud; their nodes keep live motion.

const TREE := preload("res://scripts/world/meadow_tree.gd")
const AMBIENT := preload("res://scripts/world/ambient_life.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/scenery")
	for warm in [false, true]:
		var drawing := TREE.new()
		drawing.use_baked_art = false
		drawing.warm_foliage = warm
		drawing.position = Vector2(200, 320)
		if not await _save(drawing, Vector2i(400, 340), "tree_%s" % ("warm" if warm else "cool")):
			quit(1)
			return
	var cloud := Node2D.new()
	var source := AMBIENT.new()
	source._build_cloud_shapes()
	cloud.draw.connect(source.paint_cloud.bind(cloud, Vector2(128, 80), 1.0))
	var saved := await _save(cloud, Vector2i(256, 128), "cloud")
	source.free()
	if not saved:
		quit(1)
		return
	print("Scenery cache: two trees and one cloud saved.")
	quit()


func _save(drawing: Node2D, dimensions: Vector2i, name: String) -> bool:
	var viewport := SubViewport.new()
	viewport.size = dimensions * 2
	viewport.transparent_bg = true
	drawing.position *= 2.0
	drawing.scale *= 2.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(drawing)
	root.add_child(viewport)
	await process_frame
	await RenderingServer.frame_post_draw
	var saved := _save_image(viewport, name)
	viewport.queue_free()
	await process_frame
	return saved


func _save_image(viewport: SubViewport, name: String) -> bool:
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	# Transparent render targets contain premultiplied RGB. PNG uses straight alpha.
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.0 and color.a < 1.0:
				image.set_pixel(x, y, Color(minf(1.0, color.r / color.a), minf(1.0, color.g / color.a), minf(1.0, color.b / color.a), color.a))
	if image.save_png("res://assets/scenery/%s.png" % name) != OK:
		push_error("Cannot save scenery: " + name)
		return false
	return true
