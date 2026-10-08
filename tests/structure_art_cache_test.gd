extends SceneTree
## Кэш построек сохраняет исходный рисунок, размеры и безопасный предел памяти.

const CACHE := preload("res://scripts/visuals/structure_art_cache.gd")
const BLOCK := preload("res://scripts/visuals/block_visual.gd")
const HOUSE := preload("res://scripts/visuals/dog_house_visual.gd")
var _checks: int = 0
var _failures: int = 0
var _worst_mean: float = 0.0
var _worst_changed: float = 0.0
var _longest_bake_usec: int = 0
var _largest_frame_usec: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_bounds()
	_test_requesters()
	_test_budget()
	if "--capture-structures" in OS.get_cmdline_user_args():
		if DisplayServer.get_name() == "headless":
			_check(false, "Structure capture requires a graphical renderer")
		else:
			CACHE.enabled = true
			await _test_cancel_and_scale()
			await _test_art()
	print("Structure art cache checks: %d passed, %d failed" % [_checks - _failures, _failures])
	print("Structure cache image mean %.5f, changed %.5f; longest bake %.1f ms, largest waiting frame %.1f ms" % [_worst_mean, _worst_changed, _longest_bake_usec / 1000.0, _largest_frame_usec / 1000.0])
	quit(1 if _failures > 0 else 0)


func _test_bounds() -> void:
	var bounds := Rect2(-17, -70, 34, 140)
	_check(CACHE.cache_bounds(bounds) == Rect2(-20, -73, 40, 146), "Padding keeps antialiased structure edges")
	_check(CACHE.texture_dimensions(bounds) == Vector2i(160, 584), "Cache keeps four pixels per logical pixel")
	var fractional := Rect2(-17.25, -70.4, 34.5, 140.8)
	_check(CACHE.cache_bounds(fractional) == Rect2(-21, -74, 42, 148), "Fractional bounds grow outwards to integer edges")
	_check(CACHE.cache_bounds(fractional).encloses(fractional.grow(3.0)), "Rounded padding never crops the supplied drawing")
	_check(CACHE.texture_dimensions(Rect2(0, 0, 1018, 1018)) == Vector2i(4096, 4096), "Largest supported texture remains within WebGL limits")
	_check(CACHE.texture_dimensions(Rect2(0, 0, 1019, 20)) == Vector2i.ZERO, "Oversized structures keep procedural drawing")
	_check(CACHE.texture_dimensions(Rect2()) == Vector2i.ZERO, "Empty structures never allocate textures")
	_check(CACHE.texture_dimensions(Rect2(Vector2(INF, 0), Vector2.ONE)) == Vector2i.ZERO, "Invalid coordinates never allocate textures")
	var drawing := Node2D.new()
	var previous := CACHE.enabled
	CACHE.enabled = false
	_check(not CACHE.paint(drawing, "disabled", bounds, Callable()), "Disabled cache preserves the procedural caller")
	CACHE.enabled = previous
	drawing.free()


func _test_requesters() -> void:
	var drawing := Node2D.new()
	root.add_child(drawing)
	var requesters: Array[WeakRef] = []
	var entry: Dictionary = {"requesters": requesters}
	CACHE._add_requester(entry, drawing)
	CACHE._add_requester(entry, drawing)
	_check(requesters.size() == 1, "Repeated frames share one weak requester")
	_check(CACHE._live_requesters(entry).size() == 1, "Live requester remains eligible for a redraw")
	drawing.free()
	_check(CACHE._live_requesters(entry).is_empty(), "Deleting a requester cancels its pending work safely")


