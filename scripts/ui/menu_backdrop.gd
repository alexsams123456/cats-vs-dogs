class_name MenuBackdrop
extends Control
## Собственная иллюстрация двора: пейзаж кэшируется, живые детали рисуются отдельно.

signal hero_reacted(species: StringName)

const HERO_VISUAL := preload("res://scripts/visuals/hero_visual.gd")
const SUN_FACE := preload("res://scripts/visuals/sun_face.gd")
const INK := Color("345c50")
const PAPER := Color("fff6db")
const REACTION_DURATION := 1.35

var showcase_visible: bool = true:
	set(value):
		showcase_visible = value
		if not value:
			reset_interactions()
		queue_redraw()
		if is_instance_valid(_motion):
			_motion.queue_redraw()

var visual_time: float = 0.0
var _motion: Control
var _sun_face: SunFace
var _frame_time: float = 0.0
var _reaction_times: Array[float] = [-1.0, -1.0]
var _reaction_variants: Array[int] = [0, 0]
var _next_variants: Array[int] = [0, 0]
var _touches: Dictionary = {}
var _touch_index: int = -1
var _pressed_hero: int = -1
var _press_position := Vector2.ZERO
var _mouse_down: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sun_face = SUN_FACE.new()
	_sun_face.name = "SunFace"
	add_child(_sun_face)
	_motion = Control.new()
	_motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_motion)
	_motion.draw.connect(_draw_motion)
	resized.connect(_on_resized)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()
	_on_resized()


func _process(delta: float) -> void:
	visual_time += delta
	for index in 2:
		if _reaction_times[index] >= 0.0:
			_reaction_times[index] += delta
			if _reaction_times[index] >= REACTION_DURATION:
				_reaction_times[index] = -1.0
	var watched_hero := 0 if sin(visual_time * 0.35) >= 0.0 else 1
	for index in 2:
		if _reaction_times[index] >= 0.0:
			watched_hero = index
	_sun_face.focus_on(get_hero_transform(watched_hero == 0).origin)
	_sun_face.advance(delta)
	_frame_time += delta
	if _frame_time < 1.0 / 30.0:
		return
	_frame_time = fmod(_frame_time, 1.0 / 30.0)
	_motion.queue_redraw()


func _on_resized() -> void:
	_reset_pointer()
	if is_instance_valid(_sun_face):
		var scale_factor := size.y / 720.0
		_sun_face.position = Vector2(size.x * 0.56, 188.0 * scale_factor)
		_sun_face.scale = Vector2.ONE * scale_factor * (44.0 / 47.0)
	queue_redraw()
	if is_instance_valid(_motion):
		_motion.queue_redraw()


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	if not is_visible_in_tree():
		reset_interactions()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_interactions()
	elif what == NOTIFICATION_PAUSED:
		_reset_pointer()


func reset_interactions() -> void:
	_reset_pointer()
	_reaction_times.assign([-1.0, -1.0])
	if is_instance_valid(_sun_face):
		_sun_face.reset()
	if is_instance_valid(_motion):
		_motion.queue_redraw()


func _reset_pointer() -> void:
	_touches.clear()
	_touch_index = -1
	_pressed_hero = -1
	_mouse_down = false


func handle_pointer_event(event: InputEvent, blocked: bool = false) -> bool:
	if not showcase_visible or not is_visible_in_tree() or not can_process():
		_reset_pointer()
		return false
	if event is InputEventScreenTouch:
		return _handle_touch(event, blocked)
	if event is InputEventScreenDrag:
		if event.index == _touch_index:
			_cancel_drag(event.position)
		return _pressed_hero >= 0 and event.index == _touch_index
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if not _touches.is_empty():
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_begin_press(event.position, blocked)
			return _pressed_hero >= 0
		if _mouse_down:
			_mouse_down = false
			return _finish_press(event.position, blocked)
	elif event is InputEventMouseMotion and _mouse_down:
		_cancel_drag(event.position)
	return false


