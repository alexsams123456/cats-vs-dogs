extends SceneTree
## Cache the original static procedural scenery; animated layers remain live.

const BACKDROP := preload("res://scripts/world/backdrop.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/backdrops")
	for biome: StringName in [&"backyard", &"mountain", &"glacier"]:
		for index in 3:
			var viewport := SubViewport.new()
			# Two overlapping pixels avoid seams when the camera scales the tiles.
			var width := int(BACKDROP.BAKED_TILE_WIDTH) + (2 if index < 2 else 0)
			viewport.size = Vector2i(width, int(BACKDROP.BAKED_BOTTOM - BACKDROP.BAKED_TOP)) * int(BACKDROP.BAKED_SCALE)
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var drawing := BACKDROP.new()
			drawing.use_baked_art = false
			drawing.biome = biome
			drawing.position = -Vector2(BACKDROP.WORLD_LEFT + float(index) * BACKDROP.BAKED_TILE_WIDTH, BACKDROP.BAKED_TOP)
			drawing.position *= BACKDROP.BAKED_SCALE
			drawing.scale = Vector2.ONE * BACKDROP.BAKED_SCALE
			viewport.add_child(drawing)
			root.add_child(viewport)
			drawing.set_process(false)
			drawing.get_node("AmbientLife").hide()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGB8)
			var path := "res://assets/backdrops/%s_%d.png" % [biome, index]
			if image.save_png(path) != OK:
				push_error("Cannot save " + path)
				quit(1)
				return
			viewport.queue_free()
			await process_frame
	print("Baked all three biomes into nine scenery tiles.")
	quit()
