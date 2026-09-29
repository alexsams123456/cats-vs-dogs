class_name AmbientLife
extends Node2D
## The backdrop's pausable clock drives every decorative movement.

const MEADOW_TREE := preload("res://scripts/world/meadow_tree.gd")
const SCENERY_PINE := preload("res://scripts/world/scenery_pine.gd")
const SUN_FACE := preload("res://scripts/visuals/sun_face.gd")
const PINE_ROOTS := [Vector3(-38, 609, 155), Vector3(70, 608, 111), Vector3(149, 604, 77), Vector3(1179, 603, 107), Vector3(1328, 618, 173), Vector3(1430, 616, 127)]
const LEAF_COLORS := [Color("b5b975"), Color("d4bd77"), Color("92ad72")]
const ICE_TIPS := [Vector2(65, 577), Vector2(128, 591), Vector2(397, 592), Vector2(1182, 589), Vector2(1279, 558), Vector2(1428, 578)]
const CLOUD_HEIGHTS := [90.0, 112.0, 247.0, 194.0]
const CLOUD_SCALES := [0.83, 0.52, 0.61, 0.43]
const CLOUD_SPEEDS := [7.0, 4.2, 9.5, 5.3]
const GRASS_POSITIONS := [
	-110.0, -70.0, -18.0, 51.0, 83.0, 115.0, 141.0,
	337.0, 368.0, 401.0, 468.0, 537.0, 568.0, 593.0,
	637.0, 672.0, 719.0, 1139.0, 1172.0, 1204.0, 1245.0,
	1293.0, 1328.0, 1390.0, 1464.0, 1531.0,
]
const FLOWER_ROOTS := [
	Vector2(69, 619), Vector2(92, 620), Vector2(117, 618),
	Vector2(355, 619), Vector2(371, 620), Vector2(393, 619),
	Vector2(543, 619), Vector2(564, 620), Vector2(583, 619),
	Vector2(654, 618), Vector2(1194, 619), Vector2(1217, 620),
	Vector2(1263, 619), Vector2(1290, 619), Vector2(1434, 620),
]
const FLOWER_COLORS := [Color("f5e8bd"), Color("e9b68d"), Color("c5c4df"), Color("f9edcb")]
const BUTTERFLY_ORIGINS := [Vector2(389, 529), Vector2(638, 503), Vector2(1237, 534)]
const BUTTERFLY_COLORS := [Color("edae69"), Color("b3a0ce"), Color("f2cf86")]
const WATER_GLINTS := [Vector2(754, 482), Vector2(789, 509), Vector2(660, 529), Vector2(603, 547), Vector2(614, 565), Vector2(517, 591), Vector2(438, 612)]
const SUN_CENTER := Vector2(1075, 153)
const STEM_COLOR := Color("547956")

var _cloud_x := PackedFloat32Array([192.0, 595.0, 898.0, 1410.0])
var _cloud_shape := PackedVector2Array()
var _cloud_shade := PackedVector2Array()
var _cloud_light := PackedVector2Array()
var _blade := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _bird_wing := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _trees: Array[Node2D] = []
var _pines: Array[Node2D] = []
var _water_path := PackedVector2Array()
var _leaf := PackedVector2Array([Vector2(-6, 0), Vector2(-1, -3), Vector2(6, 0), Vector2(0, 3)])
var _breeze_line := PackedVector2Array()
var _time: float = 0.0
var _visible_world := Rect2(0, 0, 1280, 720)
var biome: StringName = &"backyard"
var sun_face: SunFace


func _ready() -> void:
	_build_cloud_shapes()
	sun_face = SUN_FACE.new()
	sun_face.name = "SunFace"
	sun_face.position = SUN_CENTER
	sun_face.show_behind_parent = true
	add_child(sun_face)
	_add_tree(Vector2(25, 620), Vector2(0.95, 0.95), false)
	_add_tree(Vector2(1340, 620), Vector2(-1.06, 1.06), true)
	for item: Vector3 in PINE_ROOTS:
		var pine := SCENERY_PINE.new()
		pine.position = Vector2(item.x, item.y)
		pine.height = item.z
		pine.show_behind_parent = true
		add_child(pine)
		_pines.append(pine)
	_breeze_line.resize(13)
	set_biome(biome)


