extends SceneTree
## Восстановление использует только уникальные тестовые файлы.

const EDITOR_SCENE := preload("res://scenes/editor/level_editor.tscn")
const BUILTIN_LEVEL := preload("res://levels/level_01.tres")
const STORE := preload("res://scripts/levels/editor_draft_store.gd")

var _checks: int = 0
var _failures: int = 0
var _paths: Array[String] = []
var _recovery_path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_recovery_path = "user://test_editor_recovery_%d.json" % Time.get_ticks_usec()
	_paths.append(_recovery_path)
	_paths.append(_recovery_path + ".tmp")
	await _test_restore()
	await _test_empty_and_new()
	await _test_save_and_paths()
	await _test_corrupt()
	await _test_rosters_and_history()
	for path in _paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Editor recovery checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_restore() -> void:
	var editor := _open_editor()
	_check(editor.draft.dog_positions == BUILTIN_LEVEL.dog_positions, "Without recovery the editor opens its built-in template")
	_set_title(editor, "Двор после перезапуска")
	editor.shots_input.value = 7
	editor.canvas.material_id = &"glass"
	editor.canvas.house_type = &"barrel"
	editor.canvas.set_tool(LevelCanvas.Tool.DOG_HOUSE)
	editor.canvas._add_object(Vector2(700, 530))
	var expected := editor.draft.duplicate(true) as LevelDefinition
	await create_timer(LevelEditor.AUTOSAVE_DELAY + 0.15).timeout
	var stored: Dictionary = STORE.new(_recovery_path).load_draft()
	_check(not stored.is_empty() and stored.level.title == expected.title, "Edits autosave after the short delay")
	await _close_editor(editor)
	editor = _open_editor()
	_check(editor.draft.title == expected.title and editor.draft.shots == expected.shots, "A new editor instance restores title and shot count")
	_check(editor.draft.dog_positions == expected.dog_positions and editor.draft.block_positions == expected.block_positions, "Recovery restores complete object positions")
	_check(editor.draft.dog_house_types == expected.dog_house_types and editor.draft.dog_house_materials == expected.dog_house_materials, "Recovery preserves shelter types and materials")
	_check(editor.is_dirty() and editor._status.text.contains("восстановлен"), "Recovered unsaved work has a visible notice and remains unsaved")
	_set_title(editor, "Правка перед перетаскиванием")
	editor._finish_edit()
	var original := editor.draft.dog_positions[0]
	editor.canvas._begin(original, LevelCanvas.MOUSE_POINTER)
	editor.canvas.move_selected(original + Vector2(-40, 0))
	var dragged := editor.canvas.selected_position()
	await create_timer(LevelEditor.AUTOSAVE_DELAY + 0.15).timeout
	_check(editor.canvas._pointer == LevelCanvas.MOUSE_POINTER and editor.canvas.selected_position() == dragged, "Autosave waits without interrupting a held drag")
	editor.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	stored = STORE.new(_recovery_path).load_draft()
	_check(editor.canvas._pointer == LevelCanvas.NO_POINTER and stored.level.dog_positions[0] == original, "Focus loss cancels the incomplete drag before saving recovery")
	_set_title(editor, "Правка без потери фокуса поля")
	await create_timer(LevelEditor.AUTOSAVE_DELAY + 0.15).timeout
	stored = STORE.new(_recovery_path).load_draft()
	_check(stored.level.title == editor.draft.title, "Typing saves even before the title field loses focus")
	_set_title(editor, "Сохранить при потере фокуса")
	editor.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	stored = STORE.new(_recovery_path).load_draft()
	_check(stored.level.title == editor.draft.title, "Focus loss flushes pending text changes immediately")
	_set_title(editor, "Сохранить перед закрытием")
	await _close_editor(editor)
	editor = _open_editor()
	_check(editor.draft.title == "Сохранить перед закрытием", "Exiting the tree flushes edits before the autosave timeout")
	await _close_editor(editor)


func _test_empty_and_new() -> void:
	var editor := _open_editor()
	editor.new_level()
	var stored: Dictionary = STORE.new(_recovery_path).load_draft()
	_check(stored.level.dog_positions.is_empty(), "New immediately replaces recovery with the empty yard")
	_set_title(editor, "")
	editor.flush_recovery()
	await _close_editor(editor)
	editor = _open_editor()
	_check(editor.draft.title.is_empty() and editor.draft.dog_positions.is_empty(), "An unfinished empty draft survives restart without resurrecting the old yard")
	_check(editor.save_button.disabled and editor.play_button.disabled, "Recovery does not make an unfinished draft playable or explicitly saveable")
	_set_title(editor, "Сохранить при возврате в меню")
	editor._request_menu()
	stored = STORE.new(_recovery_path).load_draft()
	_check(stored.level.title == editor.draft.title, "Returning to the menu flushes pending edits")
	await _close_editor(editor)


