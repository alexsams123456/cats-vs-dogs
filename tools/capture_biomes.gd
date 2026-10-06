extends SceneTree
## Графический прогон трёх глав: постройки, ввод и неподвижность декора на паузе.

const GAME_SCENE := preload("res://scenes/main.tscn")
const EDITOR_SCENE := preload("res://scenes/editor/level_editor.tscn")
const BACKDROP := preload("res://scripts/world/backdrop.gd")
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]
const MIN_CHANGED_PIXEL_FRACTION: float = 0.002

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для снимков нужен графический запуск без --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	GameLocalization.apply_locale("ru")
	for window_size: Vector2i in WINDOW_SIZES:
		root.size = window_size
		for index in CampaignCatalog.LEVELS.size():
			var game := _round(index)
			await create_timer(1.2).timeout
			_check(game.dogs_left == game.level.dog_positions.size(), "%s: targets survive construction settling" % game.level.title)
			_check(_block_count(game) == game.level.block_positions.size(), "%s: building parts survive before the first shot" % game.level.title)
			await _capture("level-%02d" % (index + 1))
			if window_size == WINDOW_SIZES[2]:
				await _shot(game, index % 2 == 1)
			game.queue_free()
			await process_frame
		for index in [0, 2, 4]:
			var editor := EDITOR_SCENE.instantiate() as LevelEditor
			editor.recovery_path = ""
			root.add_child(editor)
			editor._replace_draft(CampaignCatalog.LEVELS[index].duplicate(true) as LevelDefinition, "")
			await create_timer(0.1).timeout
			var editor_backdrop: Node2D = editor.canvas._backdrop
			var editor_time: float = editor_backdrop.get("animation_time")
			await _capture("editor-" + editor.draft.biome)
			await create_timer(0.3).timeout
			_check(editor_backdrop.process_mode == Node.PROCESS_MODE_DISABLED, "Editor disables backdrop processing")
			_check(is_equal_approx(float(editor_backdrop.get("animation_time")), editor_time), "Editor backdrop remains still")
			editor.queue_free()
			await process_frame
		for biome: StringName in [&"backyard", &"mountain", &"glacier"]:
			await _landscape(biome)
	print("Biome previews: %d passed, %d failed. Images: .artifacts/biome-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _round(index: int) -> GameRound:
	var game := GAME_SCENE.instantiate() as GameRound
	game.level = CampaignCatalog.LEVELS[index].duplicate(true) as LevelDefinition
	game.campaign_mode = true
	game.has_next_level = index + 1 < CampaignCatalog.LEVELS.size()
	root.add_child(game)
	return game


func _block_count(game: GameRound) -> int:
	var count: int = 0
	for actor in game.actors.get_children():
		if actor is WoodenBlock and not actor is DogHouse and not actor.is_destroyed:
			count += 1
	return count


func _shot(game: GameRound, touch: bool) -> void:
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	var cat := game.slingshot.loaded_projectile
	var shots: int = game.shots_left
	_press(anchor, true, touch)
	_press(anchor + Vector2(-92, 38), false, touch)
	_check(cat.was_launched and game.shots_left == shots - 1, "Touch or mouse launches exactly one cat")
	await create_timer(0.35).timeout
	await _capture("shot-" + game.level.biome + ("-touch" if touch else "-mouse"))
	game.set_paused(true)
	var backdrop := game.get_node("Backdrop")
	var stopped: float = backdrop.get("animation_time")
	await create_timer(0.08, true).timeout
	_check(is_equal_approx(stopped, float(backdrop.get("animation_time"))), "Pause freezes biome animation")
	game.set_paused(false)
	await create_timer(0.08).timeout
	_check(float(backdrop.get("animation_time")) > stopped, "Resume continues biome animation")


func _press(position: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = position
		event.index = 0
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)


func _landscape(biome: StringName) -> void:
	var world := Node2D.new()
	root.add_child(world)
	var backdrop := BACKDROP.new()
	backdrop.set_biome(biome)
	world.add_child(backdrop)
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	world.add_child(camera)
	camera.make_current()
	await create_timer(0.2).timeout
	var first := await _capture("ambient-" + biome + "-before")
	var first_time: float = backdrop.animation_time
	await create_timer(1.0).timeout
	var second := await _capture("ambient-" + biome + "-after")
	_check(backdrop.animation_time - first_time >= 0.95, "%s: landscape advances for a second" % biome)
	var changed_fraction := _changed_pixel_fraction(first, second)
	_check(changed_fraction >= MIN_CHANGED_PIXEL_FRACTION, "%s: visible ambient movement changes %.3f%% of pixels" % [biome, changed_fraction * 100.0])
	print("Ambient %s %dx%d: %.3f%% of pixels changed in one second" % [biome, root.size.x, root.size.y, changed_fraction * 100.0])
	paused = true
	var stopped: float = backdrop.animation_time
	var frozen := await _capture("ambient-" + biome + "-paused")
	await create_timer(0.3, true).timeout
	await RenderingServer.frame_post_draw
	var still_frozen := root.get_texture().get_image()
	_check(is_equal_approx(backdrop.animation_time, stopped), "%s: isolated backdrop clock freezes on pause" % biome)
	_check(frozen.get_data() == still_frozen.get_data(), "%s: every landscape pixel remains unchanged on pause" % biome)
	paused = false
	await create_timer(0.35).timeout
	var resumed := await _capture("ambient-" + biome + "-resumed")
	_check(backdrop.animation_time > stopped, "%s: isolated backdrop clock resumes" % biome)
	_check(frozen.get_data() != resumed.get_data(), "%s: landscape pixels change after resume" % biome)
	# Дальние фазы: полёт/возвращение птицы, путь вагончиков, скольжение и метеор.
	for phase: float in [3.5, 7.0, 10.7]:
		backdrop.animation_time = phase
		await _capture("ambient-%s-phase-%03d" % [biome, int(phase * 10)])
	world.queue_free()
	await process_frame


func _changed_pixel_fraction(first: Image, second: Image) -> float:
	if first.get_size() != second.get_size():
		return 0.0
	first.convert(Image.FORMAT_RGBA8)
	second.convert(Image.FORMAT_RGBA8)
	var first_data := first.get_data()
	var second_data := second.get_data()
	var changed: int = 0
	# Четыре уровня цвета отсеивают едва заметные колебания полупрозрачных деталей.
	for offset in range(0, first_data.size(), 4):
		if absi(first_data[offset] - second_data[offset]) >= 4 or absi(first_data[offset + 1] - second_data[offset + 1]) >= 4 or absi(first_data[offset + 2] - second_data[offset + 2]) >= 4:
			changed += 1
	return float(changed) / float(first.get_width() * first.get_height())


func _capture(label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var path := "res://.artifacts/biome-%s-%dx%d.png" % [label, root.size.x, root.size.y]
	_check(frame.save_png(path) == OK, "Saved " + label)
	return frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
