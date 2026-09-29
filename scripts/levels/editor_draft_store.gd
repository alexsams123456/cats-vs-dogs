class_name EditorDraftStore
extends RefCounted
## Независимая копия незавершённого двора; JSON не загружает ресурсы или скрипты.

const DEFAULT_PATH: String = "user://editor_draft.json"
const MAX_BYTES: int = 2 * 1024 * 1024

var path: String


func _init(storage_path: String = DEFAULT_PATH) -> void:
	path = storage_path


func save_draft(level: LevelDefinition, current_path: String, dirty: bool) -> Error:
	if path.is_empty():
		return OK
	if not _is_editable(level):
		return ERR_INVALID_DATA
	var document := {
		"version": 1,
		"current_path": _safe_level_path(current_path),
		"dirty": dirty,
		"level": {
			"title": level.title, "shots": level.shots,
			"biome": level.biome,
			"dog_positions": _write_vectors(level.dog_positions),
			"block_positions": _write_vectors(level.block_positions),
			"block_sizes": _write_vectors(level.block_sizes),
			"block_materials": Array(level.block_materials),
			"dog_house_materials": Array(level.dog_house_materials),
			"dog_house_types": Array(level.dog_house_types),
			"cat_sequence": Array(level.cat_sequence),
			"dog_kinds": Array(level.dog_kinds),
			"tutorial": String(level.tutorial), "par_shots": level.par_shots,
		},
	}
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK and FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	return error


func load_draft() -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var document: Dictionary = parser.data
	if document.get("version") != 1 or not document.get("level") is Dictionary:
		return {}
	if not document.get("current_path", "") is String or not document.get("dirty", true) is bool:
		return {}
	var data: Dictionary = document.level
	if not data.get("title") is String or String(data.title).length() > 1024:
		return {}
	if not _is_integer(data.get("shots")) or not _is_integer(data.get("par_shots", 0)):
		return {}
	if not data.get("tutorial", "") is String:
		return {}
	if not data.get("biome", "backyard") is String:
		return {}
	var level := LevelDefinition.new()
	level.title = data.title
	level.biome = data.get("biome", "backyard")
	level.shots = int(data.shots)
	level.par_shots = int(data.get("par_shots", 0))
	level.tutorial = StringName(data.get("tutorial", ""))
	for key: String in ["dog_positions", "block_positions", "block_sizes"]:
		var vectors: Variant = _read_vectors(data.get(key))
		if vectors == null:
			return {}
		level.set(key, vectors)
	for key: String in ["block_materials", "dog_house_materials", "dog_house_types", "cat_sequence", "dog_kinds"]:
		var strings: Variant = _read_strings(data.get(key, []))
		if strings == null:
			return {}
		level.set(key, strings)
	if not _is_editable(level):
		return {}
	level.normalize_materials()
	return {"level": level, "current_path": _safe_level_path(document.get("current_path", "")), "dirty": document.get("dirty", true)}


static func _safe_level_path(value: String) -> String:
	return value if LevelLibrary._is_level_path(value, LevelLibrary.DIRECTORY) else ""


static func _is_editable(level: LevelDefinition) -> bool:
	if level == null or level.title.length() > 1024:
		return false
	# Пустые название и двор допустимы в редакторе, остальные контракты сохраняются.
	var candidate := level.duplicate(true) as LevelDefinition
	if candidate.title.strip_edges().is_empty():
		candidate.title = "Черновик"
	if candidate.dog_positions.is_empty():
		if not candidate.dog_house_materials.is_empty() or not candidate.dog_house_types.is_empty() or not candidate.dog_kinds.is_empty():
			return false
		candidate.dog_positions.append(Vector2(800, 550))
	return candidate.is_valid()


static func _write_vectors(values: PackedVector2Array) -> Array:
	var result: Array = []
	for value in values:
		result.append([value.x, value.y])
	return result


static func _read_vectors(value: Variant) -> Variant:
	if not value is Array or value.size() > LevelDefinition.MAX_OBJECTS:
		return null
	var result := PackedVector2Array()
	for pair: Variant in value:
		if not pair is Array or pair.size() != 2:
			return null
		if not _is_number(pair[0]) or not _is_number(pair[1]):
			return null
		var point := Vector2(float(pair[0]), float(pair[1]))
		if not point.is_finite():
			return null
		result.append(point)
	return result


static func _read_strings(value: Variant) -> Variant:
	if not value is Array or value.size() > LevelDefinition.MAX_OBJECTS:
		return null
	var result := PackedStringArray()
	for entry: Variant in value:
		if not entry is String or entry.length() > 128:
			return null
		result.append(entry)
	return result


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _is_integer(value: Variant) -> bool:
	return _is_number(value) and float(value) == floorf(float(value)) and absf(float(value)) <= 2147483647.0
