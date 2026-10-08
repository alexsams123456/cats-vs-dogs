extends SceneTree
## Bake only body/accessories; faces remain procedural and retain their clocks.

const VISUAL := preload("res://scripts/visuals/hero_visual.gd")
const ATLAS := preload("res://scripts/visuals/hero_atlas.gd")
const CATALOG := preload("res://scripts/data/character_catalog.gd")


class Sheet extends Node2D:
	var definition: CharacterDefinition
	var layer: String
	var cell: int = ATLAS.CELL

	func _draw() -> void:
		for frame in ATLAS.FRAMES:
			var center := (Vector2(frame % ATLAS.COLUMNS, frame / ATLAS.COLUMNS) + Vector2.ONE * 0.5) * cell
			draw_set_transform(center, 0.0, Vector2.ONE * (float(cell) / ATLAS.BOUNDS.size.x))
			var phase := float(frame) * TAU / float(ATLAS.FRAMES)
			if layer == "front":
				VISUAL._accessories(self, definition.id, definition.fur_color, definition.accent_color, sin(phase), definition.species == "cat", false)
			else:
				VISUAL.paint_body(self, StringName(definition.species), definition.id, definition.fur_color, definition.accent_color, 0.0, phase, StringName(layer))
		draw_set_transform(Vector2.ZERO)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/heroes")
	var definitions: Array[CharacterDefinition] = []
	definitions.append_array(CATALOG.CATS)
	definitions.append_array(CATALOG.DOGS)
	for species in ["cat", "dog"]:
		var menu := CharacterDefinition.new()
		menu.species = species
		menu.id = &"classic" if species == "cat" else &"jumper"
		menu.fur_color = Color("efab63") if species == "cat" else Color("d0a079")
		menu.accent_color = Color("cb7051") if species == "cat" else Color("507f78")
		menu.set_meta("atlas_cell", 256)
		definitions.append(menu)
	for definition in definitions:
		var layers: Array[String] = ["idle", "front"]
		if definition.species == "cat":
			layers.append_array(["aim", "fly"])
		for layer in layers:
			if not await _save(definition, layer):
				quit(1)
				return
		print("Hero atlas saved: %s/%s" % [definition.species, definition.id])
	quit()


func _save(definition: CharacterDefinition, layer: String) -> bool:
	var viewport := SubViewport.new()
	var cell: int = definition.get_meta("atlas_cell", ATLAS.CELL)
	viewport.size = Vector2i(ATLAS.COLUMNS, ATLAS.FRAMES / ATLAS.COLUMNS) * cell
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var sheet := Sheet.new()
	sheet.definition = definition
	sheet.layer = layer
	sheet.cell = cell
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
	var path := ATLAS.path_for(StringName(definition.species), definition.id, definition.fur_color, definition.accent_color, layer)
	var saved := image.save_png(path) == OK
	viewport.queue_free()
	await process_frame
	return saved