func _handle_touch(event: InputEventScreenTouch, blocked: bool) -> bool:
	if event.pressed and not event.canceled:
		if _touches.has(event.index):
			return false
		_touches[event.index] = true
		if _touches.size() == 1:
			_touch_index = event.index
			_mouse_down = false
			_begin_press(event.position, blocked)
		return event.index == _touch_index and _pressed_hero >= 0
	_touches.erase(event.index)
	if event.index != _touch_index:
		return false
	_touch_index = -1
	if event.canceled:
		var captured := _pressed_hero >= 0
		_pressed_hero = -1
		return captured
	return _finish_press(event.position, blocked)


func _begin_press(point: Vector2, blocked: bool) -> void:
	_press_position = point
	_pressed_hero = -1 if blocked else hero_at_position(point)


func _cancel_drag(point: Vector2) -> void:
	if point.distance_to(_press_position) > 32.0 * size.y / 720.0:
		_pressed_hero = -1


func _finish_press(point: Vector2, blocked: bool) -> bool:
	var index := _pressed_hero
	_cancel_drag(point)
	var activate := index >= 0 and _pressed_hero == index and not blocked and hero_at_position(point) == index
	_pressed_hero = -1
	if activate and _reaction_times[index] < 0.0:
		_reaction_times[index] = 0.0
		_reaction_variants[index] = _next_variants[index]
		_next_variants[index] = (_next_variants[index] + 1) % 2
		_sun_face.react(&"delighted", REACTION_DURATION)
		hero_reacted.emit(&"cat" if index == 0 else &"dog")
		_motion.queue_redraw()
	return index >= 0


func hero_at_position(viewport_point: Vector2) -> int:
	if not showcase_visible or size.y <= 0.0:
		return -1
	var local_point := get_global_transform_with_canvas().affine_inverse() * viewport_point
	# Тот же transform, что у рисунка: попадание следует за прыжком, наклоном и resize.
	for index in [1, 0]:
		var point := get_hero_transform(index == 0).affine_inverse() * local_point
		if (point / Vector2(31, 34)).length_squared() <= 1.0:
			return index
	return -1


func _draw() -> void:
	if size.y <= 0.0:
		return
	var scale_factor: float = size.y / 720.0
	var width: float = size.x / scale_factor
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	_draw_sky(width)
	_draw_hills(width)
	_draw_fence(width)
	_draw_tree(Vector2(-27, 620), 1.0, false)
	_draw_tree(Vector2(width + 46, 654), 1.17, true)
	_draw_garden(width)
	if showcase_visible:
		_draw_showcase(width)
	draw_set_transform(Vector2.ZERO)


func _draw_sky(width: float) -> void:
	draw_polygon(PackedVector2Array([
		Vector2.ZERO, Vector2(width, 0), Vector2(width, 720), Vector2(0, 720)
	]), PackedColorArray([Color("fff3d5"), Color("f8edcf"), Color("cedcc0"), Color("e1e6bc")]))
	var sun := Vector2(width * 0.56, 188)
	for index in range(5, 0, -1):
		draw_circle(sun, 48.0 + float(index) * 20.0, Color(1.0, 0.94, 0.65, 0.07))
	# Едва заметные солнечные полосы объединяют иллюстрацию и карточку меню.
	draw_colored_polygon(PackedVector2Array([
		Vector2(width * 0.53, 0), Vector2(width * 0.66, 0),
		Vector2(width * 0.94, 720), Vector2(width * 0.73, 720)
	]), Color(1.0, 0.98, 0.84, 0.13))
	var random := RandomNumberGenerator.new()
	random.seed = 98214
	for index in 130:
		var point := Vector2(random.randf_range(0, width), random.randf_range(0, 530))
		draw_circle(point, random.randf_range(0.5, 1.2), Color(0.58, 0.52, 0.29, 0.075))