func set_biome(value: StringName) -> void:
	biome = value
	if is_instance_valid(sun_face):
		sun_face.visible = biome != &"glacier"
	for tree: Node2D in _trees:
		tree.visible = biome == &"backyard"
	for pine: Node2D in _pines:
		pine.visible = biome == &"mountain"
	queue_redraw()


func set_water_path(points: PackedVector2Array) -> void:
	# Берега и течение используют одну геометрию, подготовленную при смене биома.
	_water_path = points
	queue_redraw()


func _add_tree(root: Vector2, tree_scale: Vector2, warm: bool) -> void:
	var tree := MEADOW_TREE.new()
	tree.position = root
	tree.scale = tree_scale
	tree.warm_foliage = warm
	# Cached commands move as a whole; leaves never rebuild complex geometry per frame.
	tree.show_behind_parent = true
	add_child(tree)
	_trees.append(tree)


func advance(delta: float, elapsed: float, visible_world: Rect2) -> void:
	_time = elapsed
	_visible_world = visible_world
	if is_instance_valid(sun_face) and sun_face.visible:
		sun_face.advance(delta)
	for index in _cloud_x.size():
		_cloud_x[index] += delta * CLOUD_SPEEDS[index]
		var clearance: float = 120.0 * CLOUD_SCALES[index] + 24.0
		var left: float = visible_world.position.x - clearance
		var right: float = visible_world.end.x + clearance
		if _cloud_x[index] > right or _cloud_x[index] < left:
			_cloud_x[index] = left + fposmod(_cloud_x[index] - left, right - left)
	for index in _trees.size():
		var phase := float(index) * 2.4
		_trees[index].rotation = sin(_time * 0.57 + phase) * 0.007 + sin(_time * 1.13 + phase) * 0.002
	for index in _pines.size():
		var phase := float(index) * 1.7
		_pines[index].rotation = sin(_time * 0.86 + phase) * 0.013 + sin(_time * 1.61 + phase) * 0.004
	queue_redraw()


func _draw() -> void:
	if biome == &"glacier":
		_draw_polar_sky()
		_draw_snowfall()
		_draw_ice_shimmer()
		_draw_snow_drift()
		return
	for index in _cloud_x.size():
		var bob := sin(_time * 0.24 + float(index) * 2.0) * 2.5
		_draw_cloud(Vector2(_cloud_x[index], CLOUD_HEIGHTS[index] + bob), CLOUD_SCALES[index])
	_draw_birds()
	if biome == &"mountain":
		_draw_mountain_breeze()
		_draw_water_current()
		return
	_draw_water_glints()
	_draw_water_current()
	_draw_water_ripples()
	for index in GRASS_POSITIONS.size():
		_draw_grass(GRASS_POSITIONS[index], index)
	for index in FLOWER_ROOTS.size():
		_draw_flower(index)
	_draw_drifting_seeds()
	_draw_falling_leaves()
	for index in BUTTERFLY_ORIGINS.size():
		_draw_butterfly(index)
	for index in 2:
		_draw_dragonfly(index)


func _draw_polar_sky() -> void:
	var moon := Vector2(1110, 148)
	for layer in range(5, 0, -1):
		draw_circle(moon, 25.0 + float(layer) * 9.0, Color(0.75, 0.92, 0.97, 0.025), true, -1.0, true)
	draw_circle(moon, 27.0, Color("d8ebec"), true, -1.0, true)
	draw_circle(moon + Vector2(-8, -8), 27.0, Color("abc8d4"), true, -1.0, true)
	# Полупрозрачные полосы плавно меняют высоту; пауза останавливает общий счётчик.
	for band in 3:
		var upper := PackedVector2Array()
		var lower := PackedVector2Array()
		var colors := PackedColorArray()
		var lower_colors := PackedColorArray()
		for index in 49:
			var x := -160.0 + float(index) * 35.0
			var phase := x * 0.005 + float(band) * 0.8 + _time * 0.11
			var y := 126.0 + float(band) * 29.0 + sin(phase) * 31.0 + sin(phase * 1.9) * 12.0
			var fade := sin(float(index) / 48.0 * PI)
			upper.append(Vector2(x, y - 46.0 - sin(phase * 1.3) * 14.0))
			lower.append(Vector2(x, y))
			colors.append(Color(0.53, 0.89, 0.85, 0.0))
			lower_colors.append(Color(0.59, 0.96, 0.82, 0.18 * fade) if band != 1 else Color(0.71, 0.77, 0.97, 0.16 * fade))
		lower.reverse()
		lower_colors.reverse()
		upper.append_array(lower)
		colors.append_array(lower_colors)
		draw_polygon(upper, colors)


