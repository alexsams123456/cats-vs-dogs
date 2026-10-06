class_name LevelData
extends RefCounted
## Только поля уровня: общий JSON-контракт восстановления и обмена.


static func to_dictionary(level: LevelDefinition, include_completion: bool = true) -> Dictionary:
	var data := {
		"title": level.title, "shots": level.shots,
		"biome": level.biome,
		"dog_positions": _write_vectors(level.dog_positions),
		"block_positions": _write_vectors(level.block_positions),
		"weight_positions": _write_vectors(level.weight_positions),
		"block_sizes": _write_vectors(level.block_sizes),
		"block_materials": Array(level.block_materials),
		"dog_house_materials": Array(level.dog_house_materials),
		"dog_house_types": Array(level.dog_house_types),
		"cat_sequence": Array(level.cat_sequence),
		"dog_kinds": Array(level.dog_kinds),
		"tutorial": String(level.tutorial), "par_shots": level.par_shots,
	}
	if include_completion and level.is_author_completed():
		data["author_completion"] = level.author_completion.duplicate(true)
	return data


static func from_dictionary(data: Dictionary, editable: bool = false) -> LevelDefinition:
	if not data.get("title") is String or String(data.title).length() > 1024:
		return null
	if not _is_integer(data.get("shots")) or not _is_integer(data.get("par_shots", 0)):
		return null
	if not data.get("tutorial", "") is String:
		return null
	if not data.get("biome", "backyard") is String:
		return null
	var level := LevelDefinition.new()
	level.title = data.title
	level.biome = data.get("biome", "backyard")
	level.shots = int(data.shots)
	level.par_shots = int(data.get("par_shots", 0))
	level.tutorial = StringName(data.get("tutorial", ""))
	for key: String in ["dog_positions", "block_positions", "block_sizes"]:
		var vectors: Variant = _read_vectors(data.get(key))
		if vectors == null:
			return null
		level.set(key, vectors)
	var weights: Variant = _read_vectors(data.get("weight_positions", []))
	if weights == null:
		return null
	level.weight_positions = weights
	for key: String in ["block_materials", "dog_house_materials", "dog_house_types", "cat_sequence", "dog_kinds"]:
		var strings: Variant = _read_strings(data.get(key, []))
		if strings == null:
			return null
		level.set(key, strings)
	if not (_is_editable(level) if editable else level.is_valid()):
		return null
	level.normalize_materials()
	if data.get("author_completion") is Dictionary:
		level.author_completion = data.author_completion.duplicate(true)
		if not level.is_author_completed():
			level.author_completion.clear()
	return level


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
