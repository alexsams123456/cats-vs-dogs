extends SceneTree
## Биом проходит через ресурсы, черновики, историю редактора и игровой раунд.

const GAME_SCENE := preload("res://scenes/main.tscn")
const EDITOR_SCENE := preload("res://scenes/editor/level_editor.tscn")
const LEGACY_LEVEL := preload("res://levels/level_01.tres")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(LEGACY_LEVEL.biome == "backyard" and LEGACY_LEVEL.is_valid(), "Old resources default to the backyard")
	var level := LEGACY_LEVEL.duplicate(true) as LevelDefinition
	level.biome = "unknown"
	_check(not level.is_valid(), "Unknown environments cannot be saved or played")
	var path := "user://biome_test_%d.json" % Time.get_ticks_usec()
	var store := EditorDraftStore.new(path)
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	editor.recovery_path = ""
	root.add_child(editor)
	var music_playbacks: Array[WeakRef] = []
	for biome: StringName in LevelDefinition.BIOMES:
		level.biome = String(biome)
		_check(level.is_valid(), "Authored environment is valid: " + String(biome))
		var saved := LevelLibrary.save_level(level)
		_check(saved.error == OK, "Environment saves in a user resource")
		if saved.error == OK:
			var restored := LevelLibrary.load_level(saved.path)
			_check(restored != null and restored.biome == String(biome), "Explicit save/load retains environment")
			DirAccess.remove_absolute(saved.path)
		_check(store.save_draft(level, "", true) == OK, "Environment saves in the recovery draft")
		var recovered := store.load_draft()
		_check(not recovered.is_empty() and recovered.level.biome == String(biome), "Recovery retains environment")
		editor._replace_draft(level.duplicate(true) as LevelDefinition, "")
		var backdrop := editor.canvas._backdrop
		_check(String(backdrop.get("biome")) == String(biome), "Editor previews the resource environment")
		var time_before: float = backdrop.get("animation_time")
		await create_timer(0.04).timeout
		_check(is_equal_approx(float(backdrop.get("animation_time")), time_before), "Editor landscape stays still")
		editor._begin_edit()
		editor.draft.title += " test"
		editor._finish_edit()
		editor.undo()
		_check(editor.draft.biome == String(biome), "Undo retains environment")
		editor.redo()
		_check(editor.draft.biome == String(biome), "Redo retains environment")
		var game := GAME_SCENE.instantiate() as GameRound
		game.level = level.duplicate(true) as LevelDefinition
		root.add_child(game)
		music_playbacks.append(weakref(game.background_music.get_stream_playback()))
		_check(String(game.get_node("Backdrop").get("biome")) == String(biome), "Round uses the same environment as the editor")
		game.queue_free()
		await process_frame
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	document.level.erase("biome")
	_write_document(path, document)
	var legacy := store.load_draft()
	_check(not legacy.is_empty() and legacy.level.biome == "backyard", "Old recovery documents use the backyard")
	for invalid: Variant in ["unknown", 42, null, []]:
		document.level.biome = invalid
		_write_document(path, document)
		_check(store.load_draft().is_empty(), "Invalid draft environments are rejected")
	DirAccess.remove_absolute(path)
	editor.queue_free()
	await process_frame
	# Удалённые раунды освобождают свои аудиопотоки на отдельном такте микшера.
	var audio_deadline := Time.get_ticks_msec() + 1000
	for playback: WeakRef in music_playbacks:
		while playback.get_ref() != null and Time.get_ticks_msec() < audio_deadline:
			await create_timer(0.025, true, false, true).timeout
		_check(playback.get_ref() == null, "Removed biome round releases its music playback")
	print("Biome checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _write_document(path: String, document: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
