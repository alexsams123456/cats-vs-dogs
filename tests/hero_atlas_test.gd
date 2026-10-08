extends SceneTree
## Cached bodies must preserve every hero, layering, expression and live face.

const VISUAL := preload("res://scripts/visuals/hero_visual.gd")
const ATLAS := preload("res://scripts/visuals/hero_atlas.gd")
const CATALOG := preload("res://scripts/data/character_catalog.gd")
const CAT := preload("res://scenes/actors/cat_projectile.tscn")
var _checks: int = 0
var _failures: int = 0


class Portrait extends Node2D:
	var definition: CharacterDefinition
	var expression: StringName
	var phase: float
	var time: float = 0.0
	var shield: bool = false

	func _draw() -> void:
		VISUAL.paint(self, StringName(definition.species), definition.id, definition.fur_color, definition.accent_color, time, phase, expression, shield)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var definitions: Array[CharacterDefinition] = []
	definitions.append_array(CATALOG.CATS)
	definitions.append_array(CATALOG.DOGS)
	for definition in definitions:
		var layers: Array[String] = ["idle", "front"]
		if definition.species == "cat":
			layers.append_array(["aim", "fly"])
		for layer in layers:
			var texture := load(ATLAS.path_for(StringName(definition.species), definition.id, definition.fur_color, definition.accent_color, layer)) as Texture2D
			_check(texture != null and texture.get_size() == Vector2(1536, 1536), "Atlas exists with sharp bounded dimensions: %s/%s/%s" % [definition.species, definition.id, layer])
	_check(ProjectSettings.get_setting("display/window/dpi/allow_hidpi"), "Web keeps native display density")
	_check(ATLAS.pose(&"cat", &"meow", false) == "fly" and ATLAS.pose(&"cat", &"aim", false) == "aim", "Aim and airborne ears change immediately")
	_check(ATLAS.pose(&"dog", &"bark", false) == "idle" and ATLAS.pose(&"dog", &"hit", true) == "front", "Dog expressions stay in the live face layer")
	_check(ATLAS.frame_for(0, 0) == ATLAS.frame_for(TAU / 2.8, 0), "Body animation loops continuously")
	_check(ATLAS.frame_for(0.2, 0) != ATLAS.frame_for(0.2, 2), "Heroes retain different animation phases")
	_check(not ResourceLoader.exists(ATLAS.path_for(&"cat", &"custom", Color.RED, Color.BLUE, "idle")), "Unknown artwork falls back to procedural drawing")
	VISUAL.use_atlas = true
	var cat := CAT.instantiate() as CatProjectile
	cat.definition = CATALOG.CATS[0]
	root.add_child(cat)
	var warmed: bool = true
	for layer in ["idle", "front", "aim", "fly"]:
		warmed = warmed and ATLAS._textures.has(ATLAS.path_for(&"cat", cat.definition.id, cat.definition.fur_color, cat.definition.accent_color, layer))
	_check(warmed, "Sling cat preloads aiming and flight textures before interaction")
	cat.queue_free()
	await process_frame
	if "--capture-heroes" in OS.get_cmdline_user_args():
		for definition in definitions:
			await _compare(definition)
		await _check_live_face(definitions[0])
	VISUAL.use_atlas = OS.has_feature("web")
	print("Hero atlas checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _compare(definition: CharacterDefinition) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 480)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var portrait := Portrait.new()
	portrait.definition = definition
	portrait.position = Vector2(240, 240)
	portrait.phase = float(17) * TAU / ATLAS.FRAMES + 0.0001
	portrait.shield = definition.id == &"armored"
	viewport.add_child(portrait)
	var expressions: Array[StringName] = [&"idle", &"aim", &"fly", &"meow", &"hit", &"celebrate"]
	if definition.species == "dog":
		expressions.assign([&"idle", &"alert", &"bark", &"hit", &"defeated", &"celebrate"])
	for expression in expressions:
		portrait.expression = expression
		for zoom in [0.62, 1.0, 2.5]:
			portrait.scale = Vector2.ONE * zoom
			VISUAL.use_atlas = false
			var original := await _capture(viewport, portrait)
			VISUAL.use_atlas = true
			var cached := await _capture(viewport, portrait)
			var error: float = 0.0
			for y in range(110, 370):
				for x in range(110, 370):
					var a := original.get_pixel(x, y)
					var b := cached.get_pixel(x, y)
					error += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			error /= 260.0 * 260.0 * 3.0
			_check(error < 0.012, "Art matches source: %s/%s/%.2f (mean %.5f)" % [definition.id, expression, zoom, error])
			if expression == &"idle" and zoom == 2.5:
				cached.save_png("res://.artifacts/hero-atlas-%s.png" % definition.id)
	viewport.queue_free()
	await process_frame


func _check_live_face(definition: CharacterDefinition) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var portrait := Portrait.new()
	portrait.definition = definition
	portrait.expression = &"idle"
	portrait.phase = 0.0
	portrait.position = Vector2(120, 120)
	portrait.scale = Vector2.ONE * 2.5
	viewport.add_child(portrait)
	portrait.time = 0.09
	var blinking := await _capture(viewport, portrait)
	portrait.time = 0.3
	var open := await _capture(viewport, portrait)
	var eye_region := Rect2i(88, 90, 64, 28)
	_check(blinking.get_region(eye_region).get_data() != open.get_region(eye_region).get_data(), "Eyes keep blinking with the live face clock")
	viewport.queue_free()
	await process_frame


func _capture(viewport: SubViewport, portrait: Portrait) -> Image:
	portrait.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error(message)