func _draw_snowfall() -> void:
	for index in 34:
		var phase := float(index) * 1.71
		var x := _visible_world.position.x - 20.0 + fposmod(float(index) * 163.0 + _time * (9.0 + float(index % 4) * 2.0), _visible_world.size.x + 40.0)
		var y := 55.0 + fposmod(float(index) * 73.0 + _time * (11.0 + float(index % 3) * 3.0), 559.0)
		var point := Vector2(x + sin(_time * 0.7 + phase) * 12.0, y)
		draw_circle(point, 1.0 + float(index % 3) * 0.35, Color(0.96, 0.99, 1.0, 0.40 + sin(phase) * 0.13), true, -1.0, true)
	# Несколько ближних снежинок вращаются медленнее мелкого дальнего снега.
	for index in 9:
		var phase := float(index) * 2.13
		var progress := fposmod(_time * 0.037 + float(index) * 0.117, 1.0)
		var x := _visible_world.position.x + fposmod(float(index) * 193.0 + _time * 18.0, _visible_world.size.x + 60.0) - 30.0
		var center := Vector2(x + sin(_time * 0.8 + phase) * 19.0, 76.0 + progress * 538.0)
		var alpha := sin(progress * PI) * 0.6
		draw_set_transform(center, _time * 0.5 + phase)
		for spoke in 3:
			var direction := Vector2.from_angle(float(spoke) * PI / 3.0) * 3.5
			draw_line(-direction, direction, Color(0.95, 0.99, 1.0, alpha), 1.0, true)
		draw_set_transform(Vector2.ZERO)
	for index in 6:
		var point := Vector2(400.0 + float(index) * 137.0, 581.0 + float(index % 3) * 12.0)
		var alpha := maxf(0.0, sin(_time * 1.4 + float(index) * 2.1)) * 0.65
		draw_line(point - Vector2(3, 0), point + Vector2(3, 0), Color(0.94, 1.0, 1.0, alpha), 1.0, true)
		draw_line(point - Vector2(0, 3), point + Vector2(0, 3), Color(0.94, 1.0, 1.0, alpha), 1.0, true)


func _draw_ice_shimmer() -> void:
	for index in ICE_TIPS.size():
		var glow := pow(maxf(0.0, sin(_time * 1.05 + float(index) * 1.9)), 5.0)
		var point: Vector2 = ICE_TIPS[index] + Vector2(0, 6)
		var color := Color(0.92, 1.0, 1.0, glow * 0.75)
		draw_circle(point, 6.0, Color(0.84, 0.97, 1.0, glow * 0.13), true, -1.0, true)
		draw_line(point - Vector2(5, 0), point + Vector2(5, 0), color, 1.2, true)
		draw_line(point - Vector2(0, 7), point + Vector2(0, 7), color, 1.2, true)
	for index in 8:
		var x := 528.0 + float(index) * 48.0
		var center := Vector2(x, 586.0 + sin(float(index) * 1.3) * 7.0)
		var alpha := 0.12 + sin(_time * 0.9 - float(index) * 0.7) * 0.1
		draw_line(center - Vector2(13, 0), center + Vector2(13, 0), Color(0.91, 0.99, 1.0, alpha), 1.4, true)


func _draw_snow_drift() -> void:
	# Короткие полупрозрачные струйки у земли, позади героев и построек.
	for index in 12:
		var progress := fposmod(_time * (0.09 + float(index % 3) * 0.012) + float(index) * 0.137, 1.0)
		var origin := Vector2(_visible_world.position.x - 130.0 + progress * (_visible_world.size.x + 260.0), 567.0 + float(index % 4) * 13.0)
		for sample in _breeze_line.size():
			var along := float(sample) / float(_breeze_line.size() - 1)
			_breeze_line[sample] = origin + Vector2(along * 76.0, sin(along * PI + _time * 0.7 + float(index)) * 4.0)
		var alpha := sin(progress * PI) * (0.12 + float(index % 3) * 0.025)
		draw_polyline(_breeze_line, Color(0.96, 0.99, 1.0, alpha), 2.0, true)


