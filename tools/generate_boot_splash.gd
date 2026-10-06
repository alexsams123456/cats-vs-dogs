extends SceneTree
## Собственная загрузочная картинка из тех же процедурных героев, что и игра.
## Запускать с графическим рендерером; результат хранится в assets/boot_splash.png.

const OUTPUT := "res://assets/boot_splash.png"
const DIMENSIONS := Vector2i(1280, 720)


class SplashDrawing extends Node2D:
	const HERO := preload("res://scripts/visuals/hero_visual.gd")
	const FONT := preload("res://assets/fonts/interface_font.tres")
	const INK := Color("284448")
	const PAPER := Color("fff6db")


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(DIMENSIONS)), PAPER)
		# Мягкий овал двора и несколько лапок оставляют края одноцветными:
		# поля узких и широких окон сливаются с фоном картинки.
		draw_set_transform(Vector2(640, 410), 0.0, Vector2(1.8, 1.0))
		draw_circle(Vector2.ZERO, 200.0, Color("e5edd2"))
		draw_set_transform(Vector2.ZERO)
		for paw in [Vector2(180, 240), Vector2(1070, 230), Vector2(220, 560), Vector2(1050, 570)]:
			_paw(paw)
		_text("Кошки против собак", 139.0, 66, INK)
		_text("Большая битва за маленькую сосиску", 192.0, 26, Color("668071"))
		# Полёт кота и прерывистый след от рогатки.
		for index in 9:
			var progress := float(index) / 8.0
			var point := Vector2(260.0 + progress * 270.0, 496.0 - sin(progress * PI * 0.5) * 175.0)
			draw_circle(point, 3.0 + progress * 2.0, Color("b2c4a1"))
		_shadow(Vector2(520, 555), Vector2(68, 10))
		_shadow(Vector2(811, 562), Vector2(102, 14))
		draw_set_transform(Vector2(528, 351), -0.38, Vector2.ONE * 3.35)
		HERO.paint(self, &"cat", &"classic", Color("efad62"), Color("b56942"), 0.4, 0.0, &"fly")
		draw_set_transform(Vector2(807, 449), 0.12, Vector2.ONE * 3.8)
		HERO.paint(self, &"dog", &"scout", Color("c89165"), Color("795945"), 0.4, 0.0, &"alert")
		draw_set_transform(Vector2.ZERO)
		_sausage(Vector2(706, 295))
		_bubble(Rect2(325, 234, 154, 57), "Была.", Vector2(500, 302))
		_bubble(Rect2(857, 314, 239, 62), "Моя сосиска!", Vector2(881, 415))
		_text("Загружаем двор. Прячьте сосиски!", 645.0, 30, INK)


	func _text(value: String, baseline: float, font_size: int, color: Color) -> void:
		var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(FONT, Vector2((DIMENSIONS.x - width) * 0.5, baseline), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


	func _shadow(center: Vector2, radius: Vector2) -> void:
		draw_set_transform(center, 0.0, radius)
		draw_circle(Vector2.ZERO, 1.0, Color("c3d2ac"))
		draw_set_transform(Vector2.ZERO)


	func _paw(center: Vector2) -> void:
		draw_circle(center, 12.0, Color("e7dcba"))
		for offset in [Vector2(-17, -14), Vector2(-6, -25), Vector2(9, -24), Vector2(20, -12)]:
			draw_circle(center + offset, 6.0, Color("e7dcba"))


	func _sausage(center: Vector2) -> void:
		draw_set_transform(center, -0.25)
		var sausage := PackedVector2Array([Vector2(-35, 0), Vector2(-15, 5), Vector2(15, 5), Vector2(35, 0)])
		draw_polyline(sausage, INK, 33.0, true)
		draw_polyline(sausage, Color("cf795f"), 26.0, true)
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(side * 35, 0), 15.0, INK)
			draw_circle(Vector2(side * 35, 0), 12.0, Color("cf795f"))
			draw_line(Vector2(side * 49, 0), Vector2(side * 58, -7), INK, 3.0, true)
			draw_line(Vector2(side * 49, 0), Vector2(side * 58, 7), INK, 3.0, true)
		for x in [-18.0, 0.0, 18.0]:
			draw_line(Vector2(x - 3, -3), Vector2(x + 3, 10), Color("ffe0b0"), 3.0, true)
		draw_set_transform(Vector2.ZERO)


	func _bubble(rect: Rect2, value: String, tip: Vector2) -> void:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color("fffefa")
		panel.border_color = INK
		panel.set_border_width_all(3)
		panel.set_corner_radius_all(22)
		var tail := PackedVector2Array([Vector2(rect.position.x + 33, rect.end.y - 2), tip, Vector2(rect.position.x + 61, rect.end.y - 2)])
		draw_colored_polygon(tail, INK)
		draw_style_box(panel, rect)
		var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
		draw_string(FONT, Vector2(rect.get_center().x - width * 0.5, rect.position.y + 39), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, INK)


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Boot splash generation requires a graphical renderer.")
		quit(1)
		return
	var viewport := SubViewport.new()
	# Двойное разрешение со снижением размера сглаживает контуры и в Compatibility.
	viewport.size = DIMENSIONS * 2
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var drawing := SplashDrawing.new()
	drawing.scale = Vector2.ONE * 2.0
	viewport.add_child(drawing)
	root.add_child(viewport)
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	picture.resize(DIMENSIONS.x, DIMENSIONS.y, Image.INTERPOLATE_LANCZOS)
	var result := picture.save_png(OUTPUT)
	viewport.queue_free()
	if result != OK:
		push_error("Cannot save boot splash: %s" % error_string(result))
		quit(1)
		return
	print("Boot splash saved: %s (%d x %d)" % [OUTPUT, DIMENSIONS.x, DIMENSIONS.y])
	quit()