func _test_budget() -> void:
	var previous_entries := CACHE._entries.duplicate()
	var previous_bytes := CACHE._bytes
	CACHE._entries.clear()
	CACHE._bytes = 0
	for index in CACHE.MAX_ENTRIES:
		CACHE._entries[str(index)] = {"last_used": Engine.get_process_frames(), "bytes": 4}
		CACHE._bytes += 4
	_check(not CACHE._has_space(4), "Active entry limit falls back without discarding visible artwork")
	CACHE._entries["0"]["last_used"] = Engine.get_process_frames() - CACHE.STALE_FRAMES - 1
	_check(CACHE._has_space(4) and CACHE._entries.size() == CACHE.MAX_ENTRIES - 1, "Stale artwork releases an entry before a new allocation")
	CACHE._entries.clear()
	CACHE._bytes = CACHE.MAX_BYTES
	CACHE._entries["budget"] = {"last_used": Engine.get_process_frames(), "bytes": CACHE.MAX_BYTES}
	_check(not CACHE._has_space(4), "Active texture memory stays within 64 MiB")
	CACHE._entries["budget"]["last_used"] = Engine.get_process_frames() - CACHE.STALE_FRAMES - 1
	_check(CACHE._has_space(4) and CACHE._bytes == 0, "Stale artwork releases its recorded texture memory")
	CACHE._entries.assign(previous_entries)
	CACHE._bytes = previous_bytes


func _test_art() -> void:
	await _compare_art("test-transparent", Rect2(-64, -48, 128, 96), _paint_transparent, true)
	for material: StringName in [&"wood", &"glass", &"stone", &"metal"]:
		for size: Vector2 in [Vector2(34, 140), Vector2(160, 24)]:
			for damage: float in [0.0, 0.5, 0.8]:
				var key := "test-block-%s-%s-%.1f" % [material, size, damage]
				var painter := BLOCK.paint_uncached.bind(size, material, damage)
				await _compare_art(key, Rect2(-size * 0.5, size), painter, material == &"stone" and damage == 0.5)
	for house_type: StringName in [&"classic", &"barrel", &"igloo", &"fortress"]:
		for material: StringName in [&"wood", &"glass", &"stone", &"metal"]:
			for damage: float in [0.0, 0.5, 0.8]:
				var key := "test-house-%s-%s-%.1f" % [house_type, material, damage]
				var painter := HOUSE.paint_uncached.bind(material, damage, house_type)
				await _compare_art(key, _house_bounds(house_type), painter, material == &"wood" and damage == 0.5)


func _paint_transparent(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(-64, -48, 128, 96), Color(0.8, 0.7, 0.6, 0.4))
	canvas.draw_circle(Vector2(12, -8), 31, Color(0.9, 0.2, 0.1, 0.7), true, -1, true)


func _test_cancel_and_scale() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	root.add_child(viewport)
	var first := Node2D.new()
	var second := Node2D.new()
	viewport.add_child(first)
	viewport.add_child(second)
	var key := "test-cancelled"
	var bounds := Rect2(-64, -48, 128, 96)
	first.scale = Vector2.ONE * 5.0
	_check(not CACHE.paint(first, key, bounds, _paint_transparent) and not CACHE._pending.has(key), "Magnification above four screen pixels keeps the original vector drawing")
	first.scale = Vector2.ONE * 2.0
	_check(not CACHE.paint(first, key, bounds, _paint_transparent) and CACHE._pending.has(key), "Supported magnification starts a cache request")
	CACHE.paint(first, key, bounds, _paint_transparent)
	CACHE.paint(second, key, bounds, _paint_transparent)
	var requesters: Array[WeakRef] = CACHE._pending[key]["requesters"]
	_check(requesters.size() == 2, "One pending bake deduplicates frames and serves both drawings")
	first.free()
	second.free()
	await process_frame
	await process_frame
	await process_frame
	_check(not CACHE._pending.has(key) and not CACHE._entries.has(key), "Deleting all drawings cancels a bake and clears the pending key")
	viewport.queue_free()
	await process_frame


func _house_bounds(house_type: StringName) -> Rect2:
	var outline := HOUSE.collision_outline(house_type)
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline:
		bounds = bounds.expand(point)
	return bounds


