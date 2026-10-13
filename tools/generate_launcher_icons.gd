extends SceneTree
## Утверждённая иконка «Соперники» для ПК, Android и Web.

const SOURCE := "res://assets/branding/cats_vs_dogs_icon_v2.png"
const OUTPUT := "res://assets/icons/"
const BACKGROUND := Color("10bcd3")


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	var source := Image.load_from_file(SOURCE)
	if source == null or source.is_empty() or source.get_width() != source.get_height():
		push_error("Cannot load approved square game icon")
		quit(1)
		return
	source.convert(Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for layer: String in ["main", "foreground", "background", "monochrome"]:
		var edge: int = 512 if layer == "main" else 432
		var picture := Image.create(edge, edge, false, Image.FORMAT_RGBA8)
		picture.fill(BACKGROUND if layer == "background" else Color.TRANSPARENT)
		if layer != "background":
			var logo := source.duplicate() as Image
			# Цветной передний слой покрывает область движения адаптивной маски.
			var width: int = 288 if layer == "monochrome" else edge
			var height: int = width
			logo.resize(width, height, Image.INTERPOLATE_LANCZOS)
			if layer == "monochrome":
				# Тёмные контуры образуют прозрачную маску без сплошного квадрата.
				for y in height:
					for x in width:
						var pixel := logo.get_pixel(x, y)
						var alpha := pixel.a * (1.0 - smoothstep(0.16, 0.38, pixel.get_luminance()))
						logo.set_pixel(x, y, Color(1, 1, 1, alpha))
			var offset := Vector2i(roundi((edge - width) * 0.5), roundi((edge - height) * 0.5))
			picture.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), offset)
		for prefix: String in ["launcher", "android"]:
			var path := OUTPUT + "%s_%s.png" % [prefix, layer]
			if picture.save_png(path) != OK:
				push_error("Cannot save launcher icon: %s" % path)
				quit(1)
				return
			print("Launcher icon saved: %s" % path)
		if layer == "main":
			picture.resize(180, 180, Image.INTERPOLATE_LANCZOS)
			if picture.save_png(OUTPUT + "apple_touch.png") != OK:
				push_error("Cannot save phone home screen icon")
				quit(1)
				return
	quit()