func _test_save_and_paths() -> void:
	var editor := _open_editor()
	editor.open_level("res://levels/level_01.tres")
	_set_title(editor, "Явное сохранение и черновик")
	var level_path := "user://levels/test_recovery_level_%d.tres" % Time.get_ticks_usec()
	_paths.append(level_path)
	editor.current_path = level_path
	editor.save_level()
	_check(FileAccess.file_exists(level_path) and not editor.is_dirty(), "Normal Save writes the requested user level and marks it clean")
	var stored: Dictionary = STORE.new(_recovery_path).load_draft()
	_check(stored.current_path == level_path and not stored.dirty, "Recovery remembers the explicit save destination and clean state")
	_set_title(editor, "Только незавершённый черновик")
	editor.flush_recovery()
	_check(LevelLibrary.load_level(level_path).title == "Явное сохранение и черновик", "Autosave leaves the explicitly saved level unchanged")
	await _close_editor(editor)
	editor = _open_editor()
	_check(editor.current_path == level_path and editor.is_dirty(), "Restoring edits retains their user-level save destination")
	editor.save_level()
	_check(LevelLibrary.load_level(level_path).title == editor.draft.title, "Normal Save after recovery updates the original user level")
	await _close_editor(editor)
	var store := STORE.new(_recovery_path)
	_check(store.save_draft(BUILTIN_LEVEL, "user://../outside.tres", true) == OK, "Recovery can retain a draft without accepting an unsafe destination")
	_check(store.load_draft().current_path.is_empty(), "An unsafe save destination is discarded")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_recovery_path))
	document.current_path = "res://levels/level_01.tres"
	_write_document(JSON.stringify(document))
	_check(store.load_draft().current_path.is_empty(), "A modified recovery file cannot point Save at a bundled resource")
	_check(not FileAccess.file_exists(_recovery_path + ".tmp"), "Successful atomic writes leave no temporary recovery file")


func _test_corrupt() -> void:
	for text: String in ["{unfinished", "[]", '{"version":99,"level":{}}']:
		_write_document(text)
		_check(STORE.new(_recovery_path).load_draft().is_empty(), "Malformed or unsupported recovery is rejected safely")
	var editor := _open_editor()
	_check(editor.draft.title == BUILTIN_LEVEL.title and editor.draft.is_valid(), "A corrupt recovery falls back to a usable built-in template")
	await _close_editor(editor)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_recovery_path))
	document.level.dog_positions = [["wrong", 42]]
	_write_document(JSON.stringify(document))
	_check(STORE.new(_recovery_path).load_draft().is_empty(), "Malformed vector data cannot become an editor object")
	document.level.dog_positions = [[900, 500]]
	document.level.shots = 1.5
	_write_document(JSON.stringify(document))
	_check(STORE.new(_recovery_path).load_draft().is_empty(), "Fractional shot counts are rejected instead of truncated")


func _test_rosters_and_history() -> void:
	var editor := _open_editor()
	var level := BUILTIN_LEVEL.duplicate(true) as LevelDefinition
	level.cat_sequence.resize(level.shots)
	level.cat_sequence.fill(String(CharacterCatalog.CATS[0].id))
	level.dog_kinds.resize(level.dog_positions.size())
	level.dog_kinds.fill(String(CharacterCatalog.DOGS[1].id))
	level.tutorial = &"ability"
	level.biome = "mountain"
	level.par_shots = level.shots
	editor._replace_draft(level, "")
	editor.flush_recovery()
	await _close_editor(editor)
	editor = _open_editor()
	_check(editor.draft.cat_sequence == level.cat_sequence and editor.draft.dog_kinds == level.dog_kinds, "Recovery preserves assigned cat and dog rosters")
	_check(editor.draft.tutorial == &"ability" and editor.draft.par_shots == level.par_shots and editor.draft.biome == "mountain", "Recovery preserves tutorial, scenery and star threshold metadata")
	editor.shots_input.value = 2
	_check(editor.draft.cat_sequence == PackedStringArray(["classic", "classic"]) and editor.draft.par_shots == 2 and editor.draft.is_valid(), "Changing shot count retains remaining cats and adjusts the star threshold")
	editor.undo()
	_check(editor.draft.cat_sequence == level.cat_sequence and editor.draft.par_shots == level.par_shots, "Undo restores the assigned roster with its original shot count")
	editor.canvas.set_tool(LevelCanvas.Tool.DOG)
	editor.canvas._add_object(Vector2(700, 540))
	_check(editor.draft.dog_kinds.size() == level.dog_kinds.size() + 1 and editor.draft.dog_kinds[0] == "armored" and editor.draft.dog_kinds[-1] == "scout" and editor.draft.is_valid(), "Adding a target preserves existing assignments and appends a default dog")
	editor.undo()
	_check(editor.draft.dog_kinds == level.dog_kinds, "Undo restores target assignments")
	_set_title(editor, "История после автосохранения")
	editor._finish_edit()
	editor.flush_recovery()
	editor.undo()
	await create_timer(LevelEditor.AUTOSAVE_DELAY + 0.15).timeout
	var stored: Dictionary = STORE.new(_recovery_path).load_draft()
	_check(stored.level.title == editor.draft.title, "Undo also updates recovery after the autosave delay")
	await _close_editor(editor)


func _open_editor() -> LevelEditor:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	editor.recovery_path = _recovery_path
	root.add_child(editor)
	return editor


func _close_editor(editor: LevelEditor) -> void:
	editor.queue_free()
	await process_frame
	await process_frame


func _set_title(editor: LevelEditor, title: String) -> void:
	editor.title_edit.text = title
	editor.title_edit.text_changed.emit(title)


func _write_document(text: String) -> void:
	var file := FileAccess.open(_recovery_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
