extends RefCounted
## Two sprite layers leave expressions, blinking, sound and effects on live clocks.

const FRAMES: int = 64
const COLUMNS: int = 8
const CELL: int = 192
const BOUNDS := Rect2(-48, -48, 96, 96)
const CACHE_TARGET: int = 8
static var _textures: Dictionary[String, Texture2D] = {}
static var _last_used: Dictionary[String, int] = {}


static func pose(species: StringName, expression: StringName, front: bool) -> String:
	if front:
		return "front"
	if species == &"cat":
		if expression == &"aim":
			return "aim"
		if expression == &"fly" or expression == &"meow":
			return "fly"
	return "idle"


static func path_for(species: StringName, kind: StringName, fur: Color, accent: Color, layer: String) -> String:
	return "res://assets/heroes/%s_%s_%s_%s_%s.png" % [species, kind, fur.to_html(), accent.to_html(), layer]


static func frame_for(time: float, phase: float) -> int:
	return int(floor(fposmod(time * 2.8 + phase, TAU) * float(FRAMES) / TAU)) % FRAMES


static func prepare(definition: CharacterDefinition) -> void:
	var layers: Array[String] = ["idle", "front"]
	if definition.species == "cat":
		layers.append_array(["aim", "fly"])
	for layer in layers:
		var path := path_for(StringName(definition.species), definition.id, definition.fur_color, definition.accent_color, layer)
		if not _textures.has(path) and ResourceLoader.exists(path):
			_prune()
			_textures[path] = load(path) as Texture2D
			_last_used[path] = Engine.get_process_frames()


static func paint_layer(canvas: CanvasItem, species: StringName, kind: StringName, fur: Color, accent: Color, time: float, phase: float, expression: StringName, front: bool) -> bool:
	var path := path_for(species, kind, fur, accent, pose(species, expression, front))
	if not _textures.has(path):
		if not ResourceLoader.exists(path):
			return false
		_prune()
		_textures[path] = load(path) as Texture2D
	_last_used[path] = Engine.get_process_frames()
	var frame := frame_for(time, phase)
	var cell := float(_textures[path].get_width()) / COLUMNS
	var source := Rect2(Vector2(frame % COLUMNS, frame / COLUMNS) * cell, Vector2.ONE * cell)
	canvas.draw_texture_rect_region(_textures[path], BOUNDS, source)
	return true


static func _prune() -> void:
	if _textures.size() < CACHE_TARGET:
		return
	# Artwork redraws at 30 Hz, even on 144/240 Hz displays. Keep recent layers.
	var previous_frame := Engine.get_process_frames() - 120
	for path: String in _textures.keys():
		if _last_used.get(path, -1) < previous_frame:
			_textures.erase(path)
			_last_used.erase(path)
