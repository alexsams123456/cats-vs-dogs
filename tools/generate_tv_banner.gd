extends SceneTree
## TV-баннер из собственных ассетов и локального шрифта.


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	root.size = Vector2i(320, 180)
	root.content_scale_size = Vector2i(320, 180)
	var background := ColorRect.new()
	background.color = Color("173b40")
	background.size = Vector2(320, 180)
	root.add_child(background)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/cats_vs_dogs_logo_v1.png") as Texture2D
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(8, 6)
	logo.size = Vector2(304, 116)
	root.add_child(logo)
	var title := Label.new()
	title.text = "КОШКИ ПРОТИВ СОБАК\nANDROID TV"
	title.add_theme_font_override("font", load("res://assets/fonts/interface_theme.tres").default_font)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("fff7df"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 126)
	title.size = Vector2(320, 50)
	root.add_child(title)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png("res://assets/icons/android_tv_banner.png")
	quit(0 if error == OK else 1)