func _compare_art(key: String, bounds: Rect2, painter: Callable, save: bool) -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--structure-filter=") and argument.trim_prefix("--structure-filter=") not in key:
			return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 400)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var drawing := Node2D.new()
	drawing.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	drawing.position = Vector2(240, 200)
	drawing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	viewport.add_child(drawing)
	var state: Dictionary = {"cached": false, "hit": false}
	drawing.draw.connect(func() -> void:
		if state["cached"]:
			state["hit"] = CACHE.paint(drawing, key, bounds, painter)
			if state["hit"]:
				return
		painter.call(drawing)
	)
	for scale_value: float in [0.75, 2.0]:
		drawing.scale = Vector2.ONE * scale_value
		drawing.rotation = 0.43 if scale_value == 2.0 else -0.17
		state["cached"] = false
		drawing.queue_redraw()
		var original := await _capture(viewport)
		state["cached"] = true
		state["hit"] = false
		drawing.queue_redraw()
		var started := Time.get_ticks_usec()
		for frame in 240:
			var frame_started := Time.get_ticks_usec()
			await process_frame
			_largest_frame_usec = maxi(_largest_frame_usec, Time.get_ticks_usec() - frame_started)
			if CACHE._entries.has(key):
				break
		_check(CACHE._entries.has(key), "Structure cache completes: " + key)
		if not CACHE._entries.has(key):
			print("Cache timeout after %.1f ms" % [(Time.get_ticks_usec() - started) / 1000.0])
			break
		_longest_bake_usec = maxi(_longest_bake_usec, int(CACHE._entries[key]["bake_usec"]))
		drawing.queue_redraw()
		var cached := await _capture(viewport)
		_check(state["hit"], "Finished structure uses one texture: " + key)
		_compare_pixels(original, cached, key + "-" + str(scale_value))
		if save and scale_value == 2.0:
			original.save_png("res://.artifacts/structure-%s-original.png" % key)
			cached.save_png("res://.artifacts/structure-%s-cached.png" % key)
	viewport.queue_free()
	await process_frame


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _compare_pixels(original: Image, cached: Image, name: String) -> void:
	var old_data := original.get_data()
	var new_data := cached.get_data()
	var total_error: int = 0
	var foreground: int = 0
	var changed: int = 0
	var old_covered: int = 0
	var new_covered: int = 0
	for offset in range(0, old_data.size(), 8):
		if old_data[offset + 3] > 32:
			old_covered += 1
		if new_data[offset + 3] > 32:
			new_covered += 1
		if old_data[offset + 3] == 0 and new_data[offset + 3] == 0:
			continue
		foreground += 1
		var maximum: int = 0
		for channel in 4:
			var error: int = absi(int(old_data[offset + channel]) - int(new_data[offset + channel]))
			total_error += error
			maximum = maxi(maximum, error)
		if maximum > 32:
			changed += 1
	var mean := float(total_error) / float(maxi(foreground, 1) * 4 * 255)
	var fraction := float(changed) / float(maxi(foreground, 1))
	_worst_mean = maxf(_worst_mean, mean)
	_worst_changed = maxf(_worst_changed, fraction)
	_check(foreground > 0 and absf(float(new_covered - old_covered)) <= float(old_covered) * 0.05, "Structure preserves its silhouette and coverage: " + name)
	_check(mean < 0.05 and fraction < 0.16, "Structure retains details and alpha: %s (mean %.4f, changed %.4f)" % [name, mean, fraction])
	if mean >= 0.05 or fraction >= 0.16 or absf(float(new_covered - old_covered)) > float(old_covered) * 0.05:
		original.save_png("res://.artifacts/structure-failed-%s-original.png" % name)
		cached.save_png("res://.artifacts/structure-failed-%s-cached.png" % name)
		print("Structure coverage %s: original %d, cached %d" % [name, old_covered, new_covered])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