func _draw_hills(width: float) -> void:
	_hill(width, 409, 37, 0.5, Color("d3debd"), Color("dfe4be"))
	_hill(width, 451, 45, 2.5, Color("b9ccac"), Color("cbd7a7"))
	_hill(width, 487, 28, 4.0, Color("94b69b"), Color("bfd29c"))
	for index in 10:
		var x: float = width * (0.03 + float(index) * 0.105)
		var y: float = 489.0 + sin(float(index) * 1.3) * 9.0
		var tree_scale: float = 0.55 + float(index % 3) * 0.14
		draw_line(Vector2(x, y), Vector2(x, y - 42 * tree_scale), Color("8ca78b"), 3 * tree_scale, true)
		_ellipse(self, Vector2(x, y - 44 * tree_scale), Vector2(16, 29) * tree_scale, Color("a6bea0"))
		_ellipse(self, Vector2(x - 5 * tree_scale, y - 52 * tree_scale), Vector2(11, 18) * tree_scale, Color("b4c9a6"))
	_hill(width, 537, 15, 1.6, Color("c2d39a"), Color("bbcd91"))
	_hill(width, 607, 21, 4.6, Color("a7bf82"), Color("b6c887"))
	_ellipse(self, Vector2(width * 0.38, 630), Vector2(width * 0.37, 79), Color("c9d49a"))
	_ellipse(self, Vector2(width * 0.37, 646), Vector2(width * 0.33, 65), Color("d8daa3"))
	_hill(width, 737, 36, 1.8, Color("7ba275"), Color("66916b"))


func _hill(width: float, level: float, amplitude: float, phase: float, top: Color, bottom: Color) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var bottom_y: float = maxf(760.0, level + absf(amplitude) * 1.16 + 2.0)
	for index in 65:
		var progress: float = float(index) / 64.0
		var y: float = level + sin(progress * TAU * 1.18 + phase) * amplitude + sin(progress * TAU * 2.2 + phase) * amplitude * 0.16
		points.append(Vector2(progress * width, y))
		colors.append(top)
	points.append(Vector2(width, bottom_y))
	points.append(Vector2(0, bottom_y))
	colors.append(bottom)
	colors.append(bottom)
	draw_polygon(points, colors)


func _draw_fence(width: float) -> void:
	var left: float = width * 0.04
	var right: float = width * 0.60
	draw_line(Vector2(left, 554), Vector2(right, 554), Color("b6bd8d"), 8.0)
	draw_line(Vector2(left, 577), Vector2(right, 577), Color("b6bd8d"), 7.0)
	for index in 15:
		var x: float = lerpf(left, right, float(index) / 14.0)
		var y: float = 531.0 + sin(float(index) * 2.4) * 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, 594), Vector2(x, y + 5), Vector2(x + 6, y),
			Vector2(x + 12, y + 5), Vector2(x + 12, 594)
		]), Color("e7dfb1"))
		draw_line(Vector2(x + 3, y + 8), Vector2(x + 3, 589), Color("f2e9c3"), 2.0)
		draw_circle(Vector2(x + 6, 554), 1.4, Color("b0af80"))


func _draw_tree(root: Vector2, tree_scale: float, flipped: bool) -> void:
	var direction: float = -1.0 if flipped else 1.0
	var trunk := PackedVector2Array([
		Vector2(-20, 0), Vector2(-12, -138), Vector2(-5, -288), Vector2(12, -299),
		Vector2(9, -137), Vector2(25, 0)
	])
	for index in trunk.size():
		trunk[index] = root + trunk[index] * tree_scale * Vector2(direction, 1)
	draw_colored_polygon(trunk, Color("7e9670"))
	draw_line(root + Vector2(3 * direction, -85) * tree_scale, root + Vector2(45 * direction, -275) * tree_scale, Color("7e9670"), 11.0 * tree_scale, true)
	draw_line(root + Vector2(-2 * direction, -70) * tree_scale, root + Vector2(-43 * direction, -264) * tree_scale, Color("7e9670"), 13.0 * tree_scale, true)
	for crown: Vector3 in [Vector3(-62, -313, 75), Vector3(13, -340, 91), Vector3(59, -299, 58), Vector3(-18, -264, 79)]:
		var center: Vector2 = root + Vector2(crown.x * direction, crown.y) * tree_scale
		draw_circle(center, crown.z * tree_scale, Color("729c78"))
		draw_circle(center + Vector2(-9, -15) * tree_scale, crown.z * 0.79 * tree_scale, Color("86ab80"))
		draw_arc(center, crown.z * 0.80 * tree_scale, 3.6, 5.1, 14, Color("a5bf8b"), 4.0 * tree_scale, true)
	_ellipse(self, root + Vector2(3, 0), Vector2(70, 13) * tree_scale, Color(0.29, 0.43, 0.26, 0.14))