func _draw_mountain_breeze() -> void:
	for index in GRASS_POSITIONS.size():
		if index % 2 == 0:
			_draw_grass(GRASS_POSITIONS[index], index)
	for index in [0, 3, 4, 11, 12]:
		_draw_flower(index)
	for index in 7:
		var phase := float(index) * 1.7
		var point := Vector2(732.0 + sin(_time * 0.5 + phase) * 30.0 + float(index % 3) * 29.0, 542.0 + float(index) * 9.0)
		draw_line(point - Vector2(5.0 + sin(phase) * 3.0, 0), point + Vector2(5, 0), Color(0.87, 0.97, 0.94, 0.22 + sin(_time + phase) * 0.1), 1.3, true)


func _draw_cloud(center: Vector2, scale_factor: float) -> void:
	if _cloud_shape.is_empty():
		return
	draw_set_transform(center, 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(_cloud_shape, Color("f8f5e8"))
	draw_polyline(_cloud_shape, Color("f8f5e8"), 0.9, true)
	draw_colored_polygon(_cloud_shade, Color("dce7de"))
	draw_colored_polygon(_cloud_light, Color("fffbed"))
	draw_set_transform(Vector2.ZERO)


func _build_cloud_shapes() -> void:
	_cloud_shape.append(Vector2(-110, 13))
	_append_curve(_cloud_shape, Vector2(-115, -5), Vector2(-96, -22), Vector2(-77, -16))
	_append_curve(_cloud_shape, Vector2(-82, -44), Vector2(-37, -62), Vector2(-18, -33))
	_append_curve(_cloud_shape, Vector2(-3, -67), Vector2(54, -54), Vector2(55, -18))
	_append_curve(_cloud_shape, Vector2(80, -31), Vector2(108, -6), Vector2(102, 12))
	_append_curve(_cloud_shape, Vector2(120, 17), Vector2(108, 35), Vector2(84, 35))
	_append_curve(_cloud_shape, Vector2(25, 40), Vector2(-54, 38), Vector2(-89, 33))
	_append_curve(_cloud_shape, Vector2(-108, 33), Vector2(-115, 27), Vector2(-110, 13))
	_cloud_shade.append(Vector2(-110, 15))
	_append_curve(_cloud_shade, Vector2(-85, 36), Vector2(-64, 17), Vector2(-34, 23))
	_append_curve(_cloud_shade, Vector2(18, 37), Vector2(67, 19), Vector2(105, 22))
	_append_curve(_cloud_shade, Vector2(108, 33), Vector2(96, 36), Vector2(84, 35))
	_append_curve(_cloud_shade, Vector2(25, 40), Vector2(-54, 38), Vector2(-89, 33))
	_append_curve(_cloud_shade, Vector2(-104, 32), Vector2(-114, 27), Vector2(-110, 15))
	_cloud_light.append(Vector2(-67, -20))
	_append_curve(_cloud_light, Vector2(-69, -42), Vector2(-38, -51), Vector2(-24, -32))
	_append_curve(_cloud_light, Vector2(-37, -39), Vector2(-55, -33), Vector2(-67, -20))


func _append_curve(points: PackedVector2Array, control_a: Vector2, control_b: Vector2, end: Vector2) -> void:
	var start := points[points.size() - 1]
	for step in range(1, 13):
		points.append(start.bezier_interpolate(control_a, control_b, end, float(step) / 12.0))


func _draw_birds() -> void:
	var span := _visible_world.size.x + 260.0
	var flock_x := _visible_world.position.x - 130.0 + fposmod(650.0 + _time * 13.0, span)
	for index in 5:
		var phase := float(index) * 1.9
		var wing := sin(_time * 3.2 + phase) * 3.2
		var center := Vector2(flock_x + float(index) * 24.0, 208.0 + sin(phase) * 13.0 + float(index) * 5.0)
		_bird_wing[0] = center + Vector2(-7, -2 - wing)
		_bird_wing[1] = center + Vector2(-3, -3 - wing * 0.3)
		_bird_wing[2] = center
		_bird_wing[3] = center + Vector2(3, -3 - wing * 0.3)
		_bird_wing[4] = center + Vector2(7, -2 - wing)
		draw_polyline(_bird_wing, Color("71939a"), 1.5, true)


func _draw_water_glints() -> void:
	for index in WATER_GLINTS.size():
		var phase := float(index) * 1.7
		var center: Vector2 = WATER_GLINTS[index] + Vector2(sin(_time * 0.6 + phase) * 3.0, sin(_time * 0.4 + phase) * 0.7)
		var width := 3.0 + float(index) * 1.3 + sin(_time * 0.9 + phase) * 1.5
		var alpha := 0.27 + sin(_time * 0.8 + phase) * 0.13
		draw_line(center - Vector2(width, 0), center + Vector2(width, 0), Color(0.93, 0.97, 0.83, alpha), 1.4, true)


func _draw_water_current() -> void:
	if _water_path.size() < 2:
		return
	var speed := 0.085 if biome == &"mountain" else 0.05
	for index in 18:
		var progress := fposmod(_time * speed + float(index) / 18.0, 1.0)
		var sample := progress * float(_water_path.size() - 1)
		var segment := mini(int(sample), _water_path.size() - 2)
		var center := _water_path[segment].lerp(_water_path[segment + 1], sample - float(segment))
		var depth := clampf((center.y - 455.0) / 165.0, 0.0, 1.0)
		var river_width := 1.0 + depth * depth * 49.0
		center.x += sin(float(index) * 2.4) * river_width * 0.5
		var width := 0.6 + depth * 6.0
		var alpha := sin(progress * PI) * 0.48
		draw_line(center - Vector2(width, 0), center + Vector2(width, 0), Color(0.91, 0.98, 0.94, alpha), 1.3, true)


func _draw_water_ripples() -> void:
	for index in [3, 4, 5, 6]:
		var progress := fposmod(_time * 0.35 + float(index) * 0.27, 1.0)
		var center: Vector2 = WATER_GLINTS[index]
		var alpha := sin(progress * PI) * 0.42
		draw_set_transform(center, 0.0, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, 2.0 + progress * 13.0, 0, TAU, 24, Color(0.94, 0.99, 0.90, alpha), 1.0, true)
		draw_set_transform(Vector2.ZERO)


func _draw_grass(x: float, index: int) -> void:
	var root := Vector2(x, 621)
	var breeze := _wind_at(x)
	var tint := Color("6b915d") if index % 3 == 0 else Color("517e58")
	for blade in 4:
		var spread := float(blade) - 1.5
		var height := 12.0 + float((index * 7 + blade * 11) % 18)
		_blade[0] = root + Vector2(spread * 2.5 - 1.5, 0)
		_blade[1] = root + Vector2(spread * 4.0 + breeze * 0.35 - 0.8, -height * 0.55)
		_blade[2] = root + Vector2(spread * 6.0 + breeze, -height)
		_blade[3] = root + Vector2(spread * 4.0 + breeze * 0.35 + 0.8, -height * 0.55)
		_blade[4] = root + Vector2(spread * 2.5 + 1.5, 0)
		draw_colored_polygon(_blade, tint)


func _wind_at(x: float) -> float:
	return sin(_time * 1.3 - x * 0.008) * 3.5 + sin(_time * 0.59 + x * 0.019) * 1.8 + 1.2


func _draw_flower(index: int) -> void:
	var root: Vector2 = FLOWER_ROOTS[index]
	var sway := _wind_at(root.x)
	var height := 19.0 + float(index * 11 % 21)
	var middle := root + Vector2(sway * 0.3, -height * 0.5)
	var center := root + Vector2(sway, -height)
	var color: Color = FLOWER_COLORS[index % FLOWER_COLORS.size()]
	draw_line(root, middle, STEM_COLOR, 1.5, true)
	draw_line(middle, center, STEM_COLOR, 1.3, true)
	draw_line(middle, middle + Vector2(5.0, -4.0), Color("70935e"), 2.6, true)
	if index % 4 == 2:
		# Upright lavender heads break up the round daisies.
		for bloom in 4:
			var side := -1.0 if bloom % 2 == 0 else 1.0
			draw_circle(center + Vector2(side * 2.0, float(bloom) * 3.0), 2.6, color)
	else:
		for petal in 5:
			var direction := Vector2.from_angle(float(petal) * TAU / 5.0 - PI * 0.5)
			draw_circle(center + direction * 3.0, 2.8, color)
		draw_circle(center, 2.1, Color("c99b4e"))


func _draw_drifting_seeds() -> void:
	for index in 7:
		var phase := float(index) * 1.71
		var x := _visible_world.position.x - 30.0 + fposmod(float(index) * 213.0 + _time * (12.0 + float(index % 3) * 3.0), _visible_world.size.x + 60.0)
		var y := 510.0 + sin(_time * 0.63 + phase) * 17.0 + float(index % 3) * 29.0
		var center := Vector2(x, y)
		var direction := Vector2.from_angle(-0.4 + sin(_time + phase) * 0.3)
		draw_line(center, center + direction * 4.0, Color(0.96, 0.92, 0.70, 0.62), 1.4, true)


func _draw_falling_leaves() -> void:
	for index in 10:
		var phase := float(index) * 1.79
		var progress := fposmod(_time * (0.065 + float(index % 3) * 0.009) + float(index) * 0.113, 1.0)
		var from_left := index % 2 == 0
		var root_x := 12.0 if from_left else 1332.0
		var travel := progress * (180.0 if from_left else -205.0)
		var center := Vector2(root_x + travel + sin(_time * 1.2 + phase) * 22.0, 402.0 + progress * 207.0)
		var color: Color = LEAF_COLORS[index % LEAF_COLORS.size()]
		color.a = sin(progress * PI) * 0.8
		var turn := sin(_time * 2.4 + phase)
		draw_set_transform(center, _time * 0.9 + phase, Vector2(0.35 + absf(turn) * 0.65, 0.8))
		draw_colored_polygon(_leaf, color)
		draw_line(Vector2(-4, 0), Vector2(4, 0), Color(0.44, 0.53, 0.32, color.a * 0.7), 0.8, true)
		draw_set_transform(Vector2.ZERO)


func _draw_dragonfly(index: int) -> void:
	var phase := float(index) * 3.1
	var drift := _time * 0.63 + phase
	var center := Vector2(555.0 + float(index) * 161.0, 547.0 - float(index) * 32.0)
	center += Vector2(sin(drift) * 51.0, sin(drift * 2.1) * 13.0)
	var wing := 0.35 + absf(sin(_time * 19.0 + phase)) * 0.65
	draw_set_transform(center, sin(drift) * 0.16)
	for side in [-1.0, 1.0]:
		draw_line(Vector2(0, -1), Vector2(side * 9.0, -5.0 * wing), Color(0.91, 0.99, 0.91, 0.65), 2.1, true)
		draw_line(Vector2(0, 1), Vector2(side * 7.0, 4.0 * wing), Color(0.80, 0.93, 0.84, 0.55), 1.8, true)
	draw_line(Vector2(0, -4), Vector2(0, 8), Color("58968d"), 2.0, true)
	draw_circle(Vector2(0, -4), 1.8, Color("497969"), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_butterfly(index: int) -> void:
	var phase := float(index) * 2.4
	var drift := _time * (0.38 + float(index) * 0.04) + phase
	var center: Vector2 = BUTTERFLY_ORIGINS[index] + Vector2(sin(drift) * 41.0, sin(drift * 1.9) * 19.0)
	var angle := sin(drift + 0.8) * 0.25
	var wings := 0.22 + absf(sin(_time * 7.5 + phase)) * 0.78
	var color: Color = BUTTERFLY_COLORS[index]
	draw_set_transform(center, angle, Vector2(wings, 1.0))
	draw_circle(Vector2(-4.0, -1), 4.2, color)
	draw_circle(Vector2(4.0, -1), 4.2, color)
	draw_circle(Vector2(-2.8, 3.8), 2.8, color.darkened(0.08))
	draw_circle(Vector2(2.8, 3.8), 2.8, color.darkened(0.08))
	draw_circle(Vector2(-4.7, -1.5), 1.1, Color("f8e5b1"))
	draw_circle(Vector2(4.7, -1.5), 1.1, Color("f8e5b1"))
	draw_set_transform(center, angle)
	draw_line(Vector2(0, -4), Vector2(0, 6), Color("667357"), 1.4, true)
	draw_line(Vector2(0, -3), Vector2(-2.5, -6), Color("667357"), 0.8, true)
	draw_line(Vector2(0, -3), Vector2(2.5, -6), Color("667357"), 0.8, true)
	draw_set_transform(Vector2.ZERO)
