extends SceneTree
## Контактные листы мимики и главное меню в двух пропорциях окна.

const DIMENSIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(960, 720)]


class ExpressionSheet extends Node2D:

	const CAT := preload("res://characters/cats/classic.tres")
	const DOG := preload("res://characters/dogs/scout.tres")
	const FONT := preload("res://assets/fonts/Nunito.ttf")

	var times: Array[float] = []
	var title: String = ""


	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color("fff6db"))
		draw_string(FONT, Vector2(24, 32), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, HeroVisual.INK)
		for index in times.size():
			var origin := Vector2(16 + (index % 4) * 316, 48 + floori(float(index) / 4.0) * 220)
			draw_rect(Rect2(origin, Vector2(300, 204)), Color("e9ebd5"))
			draw_string(FONT, origin + Vector2(12, 28), "t = %.2f s" % times[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, HeroVisual.INK)
			_paint(CAT, origin + Vector2(84, 128), times[index])
			_paint(DOG, origin + Vector2(226, 128), times[index])


	func _paint(definition: CharacterDefinition, center: Vector2, time: float) -> void:
		draw_set_transform(center, 0.0, Vector2.ONE * 1.85)
		HeroVisual.paint(self, definition.species, definition.id, definition.fur_color, definition.accent_color, time, 0.0)
		draw_set_transform(Vector2.ZERO)


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	root.size = Vector2i(1280, 720)
	var sheet := ExpressionSheet.new()
	root.add_child(sheet)
	for page in 2:
		sheet.times.clear()
		for index in 12:
			sheet.times.append(float(page * 12 + index) * 0.25)
		if page == 1:
			sheet.times[11] = 6.0
		sheet.title = "Мимика в покое: кот и собака, фаза 0 (лист %d)" % (page + 1)
		sheet.queue_redraw()
		await _shot("sheet-%d" % (page + 1))
	var blink_time: float = _first_blink()
	sheet.times = [maxf(0.0, blink_time - 0.12), blink_time, blink_time + 0.12]
	sheet.title = "Моргание крупным планом: до, во время и после"
	sheet.queue_redraw()
	await _shot("blink")
	sheet.queue_free()
	await process_frame
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	for dimensions in DIMENSIONS:
		root.size = dimensions
		await create_timer(0.7).timeout
		await _shot("menu-%d-a" % dimensions.x)
		await create_timer(1.2).timeout
		await _shot("menu-%d-b" % dimensions.x)
	app.queue_free()
	await create_timer(0.2).timeout
	print("Expression preview: 3 contact sheets and 4 menu frames saved")
	quit()


func _first_blink() -> float:
	for step in 600:
		var time: float = float(step) * 0.01
		if HeroVisual._blink(time, 0.0) < 0.08:
			return time
	return 0.0


func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.artifacts/expressions-%s.png" % label)