func _draw_garden(width: float) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 47211
	for index in 85:
		var center := Vector2(random.randf_range(0, width), random.randf_range(598, 720))
		var tint: Color = Color("e0dfaa") if index % 3 == 0 else Color("93ad77")
		_ellipse(self, center, Vector2(random.randf_range(1.5, 4.0), 1.0), tint)
	for flower: Vector3 in [Vector3(0.07, 636, 1.0), Vector3(0.13, 678, 0.8), Vector3(0.54, 659, 0.85), Vector3(0.59, 624, 0.68), Vector3(0.95, 681, 1.1)]:
		var center := Vector2(width * flower.x, flower.y)
		draw_line(center + Vector2(0, 13) * flower.z, center, Color("789769"), 2.0, true)
		for petal in 5:
			draw_circle(center + Vector2.from_angle(float(petal) * TAU / 5.0) * 3.5 * flower.z, 3.1 * flower.z, PAPER)
		draw_circle(center, 2.6 * flower.z, Color("e8bb63"))
	for index in 7:
		var x: float = width * (0.018 + float(index) * 0.008)
		var y: float = 691.0 + sin(float(index) * 2) * 5
		draw_line(Vector2(x, y + 22), Vector2(x - 5, y - 7), Color("719664"), 2.0, true)
		draw_line(Vector2(x, y + 22), Vector2(x + 9, y + 3), Color("719664"), 2.0, true)


func _draw_showcase(width: float) -> void:
	var art_scale: float = clampf(width / 1280.0, 0.78, 1.08)
	var cat := Vector2(width * 0.315, 545)
	var dog := Vector2(width * 0.495, 530)
	_ellipse(self, Vector2(width * 0.34, 637), Vector2(width * 0.24, 18), Color(0.30, 0.42, 0.25, 0.10))
	_ellipse(self, cat + Vector2(0, 80 * art_scale), Vector2(72, 12) * art_scale, Color(0.25, 0.38, 0.24, 0.15))
	_draw_crate(dog + Vector2(-57, 75) * art_scale, Vector2(117, 39) * art_scale)
	_draw_crate(Vector2(width * 0.53, 623), Vector2(51, 38) * art_scale)
	_draw_slingshot(Vector2(width * 0.16, 633), art_scale)
	# Несколько камешков и рыжий мяч связывают героев с двором.
	_ellipse(self, Vector2(width * 0.43, 646), Vector2(18, 6), Color("b2b78c"))
	_ellipse(self, Vector2(width * 0.43, 643), Vector2(15, 6), Color("ede2b4"))
	var ball := Vector2(width * 0.37, 649)
	_ellipse(self, ball + Vector2(0, 14), Vector2(20, 5), Color(0.31, 0.42, 0.25, 0.14))
	draw_circle(ball, 15, Color("c8754f"))
	draw_circle(ball - Vector2(2, 2), 12, Color("e99d66"))
	draw_arc(ball, 10, 3.6, 5.5, 12, Color("f6c081"), 3.0, true)
	draw_arc(ball + Vector2(-8, 0), 13, -1.0, 1.0, 14, Color("a75f46"), 2.0, true)


func _draw_crate(origin: Vector2, dimensions: Vector2) -> void:
	var rect := Rect2(origin, dimensions)
	draw_style_box(_wood_box(), rect)
	for index in range(1, 3):
		var x: float = origin.x + dimensions.x * float(index) / 3.0
		draw_line(Vector2(x, origin.y + 3), Vector2(x, origin.y + dimensions.y - 3), Color("ae8050"), 2.0, true)
	draw_line(origin + Vector2(6, 6), origin + dimensions - Vector2(6, 6), Color("a97d4d"), 8.0, true)
	draw_line(origin + Vector2(6, 4), origin + dimensions - Vector2(6, 8), Color("edc18a"), 5.0, true)
	for point in [origin + Vector2(7, 7), origin + dimensions - Vector2(7, 7)]:
		draw_circle(point, 1.6, Color("8e754f"))


