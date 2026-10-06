extends SceneTree
## Обмен всеми полями, повреждённый ввод и сохранение независимых копий.

var _checks: int = 0
var _failures: int = 0
var _paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for resource: LevelDefinition in CampaignCatalog.LEVELS:
		var original := resource.duplicate(true) as LevelDefinition
		original.normalize_materials()
		var code := LevelExchange.encode(original)
		_check(not code.is_empty(), "Каждый двор имеет переносимый код")
		_check(_same(original, LevelExchange.decode(code)), "Код сохраняет все поля кампании")
		_check(_same(original, LevelExchange.decode(" \n" + code.substr(0, 5) + "\n\t" + code.substr(5) + "\n")), "Перенос строки в сообщении разрешён")
		_check(_same(original, LevelExchange.parse_document(LevelExchange.document(original))), "Файл сохраняет все поля кампании")
	var level := CampaignCatalog.LEVELS[8].duplicate(true) as LevelDefinition
	level.title = "Двор друга 🐈 · 友達"
	level.normalize_materials()
	_check(_same(level, LevelExchange.decode(LevelExchange.encode(level))), "Пользовательское имя с Unicode сохраняется")
	for code: String in ["", "не код", "CVD2:AAAA", "CVD1:", "CVD1:!AAA", "CVD1:====", "CVD1:AA=A", "CVD1:AAAA", "CVD1:A", "x".repeat(LevelExchange.MAX_CODE_LENGTH + 1)]:
		_check(LevelExchange.decode(code) == null, "Неверный код отклонён")
	_check(LevelExchange.decode("CVD1:" + Marshalls.raw_to_base64(PackedByteArray([0xff, 0xfe, 0xfd]))) == null, "Неверный UTF-8 отклонён без ошибок движка")
	var huge := "x".repeat(LevelExchange.MAX_BYTES + 1).to_utf8_buffer()
	_check(LevelExchange.decode(LevelExchange.PREFIX + Marshalls.raw_to_base64(huge)) == null, "Декодирование ограничено по размеру")
	var document: Dictionary = JSON.parse_string(LevelExchange.document(level))
	for mutation: Dictionary in [{"version": 2}, {"version": true}, {"format": "other"}, {"format": false}, {"level": []}, {"script": "res://evil.gd"}]:
		var changed := document.duplicate(true)
		changed.merge(mutation, true)
		_check(LevelExchange.parse_document(JSON.stringify(changed)) == null, "Неизвестная версия или поле файла отклонены")
	for mutation: Dictionary in [{"shots": 1.5}, {"shots": true}, {"shots": 21}, {"par_shots": 5}, {"title": ""}, {"title": "x".repeat(1025)}, {"dog_positions": []}, {"block_sizes": [[0, 20]]}, {"weight_positions": [["x", 20]]}, {"biome": "other"}, {"cat_sequence": ["unknown"]}, {"dog_kinds": ["unknown"]}, {"block_materials": ["unknown"]}, {"script": "res://evil.gd"}, {"current_path": "user://levels/old.tres"}]:
		var changed := document.duplicate(true)
		changed.level.merge(mutation, true)
		_check(LevelExchange.parse_document(JSON.stringify(changed)) == null, "Неверные поля и скрипты уровня отклонены")
	for text: String in ["[]", "null", "{}", "[gd_resource type=\"Resource\"]", "{".repeat(LevelExchange.MAX_BYTES + 1)]:
		_check(LevelExchange.parse_document(text) == null, "Импорт читает только ограниченный документ уровня")
	var file_path := "user://exchange_test_%d.cvdlevel" % Time.get_ticks_usec()
	_paths.append(file_path)
	_check(LevelExchange.write_file(level, file_path) == OK, "Экспорт файла")
	_check(_same(level, LevelExchange.read_file(file_path)), "Импорт экспортированного файла")
	_check(LevelExchange.read_file(file_path + ".missing") == null, "Нет файла — нет уровня")
	var hash := FileAccess.get_sha256(file_path)
	_check(LevelExchange.write_file(LevelDefinition.new(), file_path) == ERR_INVALID_DATA and FileAccess.get_sha256(file_path) == hash, "Неверный черновик не перезаписывает файл")
	var bad_file_path := file_path + ".invalid"
	_paths.append(bad_file_path)
	var file := FileAccess.open(bad_file_path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0xff, 0xfe, 0xfd]))
	file.close()
	_check(LevelExchange.read_file(bad_file_path) == null, "Файл с неверным UTF-8 отклонён без ошибок движка")
	file = FileAccess.open(bad_file_path, FileAccess.WRITE)
	file.store_buffer(huge)
	file.close()
	_check(LevelExchange.read_file(bad_file_path) == null, "Размер файла проверяется до разбора")
	var first := LevelLibrary.save_level(level)
	var second := LevelLibrary.save_level(LevelExchange.read_file(file_path))
	_paths.append(first.path)
	_paths.append(second.path)
	_check(first.error == OK and second.error == OK and first.path != second.path, "Повторный импорт добавляет отдельную копию")
	var copy := LevelLibrary.load_level(second.path)
	copy.title = "Изменённая копия"
	_check(LevelLibrary.save_level(copy, second.path).error == OK, "Импортированную копию можно редактировать")
	_check(LevelLibrary.load_level(first.path).title == level.title, "Исходный двор не изменяется")
	await _editor(level)
	for path in _paths:
		DirAccess.remove_absolute(path)
	print("Level exchange checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _editor(level: LevelDefinition) -> void:
	var editor := preload("res://scenes/editor/level_editor.tscn").instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	await _settle()
	editor._show_exchange()
	await _settle()
	var dialog := editor.exchange_dialog
	_check(dialog.visible and not dialog.code_edit.editable and LevelExchange.decode(dialog.code_edit.text) != null, "Обмен текущим черновиком без предварительного сохранения")
	var old := editor.draft
	dialog.import_button.pressed.emit()
	await _settle()
	_check(dialog.code_edit.editable and dialog.add_button.disabled, "Импорт начинается без чтения буфера обмена")
	dialog.code_edit.text = "ошибка"
	dialog._validate_code()
	_check(dialog.add_button.disabled and editor.draft == old, "Повреждённый ввод сохраняет черновик")
	dialog.code_edit.text = LevelExchange.encode(level)
	dialog._validate_code()
	_check(not dialog.add_button.disabled and dialog.summary.text.contains(level.title) and editor.draft == old, "Предпросмотр до импорта")
	dialog.hide()
	editor._on_title_changed("Несохранённый двор")
	editor._finish_edit()
	var before := LevelLibrary.list_levels().size()
	editor._confirm_import(level)
	await _settle()
	_check(editor._confirm.visible and editor.draft == old and LevelLibrary.list_levels().size() == before, "Подтверждение предшествует записи и замене черновика")
	editor._confirm.get_cancel_button().pressed.emit()
	await _settle()
	_check(editor.draft == old and LevelLibrary.list_levels().size() == before, "Отмена не добавляет файл")
	editor._confirm_import(level)
	await _settle()
	editor._confirm.get_ok_button().pressed.emit()
	await _settle()
	_paths.append(editor.current_path)
	_check(_same(editor.draft, level) and not editor.is_dirty() and LevelLibrary.list_levels().size() == before + 1, "Импорт создаёт сохранённую локальную копию и открывает её")
	editor._show_exchange()
	await _settle()
	dialog._show_import()
	dialog.file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog._file_selected(_paths[0])
	_check(not dialog.add_button.disabled and _same(dialog._incoming, level), "Выбор файла заполняет предпросмотр")
	dialog._file_selected(_paths[0] + ".missing")
	_check(dialog.add_button.disabled and not dialog.message.text.is_empty(), "Неудачный выбор очищает устаревший предпросмотр")
	dialog._show_share()
	dialog.file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog._file_selected(_paths[0])
	_check(_same(LevelExchange.read_file(_paths[0]), editor.draft) and not dialog.message.text.is_empty(), "Кнопка экспорта передаёт текущий двор в выбранный файл")
	editor.new_level()
	editor._show_exchange()
	await _settle()
	_check(not dialog._sharing and dialog.add_button.disabled, "Пустой двор открывает импорт")
	dialog._show_share()
	_check(dialog.copy_button.disabled and dialog.save_button.disabled, "Незавершённый двор нельзя отправить")
	editor.queue_free()
	await _settle()


func _same(first: LevelDefinition, second: LevelDefinition) -> bool:
	return first != null and second != null and LevelData.to_dictionary(first) == LevelData.to_dictionary(second)


func _settle() -> void:
	for frame in 5:
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
