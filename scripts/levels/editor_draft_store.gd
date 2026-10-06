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
		"level": LevelData.to_dictionary(level),
	}
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "", true, true))
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
	var level := LevelData.from_dictionary(document.level, true)
	if level == null:
		return {}
	return {"level": level, "current_path": _safe_level_path(document.get("current_path", "")), "dirty": document.get("dirty", true)}


static func _safe_level_path(value: String) -> String:
	return value if LevelLibrary._is_level_path(value, LevelLibrary.DIRECTORY) else ""


static func _is_editable(level: LevelDefinition) -> bool:
	return LevelData._is_editable(level)