func _wood_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("d6a669")
	box.border_color = Color("9f8258")
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.shadow_color = Color(0.24, 0.36, 0.23, 0.15)
	box.shadow_size = 4
	box.shadow_offset = Vector2(1, 4)
	return box


func _draw_slingshot(root: Vector2, art_scale: float) -> void:
	_ellipse(self, root, Vector2(35, 9) * art_scale, Color(0.29, 0.40, 0.24, 0.18))
	var fork: Vector2 = root + Vector2(2, -135) * art_scale
	var left: Vector2 = root + Vector2(-38, -208) * art_scale
	var right: Vector2 = root + Vector2(48, -215) * art_scale
	for branch: PackedVector2Array in [PackedVector2Array([root, fork, left]), PackedVector2Array([fork, right])]:
		draw_polyline(branch, Color("7d6949"), 23 * art_scale, true)
		draw_polyline(branch, Color("b88a53"), 17 * art_scale, true)
		draw_polyline(branch, Color("dbad6d"), 6 * art_scale, true)
		draw_circle(branch[-1], 11.5 * art_scale, Color("7d6949"))
		draw_circle(branch[-1], 8.5 * art_scale, Color("d1a06b"))
	var band := PackedVector2Array([left, root + Vector2(2, -179) * art_scale, right])
	draw_polyline(band, Color("765e48"), 7 * art_scale, true)
	draw_polyline(band, Color("bc8356"), 3 * art_scale, true)
	for index in 5:
		var center: Vector2 = root + Vector2(0, -26 - index * 9) * art_scale
		draw_line(center - Vector2(8, -2) * art_scale, center + Vector2(8, -2) * art_scale, Color("e4c391"), 5 * art_scale, true)


func _draw_motion() -> void:
	if size.y <= 0.0:
		return
	var scale_factor: float = size.y / 720.0
	var width: float = size.x / scale_factor
	_motion.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
	_draw_cloud(Vector2(width * 0.67 + sin(visual_time * 0.045) * 24, 104), 0.85)
	_draw_cloud(Vector2(width * 0.92 + sin(visual_time * 0.033 + 1) * 32, 268), 1.1)
	_draw_cloud(Vector2(width * 0.045 + sin(visual_time * 0.041 + 2) * 20, 343), 0.60)
	for index in 8:
		var phase: float = float(index) * 2.17
		var point := Vector2(fposmod(float(index) * width * 0.17 + visual_time * (3.0 + float(index % 3)), width + 40.0) - 20.0, 372.0 + sin(visual_time * 0.31 + phase) * 28 + float(index % 4) * 59)
		var opacity: float = 0.22 + sin(visual_time * 0.8 + phase) * 0.12
		_motion.draw_circle(point, 2.0 + float(index % 2), Color(1.0, 0.97, 0.76, opacity))
	if showcase_visible:
		_draw_hero(true)
		_draw_hero(false)
	_motion.draw_set_transform(Vector2.ZERO)


func _draw_cloud(center: Vector2, cloud_scale: float) -> void:
	var shade := Color(1.0, 0.98, 0.89, 0.54)
	_ellipse(_motion, center, Vector2(78, 17) * cloud_scale, shade)
	_ellipse(_motion, center + Vector2(-28, -12) * cloud_scale, Vector2(33, 25) * cloud_scale, shade)
	_ellipse(_motion, center + Vector2(11, -19) * cloud_scale, Vector2(38, 31) * cloud_scale, shade)
	_ellipse(_motion, center + Vector2(48, -8) * cloud_scale, Vector2(28, 21) * cloud_scale, shade)


