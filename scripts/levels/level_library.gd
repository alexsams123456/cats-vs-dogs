class_name LevelLibrary
extends RefCounted
## Пользовательские уровни хранятся отдельно от ресурсов игры.

const DIRECTORY: String = "user://levels"
const BUILTIN_DIRECTORY: String = "res://levels"


static func list_levels() -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	var directory := DirAccess.open(DIRECTORY)
	if directory == null:
		return levels
	for file_name in directory.get_files():
		var path: String = DIRECTORY.path_join(file_name)
		var level := load_level(path)
		if level != null:
			levels.append({"path": path, "title": level.title, "level": level})
	levels.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var comparison: int = String(first["title"]).naturalnocasecmp_to(String(second["title"]))
		if comparison == 0:
			return String(first["path"]) < String(second["path"])
		return comparison < 0
	)
	return levels


static func save_level(level: LevelDefinition, path: String = "") -> Dictionary:
	if level == null or not level.is_valid():
		return {"error": ERR_INVALID_DATA, "path": path}
	if not path.is_empty() and not _is_level_path(path, DIRECTORY):
		return {"error": ERR_INVALID_PARAMETER, "path": path}
	var error: Error = DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK:
		return {"error": error, "path": path}
	if path.is_empty():
		path = _unique_path("level")
	var temporary_path := _unique_path(".saving")
	# Замена выполняется только после полной записи, сохраняя предыдущую версию при ошибке.
	var snapshot := level.duplicate(true) as LevelDefinition
	error = ResourceSaver.save(snapshot, temporary_path)
	if error == OK:
		error = DirAccess.rename_absolute(temporary_path, path)
	if error != OK and FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	return {"error": error, "path": path}


static func load_level(path: String) -> LevelDefinition:
	if not _is_level_path(path, DIRECTORY) and not _is_level_path(path, BUILTIN_DIRECTORY):
		return null
	if not FileAccess.file_exists(path):
		return null
	var level := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelDefinition
	if level == null or not level.is_valid():
		return null
	return level.duplicate(true) as LevelDefinition


static func _is_level_path(path: String, directory: String) -> bool:
	if not path.begins_with(directory + "/"):
		return false
	var file_name: String = path.trim_prefix(directory + "/")
	return (not file_name.begins_with(".") and file_name.ends_with(".tres")
		and file_name.length() > 5 and not file_name.contains("/")
		and not file_name.contains("\\") and not file_name.contains(":"))


static func _unique_path(prefix: String) -> String:
	var suffix: String = "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var path: String = DIRECTORY.path_join("%s_%s.tres" % [prefix, suffix])
	var attempt: int = 0
	while FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
		attempt += 1
		path = DIRECTORY.path_join("%s_%s_%d.tres" % [prefix, suffix, attempt])
	return path
