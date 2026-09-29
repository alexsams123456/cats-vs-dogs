extends SceneTree
## Проверка данных и сохранения уровней с очисткой только собственных файлов.

const BUILTIN_PATH: String = "res://levels/level_01.tres"

var _failures: int = 0
var _checks: int = 0
var _created_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_validation()
	_test_storage()
	for path in _created_paths:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(path) == OK, "Тестовый файл удалён")
	print("Level library checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_validation() -> void:
	var original := LevelLibrary.load_level(BUILTIN_PATH)
	_check(original != null and original.is_valid(), "Встроенный уровень проходит проверку")
	if original == null:
		return
	var level := original.duplicate(true) as LevelDefinition
	level.shots = 0
	_check(not level.is_valid(), "Нулевое число выстрелов отклоняется")
	level.shots = 21
	_check(not level.is_valid(), "Число выстрелов ограничено сверху")
	level.shots = 20
	_check(level.is_valid(), "Верхняя граница числа выстрелов допустима")
	level.shots = 1
	_check(level.is_valid(), "Нижняя граница числа выстрелов допустима")
	level.title = " \t\n"
	_check(not level.is_valid(), "Пустое название отклоняется")
	level = original.duplicate(true) as LevelDefinition
	level.dog_positions.clear()
	_check(not level.is_valid(), "Уровень без целей отклоняется")
	level = original.duplicate(true) as LevelDefinition
	level.block_sizes.remove_at(0)
	_check(not level.is_valid(), "Позиции и размеры блоков должны соответствовать")
	level = original.duplicate(true) as LevelDefinition
	level.dog_positions[0] = Vector2(NAN, 100.0)
	_check(not level.is_valid(), "Позиция цели с NaN отклоняется")
	level = original.duplicate(true) as LevelDefinition
	level.block_positions[0] = Vector2(100.0, INF)
	_check(not level.is_valid(), "Бесконечная позиция блока отклоняется")
	level = original.duplicate(true) as LevelDefinition
	level.block_sizes[0] = Vector2(NAN, 100.0)
	_check(not level.is_valid(), "Размер блока с NaN отклоняется")
	level.block_sizes[0] = Vector2(100.0, INF)
	_check(not level.is_valid(), "Бесконечный размер блока отклоняется")
	level.block_sizes[0] = Vector2(0.0, 100.0)
	_check(not level.is_valid(), "Нулевой размер блока отклоняется")
	level.block_sizes[0] = Vector2(100.0, -1.0)
	_check(not level.is_valid(), "Отрицательный размер блока отклоняется")
	level = original.duplicate(true) as LevelDefinition
	level.dog_house_materials.clear()
	level.dog_house_types.clear()
	level.block_materials.clear()
	level.dog_positions.resize(LevelDefinition.MAX_OBJECTS + 1)
	_check(not level.is_valid(), "Слишком много целей отклоняется")
	level.dog_positions.resize(LevelDefinition.MAX_OBJECTS)
	_check(level.is_valid(), "Граница числа целей допустима")
	level.block_positions.resize(LevelDefinition.MAX_OBJECTS + 1)
	level.block_sizes.resize(LevelDefinition.MAX_OBJECTS + 1)
	level.block_sizes.fill(Vector2(20.0, 20.0))
	_check(not level.is_valid(), "Слишком много блоков отклоняется")
	level.block_positions.resize(LevelDefinition.MAX_OBJECTS)
	level.block_sizes.resize(LevelDefinition.MAX_OBJECTS)
	_check(level.is_valid(), "Граница числа блоков допустима")


func _test_storage() -> void:
	var original := LevelLibrary.load_level(BUILTIN_PATH)
	if original == null:
		return
	var builtin_hash: String = FileAccess.get_sha256(BUILTIN_PATH)
	var level := original.duplicate(true) as LevelDefinition
	level.title = "Проверка сохранения"
	var saved: Dictionary = LevelLibrary.save_level(level)
	_check(saved["error"] == OK, "Новый пользовательский уровень сохраняется")
	if saved["error"] != OK:
		return
	var first_path: String = saved["path"]
	_created_paths.append(first_path)
	_check(first_path.begins_with(LevelLibrary.DIRECTORY + "/"), "Новый файл находится в папке пользователя")
	var first := LevelLibrary.load_level(first_path)
	_check(_same_layout(level, first), "Загрузка сохраняет название, выстрелы и геометрию")
	if first == null:
		return
	first.dog_positions[0] = Vector2(321.0, 456.0)
	first.block_sizes[0] = Vector2(77.0, 66.0)
	first.title = "Изменённая копия"
	var second := LevelLibrary.load_level(first_path)
	_check(_same_layout(level, second), "Загрузки независимы друг от друга")
	_check(_same_layout(original, LevelLibrary.load_level(BUILTIN_PATH)), "Правка копии не затрагивает встроенный ресурс")
	saved = LevelLibrary.save_level(first, first_path)
	_check(saved["error"] == OK and saved["path"] == first_path, "Повторное сохранение заменяет тот же файл")
	_check(_same_layout(first, LevelLibrary.load_level(first_path)), "Загрузка после замены обходит старый кеш")
	_check(_same_layout(level, second), "Сохранение не меняет уже загруженную копию")
	saved = LevelLibrary.save_level(level)
	_check(saved["error"] == OK and saved["path"] != first_path, "Сохранение копии создаёт уникальный путь")
	if saved["error"] == OK:
		_created_paths.append(saved["path"])
	var found_paths: Array[String] = []
	for entry in LevelLibrary.list_levels():
		found_paths.append(entry["path"])
		if entry["path"] == first_path:
			_check(entry["title"] == first.title, "Список показывает сохранённое название")
	_check(found_paths.has(first_path) and found_paths.has(saved["path"]), "Список содержит оба сохранённых уровня")
	var invalid := original.duplicate(true) as LevelDefinition
	invalid.shots = 0
	_check(LevelLibrary.save_level(invalid, first_path)["error"] == ERR_INVALID_DATA, "Некорректные данные не сохраняются")
	_check(_same_layout(first, LevelLibrary.load_level(first_path)), "Неудачная запись сохраняет предыдущую версию")
	_check(LevelLibrary.save_level(null)["error"] == ERR_INVALID_DATA, "Отсутствующий ресурс отклоняется")
	var rejected_paths: Array[String] = [
		BUILTIN_PATH, "user://outside.tres", "user://levels/../outside.tres",
		"user://levels/..\\outside.tres", "user://levels/sub/level.tres",
		"user://levels/name.tres:stream", "user://levels/name.res", "user://levels/.hidden.tres",
	]
	for path in rejected_paths:
		_check(LevelLibrary.save_level(level, path)["error"] == ERR_INVALID_PARAMETER,
			"Запись за пределами разрешённых файлов отклоняется: " + path)
	_check(FileAccess.get_sha256(BUILTIN_PATH) == builtin_hash, "Встроенный файл не перезаписан")
	_check(LevelLibrary.load_level("user://levels/../outside.tres") == null, "Загрузка отклоняет выход из папки")
	_check(LevelLibrary.load_level("user://levels/missing_%d.tres" % Time.get_ticks_usec()) == null,
		"Отсутствующий файл не загружается")
	var invalid_path: String = LevelLibrary.DIRECTORY.path_join("test_invalid_%d.tres" % Time.get_ticks_usec())
	_created_paths.append(invalid_path)
	_check(ResourceSaver.save(invalid, invalid_path) == OK, "Создан некорректный ресурс для проверки загрузки")
	_check(LevelLibrary.load_level(invalid_path) == null, "Загрузка проверяет данные ресурса")
	var unrelated_path: String = LevelLibrary.DIRECTORY.path_join("test_unrelated_%d.tres" % Time.get_ticks_usec())
	_created_paths.append(unrelated_path)
	_check(ResourceSaver.save(Resource.new(), unrelated_path) == OK, "Создан ресурс другого типа для проверки")
	_check(LevelLibrary.load_level(unrelated_path) == null, "Ресурс другого типа не становится уровнем")
	var invalid_listed: bool = false
	for entry in LevelLibrary.list_levels():
		invalid_listed = invalid_listed or entry["path"] in [invalid_path, unrelated_path]
	_check(not invalid_listed, "Список скрывает некорректные ресурсы")


func _same_layout(first: LevelDefinition, second: LevelDefinition) -> bool:
	return (first != null and second != null and first.title == second.title
		and first.shots == second.shots and first.dog_positions == second.dog_positions
		and first.block_positions == second.block_positions and first.block_sizes == second.block_sizes
		and first.block_materials == second.block_materials and first.dog_house_materials == second.dog_house_materials
		and first.dog_house_types == second.dog_house_types)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