func get_hero_transform(cat: bool) -> Transform2D:
	var scale_factor: float = maxf(size.y / 720.0, 0.001)
	var width: float = size.x / scale_factor
	var art_scale: float = clampf(width / 1280.0, 0.78, 1.08)
	var phase: float = 0.0 if cat else 2.4
	var breathing: float = sin(visual_time * 1.7 + phase)
	var hero_position := Vector2(width * (0.315 if cat else 0.495), 545 if cat else 530)
	hero_position.y += breathing * 1.7
	var stretch := Vector2(1.0 - breathing * 0.008, 1.0 + breathing * 0.012)
	var rotation_angle: float = sin(visual_time * 0.9 + phase) * 0.025
	var index: int = 0 if cat else 1
	var elapsed: float = _reaction_times[index]
	if elapsed >= 0.0:
		var progress: float = clampf(elapsed / REACTION_DURATION, 0.0, 1.0)
		var envelope: float = sin(progress * PI)
		if cat and _reaction_variants[index] == 0:
			var hop: float = sin(clampf((progress - 0.1) / 0.62, 0.0, 1.0) * PI)
			hero_position.y -= hop * 48.0 * art_scale
			stretch *= Vector2(1.0 - hop * 0.10, 1.0 + hop * 0.13)
			rotation_angle += sin(progress * TAU) * envelope * 0.12
		elif cat:
			stretch *= Vector2(1.0 + envelope * 0.18, 1.0 - envelope * 0.12)
			hero_position.y += envelope * 8.0 * art_scale
			rotation_angle -= envelope * 0.16
		else:
			var hop: float = absf(sin(progress * TAU)) * envelope
			hero_position.y -= hop * (37.0 if _reaction_variants[index] == 0 else 23.0) * art_scale
			stretch *= Vector2(1.0 + hop * 0.09, 1.0 - hop * 0.06)
			rotation_angle += sin(progress * TAU * 2.0) * envelope * 0.13
	var hero_scale: float = (3.0 if cat else 2.7) * art_scale * scale_factor
	return Transform2D(rotation_angle, stretch * hero_scale, 0.0, hero_position * scale_factor)


func _draw_hero(cat: bool) -> void:
	var index: int = 0 if cat else 1
	var elapsed: float = _reaction_times[index]
	var reacting: bool = elapsed >= 0.0
	_motion.draw_set_transform_matrix(get_hero_transform(cat))
	HERO_VISUAL.paint(_motion, &"cat" if cat else &"dog", &"classic" if cat else &"jumper", Color("efab63") if cat else Color("d0a079"), Color("cb7051") if cat else Color("507f78"), visual_time + maxf(elapsed, 0.0) * 1.6, 0.0 if cat else 2.4, &"celebrate" if reacting else &"idle")
	if reacting:
		_draw_affection(elapsed, cat)


func _draw_affection(elapsed: float, cat: bool) -> void:
	for index in 3:
		var progress: float = clampf((elapsed - float(index) * 0.15) / 0.85, 0.0, 1.0)
		if progress <= 0.0 or progress >= 1.0:
			continue
		var opacity: float = sin(progress * PI)
		var center := Vector2(float(index - 1) * 16.0, -37.0 - progress * 22.0)
		var tint := Color("e88980") if cat else Color("efbc60")
		tint.a = opacity
		if cat:
			var heart := PackedVector2Array()
			for segment in 32:
				var angle: float = float(segment) * TAU / 32.0
				var x: float = 16.0 * pow(sin(angle), 3.0)
				var y: float = -(13.0 * cos(angle) - 5.0 * cos(2.0 * angle) - 2.0 * cos(3.0 * angle) - cos(4.0 * angle))
				heart.append(center + Vector2(x, y) * 0.37)
			_motion.draw_colored_polygon(heart, tint)
		else:
			_ellipse(_motion, center + Vector2(0, 2), Vector2(4.1, 3.4), tint)
			for toe in 3:
				_motion.draw_circle(center + Vector2(float(toe - 1) * 3.7, -3.0 - (1.5 if toe == 1 else 0.0)), 2.0, tint)


func _ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 32:
		var angle: float = TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	canvas.draw_colored_polygon(points, color)
