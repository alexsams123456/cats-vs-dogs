extends SceneTree
## Графический прогон кошек на отдельной площадке: мышь, касания, HUD и E.

const CAT_IDS: Array[StringName] = [
	&"classic", &"bomb", &"zigzag", &"splitter", &"heavy",
	&"wind", &"magnet", &"frost", &"ghost", &"homing",
]

var _failures: int = 0
var _pictures: Array[Image] = []


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	await create_timer(0.3).timeout
	for window_size in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = window_size
		_pictures.clear()
		for index in CAT_IDS.size():
			if not OS.get_cmdline_user_args().is_empty() and String(CAT_IDS[index]) not in OS.get_cmdline_user_args():
				continue
			await _capture_kind(app, CAT_IDS[index], index)
		_save_contact_sheet()
	app.queue_free()
	await create_timer(0.2).timeout
	print("Cat preview: %d kinds in 3 window sizes, %d failures" % [_pictures.size(), _failures])
	quit(0 if _failures == 0 else 1)


func _capture_kind(app: GameApp, kind: StringName, index: int) -> void:
	app.selected_cat_id = kind
	app.selected_dog_id = &"scout"
	app.start_editor_game(_demo_level())
	await create_timer(0.9).timeout
	var game := app.game
	game.set_paused(false)
	var cat := game.slingshot.loaded_projectile
	var original_blocks: Array[WeakRef] = []
	for actor: Node in game.actors.get_children():
		if actor is WoodenBlock:
			original_blocks.append(weakref(actor))
	var anchor := game.slingshot.get_global_transform_with_canvas().origin
	var touch_shot: bool = index % 2 == 1
	_pointer(anchor, true, touch_shot)
	_pointer(anchor + Vector2(-95, 42), false, touch_shot)
	if not _check(cat.was_launched and game.shots_left == 3, kind, "выстрел мышью/касанием"):
		return
	# Magnet starts within reach before the projectile can contact a swaying beam.
	var activation_delay := 0.5 if kind == &"magnet" else (0.73 if kind == &"frost" else 0.65)
	await create_timer(activation_delay).timeout
	if kind == &"zigzag":
		_check(not game.hud._ability_button.visible, kind, "пассивная способность без кнопки")
		_check(not cat._trail_points.is_empty(), kind, "видимый волновой след")
	else:
		if not _check(cat.can_activate_ability(), kind, "способность доступна до столкновения"):
			return
		if index % 3 == 0:
			_ability_key()
		else:
			var button := game.hud._ability_button
			var center := button.get_global_rect().get_center()
			_pointer(center, true, index % 3 == 2)
			_pointer(center, false, index % 3 == 2)
		if not _check(cat.ability_spent, kind, "активация кнопкой/E"):
			return
		_check(game.hud._ability_button.disabled, kind, "повторная активация недоступна")
	var effect_delay: float = 0.2 if kind == &"magnet" else (0.18 if kind == &"ghost" else (0.045 if kind == &"heavy" else 0.08))
	await create_timer(effect_delay).timeout
	if kind != &"bomb":
		_check_effect(game, cat, kind, original_blocks)
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := "res://.artifacts/cat-ability-%s-%dx%d.png" % [kind, root.size.x, root.size.y]
	_check(picture.save_png(path) == OK, kind, "сохранён кадр")
	_pictures.append(picture)
	print("Cat preview: %s; shot=%s; ability=%s" % [
		kind, "touch" if touch_shot else "mouse",
		"passive" if kind == &"zigzag" else ("E" if index % 3 == 0 else ("HUD touch" if index % 3 == 2 else "HUD mouse")),
	])
	await create_timer(0.4).timeout


func _demo_level() -> LevelDefinition:
	# Незащищённые цели и дерево позволяют показать мороз, притяжение и порыв.
	var level := LevelDefinition.new()
	level.title = "Площадка способностей"
	level.shots = 4
	level.dog_positions = PackedVector2Array([Vector2(850, 595), Vector2(1080, 595)])
	level.block_positions = PackedVector2Array([Vector2(790, 550), Vector2(960, 550), Vector2(875, 470)])
	level.block_sizes = PackedVector2Array([Vector2(34, 140), Vector2(34, 140), Vector2(204, 20)])
	return level


func _check_effect(game: GameRound, cat: CatProjectile, kind: StringName, original_blocks: Array[WeakRef]) -> void:
	match kind:
		&"splitter":
			var fragments: int = 0
			for actor in game.actors.get_children():
				if actor is CatProjectile:
					fragments += 1
			_check(fragments == 3, kind, "в полёте три кошки")
		&"frost":
			var frozen: bool = false
			for actor in game.actors.get_children():
				if actor is DogTarget and actor.frost_time_left > 0.0:
					frozen = true
			_check(frozen, kind, "собака в радиусе заморожена")
		&"wind", &"magnet":
			var moved: bool = false
			for reference: WeakRef in original_blocks:
				var block := reference.get_ref() as WoodenBlock
				if not is_instance_valid(block) or block.is_destroyed or block.linear_velocity.length() > 2.0:
					moved = true
			_check(moved, kind, "близкое дерево сдвинулось или разрушилось")
		&"classic", &"heavy", &"ghost", &"homing":
			_check(cat.ability.time_left > 0.0, kind, "эффект способности активен")


func _ability_key() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_E
		event.pressed = pressed
		root.push_input(event, true)


func _pointer(position: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)


func _save_contact_sheet() -> void:
	if _pictures.is_empty():
		return
	var thumb_height := roundi(640.0 * float(root.size.y) / float(root.size.x))
	var sheet := Image.create(1280, thumb_height * 5, false, Image.FORMAT_RGB8)
	for index in _pictures.size():
		var thumb := _pictures[index].duplicate() as Image
		thumb.resize(640, thumb_height, Image.INTERPOLATE_LANCZOS)
		thumb.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(thumb, Rect2i(0, 0, 640, thumb_height), Vector2i(index % 2 * 640, index / 2 * thumb_height))
	var path := "res://.artifacts/cat-abilities-sheet-%dx%d.png" % [root.size.x, root.size.y]
	_check(sheet.save_png(path) == OK, &"all", "сохранён общий лист")


func _check(condition: bool, kind: StringName, description: String) -> bool:
	if not condition:
		_failures += 1
		push_error("Cat preview %s: %s" % [kind, description])
	return condition
