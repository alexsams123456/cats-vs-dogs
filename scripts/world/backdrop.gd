extends Node2D
## Кэшируемый пейзаж; ветер и живые детали рисуются отдельным слоем.

const AMBIENT_LIFE := preload("res://scripts/world/ambient_life.gd")
const SCENERY_PINE := preload("res://scripts/world/scenery_pine.gd")
const BACKYARD_STREAM := [Vector2(755, 455), Vector2(700, 466), Vector2(754, 482), Vector2(825, 494), Vector2(791, 510), Vector2(661, 529), Vector2(601, 546), Vector2(613, 568), Vector2(515, 594), Vector2(410, 620)]
const MOUNTAIN_STREAM := [Vector2(873, 476), Vector2(792, 496), Vector2(836, 515), Vector2(747, 539), Vector2(661, 567), Vector2(713, 589), Vector2(607, 620)]
const GROUND_Y: float = 620.0
const WORLD_LEFT: float = -2200.0
const WORLD_RIGHT: float = 3500.0

var animation_time: float = 0.0
var biome: StringName = &"backyard"
var _ambient: AmbientLife


func _ready() -> void:
	_ambient = AMBIENT_LIFE.new()
	_ambient.name = "AmbientLife"
	_ambient.biome = biome
	add_child(_ambient)
	_ambient.set_water_path(_water_path())


func set_biome(value: StringName) -> void:
	biome = value if value in [&"backyard", &"mountain", &"glacier"] else &"backyard"
	if is_instance_valid(_ambient):
		_ambient.set_biome(biome)
		_ambient.set_water_path(_water_path())
	queue_redraw()


func _process(delta: float) -> void:
	animation_time += delta
	var visible_world := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	_ambient.advance(delta, animation_time, visible_world)


func _draw() -> void:
	if biome == &"mountain":
		_draw_mountain_valley()
		return
	if biome == &"glacier":
		_draw_glacial_valley()
		return
	_draw_sky()
	_draw_highlands()
	_draw_meadow()
	_draw_stream()
	_draw_distant_grove()
	_draw_backyard_house()
	_draw_fence()
	_draw_garden()
	_draw_ground()


func _draw_sky() -> void:
	draw_rect(Rect2(WORLD_LEFT, -1600, WORLD_RIGHT - WORLD_LEFT, 2300), Color("a9d6d6"))
	_gradient_rect(Rect2(WORLD_LEFT, -80, WORLD_RIGHT - WORLD_LEFT, 340), Color("a9d6d6"), Color("dce9d5"))
	_gradient_rect(Rect2(WORLD_LEFT, 260, WORLD_RIGHT - WORLD_LEFT, 380), Color("dce9d5"), Color("f3e7be"))
	_ellipse(Vector2(305, 285), Vector2(225, 9), Color(0.99, 0.97, 0.85, 0.16))
	_ellipse(Vector2(865, 320), Vector2(315, 13), Color(0.99, 0.97, 0.85, 0.18))
	_ellipse(Vector2(1420, 256), Vector2(190, 7), Color(0.99, 0.97, 0.85, 0.14))


func _draw_highlands() -> void:
	_landform(PackedVector2Array([
		Vector2(WORLD_LEFT, 400), Vector2(-370, 377), Vector2(-140, 352),
		Vector2(55, 299), Vector2(145, 315), Vector2(290, 355),
		Vector2(435, 344), Vector2(615, 390), Vector2(780, 362),
		Vector2(961, 287), Vector2(1065, 301), Vector2(1185, 330),
		Vector2(1340, 304), Vector2(1560, 365), Vector2(WORLD_RIGHT, 400)
	]), Color("b3cdd0"), Color("dae1c3"))
	_landform(PackedVector2Array([
		Vector2(WORLD_LEFT, 435), Vector2(-260, 400), Vector2(-75, 386),
		Vector2(80, 349), Vector2(215, 391), Vector2(310, 377),
		Vector2(480, 435), Vector2(635, 454), Vector2(795, 397),
		Vector2(944, 365), Vector2(1070, 385), Vector2(1190, 352),
		Vector2(1380, 411), Vector2(1620, 390), Vector2(WORLD_RIGHT, 440)
	]), Color("8fb6b7"), Color("c6d5b3"))
	_patch(PackedVector2Array([
		Vector2(-90, 398), Vector2(77, 356), Vector2(173, 382),
		Vector2(127, 406), Vector2(206, 462), Vector2(73, 433), Vector2(-90, 441)
	]), Color("a7c5bc"))
	_patch(PackedVector2Array([
		Vector2(817, 399), Vector2(943, 372), Vector2(1031, 389),
		Vector2(973, 408), Vector2(990, 444), Vector2(899, 425), Vector2(816, 449)
	]), Color("a8c5b7"))
	_landform(PackedVector2Array([
		Vector2(WORLD_LEFT, 500), Vector2(-260, 456), Vector2(-35, 434),
		Vector2(135, 454), Vector2(300, 477), Vector2(482, 459),
		Vector2(652, 471), Vector2(810, 452), Vector2(992, 438),
		Vector2(1167, 464), Vector2(1325, 447), Vector2(1530, 478),
		Vector2(WORLD_RIGHT, 490)
	]), Color("78a993"), Color("c0ce98"))
	_patch(PackedVector2Array([
		Vector2(-190, 482), Vector2(-30, 447), Vector2(100, 468),
		Vector2(270, 488), Vector2(396, 480), Vector2(304, 516),
		Vector2(113, 501), Vector2(-77, 517)
	]), Color("9dbb94"))
	_patch(PackedVector2Array([
		Vector2(875, 466), Vector2(1024, 451), Vector2(1180, 478),
		Vector2(1390, 465), Vector2(1502, 495), Vector2(1288, 507),
		Vector2(1100, 488), Vector2(934, 499)
	]), Color("b0c790"))


func _draw_meadow() -> void:
	_landform(PackedVector2Array([
		Vector2(WORLD_LEFT, 545), Vector2(-300, 510), Vector2(-50, 519),
		Vector2(157, 540), Vector2(370, 525), Vector2(558, 537),
		Vector2(732, 526), Vector2(942, 514), Vector2(1170, 538),
		Vector2(1380, 523), Vector2(1610, 536), Vector2(WORLD_RIGHT, 550)
	]), Color("a8c187"), Color("8fb07a"))
	_patch(PackedVector2Array([
		Vector2(-110, 548), Vector2(106, 556), Vector2(309, 539),
		Vector2(463, 550), Vector2(317, 562), Vector2(243, 581), Vector2(34, 570)
	]), Color("bed097"))
	_patch(PackedVector2Array([
		Vector2(704, 553), Vector2(897, 531), Vector2(1140, 550),
		Vector2(1320, 539), Vector2(1420, 565), Vector2(1140, 577),
		Vector2(907, 559), Vector2(787, 571)
	]), Color("bbcc8c"))
	var random := RandomNumberGenerator.new()
	random.seed = 7321
	for index in 110:
		var point := Vector2(random.randf_range(-180, 1500), random.randf_range(543, 615))
		var width := random.randf_range(1.2, 4.5)
		var color := Color("d1dba3") if index % 3 == 0 else Color("7ea475")
		color.a = 0.42
		_ellipse(point, Vector2(width, 0.8), color)


func _draw_stream() -> void:
	var centers := _water_path()
	_stream_ribbon(centers, 5.0, Color("cbd3a0"), Color("c5d29a"))
	_stream_ribbon(centers, 0.0, Color("c2dcce"), Color("81b8af"))
	for index in 12:
		var sample_index := 35 + index * 8
		var point := centers[mini(sample_index, centers.size() - 1)]
		var depth := clampf((point.y - 455.0) / 165.0, 0.0, 1.0)
		var half_width := 2.0 + depth * depth * 28.0
		draw_line(point - Vector2(half_width, 0), point + Vector2(half_width, 0), Color(0.9, 0.95, 0.8, 0.28), 1.0, true)
	for stone: Vector3 in [Vector3(551, 584, 7), Vector3(558, 587, 4), Vector3(667, 540, 4), Vector3(465, 616, 9)]:
		_ellipse(Vector2(stone.x, stone.y + 2), Vector2(stone.z + 2, stone.z * 0.35), Color("739c84"))
		_ellipse(Vector2(stone.x, stone.y), Vector2(stone.z, stone.z * 0.55), Color("c6ceb0"))


func _draw_distant_grove() -> void:
	for tree: Vector3 in [Vector3(18, 495, 0.65), Vector3(59, 501, 0.85), Vector3(94, 505, 0.7), Vector3(1068, 512, 0.65), Vector3(1101, 517, 0.9), Vector3(1151, 516, 0.8), Vector3(1181, 520, 0.55)]:
		var root := Vector2(tree.x, tree.y)
		var size := tree.z
		draw_line(root, root - Vector2(0, 32 * size), Color("749c83"), 3.0 * size, true)
		_ellipse(root - Vector2(0, 33 * size), Vector2(19, 27) * size, Color("78a48b"))
		_ellipse(root - Vector2(5, 42) * size, Vector2(15, 19) * size, Color("8eb496"))


func _draw_fence() -> void:
	# Выцветший забор остаётся второстепенным относительно целей.
	draw_rect(Rect2(701, 575, 575, 7), Color("afbb8c"))
	draw_rect(Rect2(701, 604, 575, 6), Color("afbb8c"))
	for x in range(710, 1270, 57):
		var top := 553.0 + sin(float(x) * 0.031) * 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, GROUND_Y), Vector2(x, top + 5), Vector2(x + 6, top),
			Vector2(x + 13, top + 5), Vector2(x + 13, GROUND_Y)
		]), Color("d2d3a5"))
		draw_line(Vector2(x + 2, top + 7), Vector2(x + 2, 616), Color("e2dfb6"), 2.0)
	draw_rect(Rect2(701, 571, 575, 7), Color("d7d7ab"))
	draw_rect(Rect2(701, 601, 575, 5), Color("cbd0a0"))
	for x in range(716, 1270, 57):
		draw_circle(Vector2(x, 574), 1.0, Color("99aa88"))


func _draw_ground() -> void:
	draw_rect(Rect2(WORLD_LEFT, GROUND_Y, WORLD_RIGHT - WORLD_LEFT, 1500), Color("eadcbd"))
	_gradient_rect(Rect2(WORLD_LEFT, 632, WORLD_RIGHT - WORLD_LEFT, 160), Color("d5bd92"), Color("eadcbd"))
	var turf := PackedVector2Array([Vector2(WORLD_LEFT, GROUND_Y), Vector2(WORLD_RIGHT, GROUND_Y)])
	for index in range(285, -1, -1):
		var x := WORLD_LEFT + float(index) * 20.0
		turf.append(Vector2(x, 632.0 + sin(x * 0.031) * 2.0 + sin(x * 0.092) * 1.0))
	draw_colored_polygon(turf, Color("638e66"))
	draw_rect(Rect2(WORLD_LEFT, GROUND_Y, WORLD_RIGHT - WORLD_LEFT, 4), Color("b2c580"))
	var random := RandomNumberGenerator.new()
	random.seed = 118
	for index in 72:
		var center := Vector2(random.randf_range(-180, 1500), random.randf_range(641, 805))
		var tint := Color("c5ae88") if index % 3 == 0 else Color("f2e4c6")
		tint.a = 0.38
		_ellipse(center, Vector2(random.randf_range(1.0, 3.8), random.randf_range(0.7, 1.5)), tint)


func _draw_backyard_house() -> void:
	# Дом стоит за садом: его силуэт не выглядит частью разрушаемой постройки.
	draw_rect(Rect2(175, 365, 259, 178), Color("d9c7a1"))
	draw_rect(Rect2(357, 365, 77, 178), Color("bead91"))
	for y in range(382, 543, 20):
		draw_line(Vector2(177, y), Vector2(431, y), Color("cbbd9e"), 1.5)
	draw_rect(Rect2(376, 300, 21, 64), Color("b5937e"))
	draw_rect(Rect2(372, 296, 29, 8), Color("a48672"))
	draw_colored_polygon(PackedVector2Array([Vector2(143, 372), Vector2(260, 281), Vector2(354, 296), Vector2(454, 363), Vector2(442, 377), Vector2(162, 384)]), Color("978577"))
	draw_colored_polygon(PackedVector2Array([Vector2(168, 368), Vector2(262, 298), Vector2(359, 368)]), Color("e7d8b5"))
	draw_line(Vector2(263, 285), Vector2(451, 364), Color("b79c84"), 7.0, true)
	for index in 6:
		var offset := float(index) * 15.0
		draw_line(Vector2(285 + offset, 311 + offset * 0.39), Vector2(349 + offset, 363 + offset * 0.12), Color("a48c79"), 1.5, true)
	_house_window(Vector2(203, 407), Vector2(48, 56))
	_house_window(Vector2(296, 407), Vector2(48, 56))
	_house_window(Vector2(241, 339), Vector2(36, 34))
	draw_rect(Rect2(376, 426, 39, 114), Color("8d9c87"))
	draw_rect(Rect2(382, 432, 27, 41), Color("b2c9bd"))
	draw_circle(Vector2(407, 489), 2.0, Color("e6d4a3"))
	draw_rect(Rect2(364, 538, 65, 7), Color("b8ad94"))
	draw_rect(Rect2(355, 545, 83, 6), Color("ccc2a7"))
	for x in [210, 303]:
		draw_rect(Rect2(x - 7, 467, 58, 9), Color("b2947a"))
		for flower in 6:
			var point := Vector2(float(x + flower * 8), 464.0 + sin(float(flower) * 2.0) * 3.0)
			draw_circle(point, 5.0, Color("7e9b6e"))
			draw_circle(point - Vector2(0, 4), 2.6, Color("d8a8a1") if flower % 2 == 0 else Color("ece0aa"))
	# Небольшая пергола и мягкая лиственная изгородь связывают дом с двором.
	for x in [470, 556]:
		draw_rect(Rect2(x, 469, 6, 97), Color("b7af8a"))
	draw_rect(Rect2(456, 466, 120, 6), Color("cbc39c"))
	for x in range(465, 578, 21):
		draw_line(Vector2(x, 458), Vector2(x - 8, 482), Color("aca783"), 4.0)
	for index in 9:
		_ellipse(Vector2(458 + index * 14, 466 + sin(float(index)) * 5), Vector2(15, 8), Color("91ac7d"))
	for index in 11:
		_ellipse(Vector2(182 + index * 20, 547 - sin(float(index) * 1.4) * 5), Vector2(22, 14), Color("88a477"))


func _house_window(origin: Vector2, size: Vector2) -> void:
	draw_rect(Rect2(origin - Vector2(4, 4), size + Vector2(8, 8)), Color("f1e2bc"))
	draw_rect(Rect2(origin, size), Color("95b5b1"))
	draw_colored_polygon(PackedVector2Array([origin, origin + Vector2(size.x, 0), origin + Vector2(0, size.y)]), Color("bed3c6"))
	draw_line(origin + Vector2(size.x * 0.5, 0), origin + Vector2(size.x * 0.5, size.y), Color("eee0bc"), 3.0)
	draw_line(origin + Vector2(0, size.y * 0.5), origin + Vector2(size.x, size.y * 0.5), Color("eee0bc"), 3.0)


func _draw_garden() -> void:
	for index in 6:
		_ellipse(Vector2(403 + index * 18, 563 + index * 6), Vector2(13 + index, 3.5), Color("c6ca9a"))
	# Приподнятая грядка, лейка и горшки живут за игровой поверхностью.
	draw_rect(Rect2(66, 592, 86, 24), Color("b29a78"))
	draw_rect(Rect2(61, 589, 95, 6), Color("d1b895"))
	for index in 6:
		var root := Vector2(72 + index * 14, 590)
		draw_line(root, root - Vector2(3, 14), Color("759269"), 3.0)
		_ellipse(root - Vector2(6, 11), Vector2(7, 3), Color("91ac73"))
		_ellipse(root + Vector2(4, -17), Vector2(6, 3), Color("809d6c"))
	for pot: Vector2 in [Vector2(458, 614), Vector2(500, 617)]:
		draw_colored_polygon(PackedVector2Array([pot + Vector2(-12, -18), pot + Vector2(12, -18), pot + Vector2(8, 0), pot + Vector2(-8, 0)]), Color("c09a7b"))
		draw_line(pot + Vector2(-14, -19), pot + Vector2(14, -19), Color("d9b58d"), 4.0)
		for stem in 3:
			var flower := pot + Vector2(float(stem - 1) * 8.0, -33.0 - float(stem % 2) * 9.0)
			draw_line(pot - Vector2(0, 19), flower, Color("719165"), 2.0)
			draw_circle(flower, 5.0, Color("e2bcaa"))
			draw_circle(flower, 2.0, Color("eee0aa"))
	draw_arc(Vector2(562, 599), 11, -PI * 0.8, PI * 0.8, 20, Color("83a29a"), 3.0, true)
	draw_rect(Rect2(541, 590, 22, 25), Color("96b3a6"))
	draw_line(Vector2(543, 599), Vector2(526, 585), Color("96b3a6"), 6.0, true)
	draw_line(Vector2(522, 586), Vector2(529, 580), Color("b5c8ad"), 4.0, true)


func _draw_mountain_valley() -> void:
	draw_rect(Rect2(WORLD_LEFT, -1600, WORLD_RIGHT - WORLD_LEFT, 2300), Color("91b8cf"))
	_gradient_rect(Rect2(WORLD_LEFT, -40, WORLD_RIGHT - WORLD_LEFT, 670), Color("91b8cf"), Color("e4e2ce"))
	for peak: Vector3 in [Vector3(-180, 448, 270), Vector3(204, 425, 289), Vector3(547, 455, 218), Vector3(978, 442, 300), Vector3(1397, 438, 252)]:
		_mountain_peak(Vector2(peak.x, peak.y), 460, peak.z, Color("a0b9c2"), Color("e3e7df"))
	_mountain_peak(Vector2(485, 523), 550, 280, Color("7e9ca7"), Color("e1e5d8"))
	_mountain_peak(Vector2(1265, 530), 537, 325, Color("7598a4"), Color("dce4de"))
	var forest_ridge := PackedVector2Array([Vector2(WORLD_LEFT, 504), Vector2(-190, 406), Vector2(62, 463), Vector2(235, 499), Vector2(417, 469), Vector2(628, 516), Vector2(822, 485), Vector2(1014, 516), Vector2(1235, 455), Vector2(1491, 467), Vector2(WORLD_RIGHT, 492)])
	_landform(forest_ridge, Color("6f968a"), Color("b4bf96"))
	var forest_edge := _smooth_path(forest_ridge, false, true)
	for index in 36:
		var x := -180.0 + float(index) * 47.0
		var y := 520.0
		for sample in range(1, forest_edge.size()):
			if forest_edge[sample].x >= x:
				var before := forest_edge[sample - 1]
				var after := forest_edge[sample]
				y = lerpf(before.y, after.y, inverse_lerp(before.x, after.x, x)) + 12.0
				break
		_pine(Vector2(x, y), 31.0 + float(index * 19 % 36), Color("709487"))
	_landform(PackedVector2Array([Vector2(WORLD_LEFT, 562), Vector2(-161, 520), Vector2(47, 531), Vector2(287, 550), Vector2(507, 549), Vector2(734, 543), Vector2(948, 558), Vector2(1190, 523), Vector2(1409, 532), Vector2(WORLD_RIGHT, 545)]), Color("8faa8d"), Color("b9c395"))
	# Холодная горная река шире лугового ручья; обломки породы подчёркивают масштаб.
	var river := _water_path()
	_stream_ribbon(river, 8.0, Color("c4cbb5"), Color("b5bea2"))
	_stream_ribbon(river, 0.0, Color("bcd6ce"), Color("70b0b3"))
	for item: Vector3 in [Vector3(91, 619, 30), Vector3(378, 619, 25), Vector3(449, 615, 17), Vector3(652, 599, 15), Vector3(1169, 619, 24), Vector3(1261, 612, 38), Vector3(1409, 620, 45)]:
		_boulder(Vector2(item.x, item.y), item.z, Color("98a99a"))
	_draw_alpine_ground(false)


func _mountain_peak(base: Vector2, width: float, height: float, tint: Color, snow: Color) -> void:
	# Основание уходит под ближние холмы, не оставляя горизонтального среза в небе.
	height += GROUND_Y - base.y
	base.y = GROUND_Y
	var peak := base - Vector2(width * 0.06, height)
	var left := base - Vector2(width * 0.55, 0)
	var right := base + Vector2(width * 0.55, 0)
	draw_colored_polygon(PackedVector2Array([left, peak + Vector2(-width * 0.16, height * 0.32), peak, peak + Vector2(width * 0.17, height * 0.29), right]), tint)
	draw_colored_polygon(PackedVector2Array([peak, peak + Vector2(width * 0.17, height * 0.29), right, base - Vector2(width * 0.04, 0), peak + Vector2(width * 0.05, height * 0.49)]), tint.darkened(0.1))
	draw_colored_polygon(PackedVector2Array([peak + Vector2(-width * 0.16, height * 0.32), peak, peak + Vector2(width * 0.17, height * 0.29), peak + Vector2(width * 0.065, height * 0.22), peak + Vector2(width * 0.043, height * 0.36), peak + Vector2(-width * 0.015, height * 0.19), peak + Vector2(-width * 0.081, height * 0.31), peak + Vector2(-width * 0.093, height * 0.24)]), snow)
	draw_line(peak + Vector2(width * 0.047, height * 0.43), base + Vector2(width * 0.18, -height * 0.08), tint.lightened(0.06), 2.0, true)


func _pine(root: Vector2, height: float, tint: Color) -> void:
	SCENERY_PINE.draw_tree(self, root, height, tint)


func _water_path() -> PackedVector2Array:
	if biome == &"glacier":
		return PackedVector2Array()
	return _smooth_path(PackedVector2Array(MOUNTAIN_STREAM if biome == &"mountain" else BACKYARD_STREAM))


func _boulder(root: Vector2, size: float, tint: Color) -> void:
	var points := PackedVector2Array([root + Vector2(-size, 0), root + Vector2(-size * 0.77, -size * 0.52), root + Vector2(-size * 0.18, -size * 0.75), root + Vector2(size * 0.60, -size * 0.55), root + Vector2(size, -size * 0.08), root + Vector2(size * 0.68, size * 0.03)])
	draw_colored_polygon(points, tint)
	draw_colored_polygon(PackedVector2Array([points[1], points[2], points[3], root - Vector2(size * 0.23, size * 0.28)]), tint.lightened(0.15))
	draw_line(points[2], root + Vector2(size * 0.13, -size * 0.20), tint.darkened(0.13), 1.4, true)


func _draw_glacial_valley() -> void:
	draw_rect(Rect2(WORLD_LEFT, -1600, WORLD_RIGHT - WORLD_LEFT, 2300), Color("9ebdce"))
	_gradient_rect(Rect2(WORLD_LEFT, -60, WORLD_RIGHT - WORLD_LEFT, 660), Color("9ebdce"), Color("c6dfe2"))
	var random := RandomNumberGenerator.new()
	random.seed = 281
	for index in 55:
		var point := Vector2(random.randf_range(-200, 1500), random.randf_range(40, 290))
		draw_circle(point, random.randf_range(0.6, 1.3), Color(0.87, 0.97, 1.0, random.randf_range(0.20, 0.55)), true, -1.0, true)
	for peak: Vector3 in [Vector3(-60, 492, 231), Vector3(280, 485, 272), Vector3(670, 495, 218), Vector3(1040, 470, 295), Vector3(1425, 490, 265)]:
		_mountain_peak(Vector2(peak.x, peak.y), 420, peak.z, Color("8aaec6"), Color("c3dce7"))
	_landform(PackedVector2Array([Vector2(WORLD_LEFT, 510), Vector2(-137, 450), Vector2(174, 493), Vector2(417, 472), Vector2(709, 516), Vector2(994, 472), Vector2(1224, 491), Vector2(1510, 451), Vector2(WORLD_RIGHT, 512)]), Color("c7dfe4"), Color("e7eff0"))
	# Две стены ледника образуют проход; вертикальные грани отличаются от горных склонов.
	_glacier_wall(PackedVector2Array([Vector2(-270, 521), Vector2(-188, 394), Vector2(-111, 376), Vector2(-57, 425), Vector2(19, 405), Vector2(84, 473), Vector2(145, 462), Vector2(217, 527), Vector2(276, 513), Vector2(333, 576)]), false)
	_glacier_wall(PackedVector2Array([Vector2(1015, 553), Vector2(1074, 507), Vector2(1142, 518), Vector2(1219, 430), Vector2(1278, 445), Vector2(1336, 386), Vector2(1419, 404), Vector2(1491, 376), Vector2(1598, 490)]), true)
	_landform(PackedVector2Array([Vector2(WORLD_LEFT, 586), Vector2(-190, 569), Vector2(132, 588), Vector2(416, 556), Vector2(628, 570), Vector2(822, 548), Vector2(1024, 573), Vector2(1283, 566), Vector2(1480, 587), Vector2(WORLD_RIGHT, 578)]), Color("deebed"), Color("f0f3ed"))
	_patch(PackedVector2Array([Vector2(442, 586), Vector2(593, 561), Vector2(758, 570), Vector2(876, 564), Vector2(1056, 599), Vector2(991, 619), Vector2(701, 626), Vector2(510, 614)]), Color("afcedb"))
	_patch(PackedVector2Array([Vector2(496, 589), Vector2(661, 577), Vector2(857, 578), Vector2(976, 601), Vector2(799, 608), Vector2(602, 612)]), Color("c6e1e6"))
	for points: PackedVector2Array in [PackedVector2Array([Vector2(584, 595), Vector2(642, 586), Vector2(679, 597), Vector2(737, 591)]), PackedVector2Array([Vector2(781, 602), Vector2(815, 591), Vector2(872, 595), Vector2(903, 588)])]:
		draw_polyline(points, Color("95bdcf"), 1.3, true)
	for item: Vector3 in [Vector3(65, 619, 42), Vector3(128, 616, 25), Vector3(397, 618, 26), Vector3(1182, 618, 29), Vector3(1279, 619, 61), Vector3(1428, 618, 40)]:
		_ice_crystal(Vector2(item.x, item.y), item.z)
	_draw_alpine_ground(true)


func _glacier_wall(ridge: PackedVector2Array, flipped: bool) -> void:
	var outline := ridge.duplicate()
	outline.append(Vector2(ridge[-1].x, 619))
	outline.append(Vector2(ridge[0].x, 619))
	draw_colored_polygon(outline, Color("95c3d6"))
	for index in range(ridge.size() - 1):
		var start := ridge[index]
		var end := ridge[index + 1]
		var offset := 17.0 if flipped else -17.0
		draw_colored_polygon(PackedVector2Array([start, end, Vector2(end.x + offset, 619), Vector2(start.x + offset, 619)]), Color("afd6e2") if index % 2 == 0 else Color("82b2ca"))
		draw_line(start + Vector2(offset * 0.3, 23), Vector2(start.x + offset * 0.6, 584), Color(0.82, 0.95, 0.98, 0.3), 2.0, true)
		var snow := PackedVector2Array([start, end, end + Vector2(-4, 9), start + Vector2(3, 11)])
		draw_colored_polygon(snow, Color("e2eff0"))


func _ice_crystal(root: Vector2, height: float) -> void:
	for index in 3:
		var x := float(index - 1) * height * 0.23
		var tip := root + Vector2(x * 1.35, -height * (1.0 if index == 1 else 0.60))
		var left := root + Vector2(x - height * 0.17, 0)
		var right := root + Vector2(x + height * 0.17, 0)
		var facet := tip + Vector2(height * 0.07, height * 0.22)
		draw_colored_polygon(PackedVector2Array([left, tip - Vector2(height * 0.08, -height * 0.14), tip, facet, right]), Color("a3d5e1"))
		draw_colored_polygon(PackedVector2Array([tip, facet, right, root + Vector2(x, 0)]), Color("7bb8d0"))
		draw_line(tip, left, Color("e9f8f3"), 1.7, true)
	_ellipse(root + Vector2(0, 1), Vector2(height * 0.65, 3), Color("edf5ef"))


func _draw_alpine_ground(frozen: bool) -> void:
	var top := Color("dae9e9") if frozen else Color("c3baa1")
	var bottom := Color("90bacf") if frozen else Color("a49e8c")
	draw_rect(Rect2(WORLD_LEFT, GROUND_Y, WORLD_RIGHT - WORLD_LEFT, 1500), bottom)
	_gradient_rect(Rect2(WORLD_LEFT, GROUND_Y + 9, WORLD_RIGHT - WORLD_LEFT, 140), top, bottom)
	draw_rect(Rect2(WORLD_LEFT, GROUND_Y, WORLD_RIGHT - WORLD_LEFT, 8), Color("f2f5ef") if frozen else Color("9eaf83"))
	var random := RandomNumberGenerator.new()
	random.seed = 884
	for index in 78:
		var point := Vector2(random.randf_range(-200, 1500), random.randf_range(640, 782))
		if frozen:
			draw_line(point, point + Vector2(random.randf_range(4, 19), random.randf_range(2, 12)), Color(0.82, 0.93, 0.96, 0.35), 1.4, true)
		else:
			_boulder(point, random.randf_range(1.5, 4.0), Color("96998a") if index % 2 == 0 else Color("d3cbb4"))


func _landform(anchors: PackedVector2Array, top: Color, bottom: Color) -> void:
	var outline := _smooth_path(anchors, false, true)
	var colors := PackedColorArray()
	for point in outline:
		colors.append(top.lerp(bottom, clampf((point.y - 300.0) / 380.0, 0.0, 1.0)))
	draw_polyline_colors(outline, colors, 1.0, true)
	outline.append(Vector2(anchors[-1].x, GROUND_Y))
	outline.append(Vector2(anchors[0].x, GROUND_Y))
	colors.append(bottom)
	colors.append(bottom)
	draw_polygon(outline, colors)


func _patch(anchors: PackedVector2Array, color: Color) -> void:
	var outline := _smooth_path(anchors, true)
	draw_colored_polygon(outline, color)
	outline.append(outline[0])
	draw_polyline(outline, color, 1.0, true)


func _smooth_path(anchors: PackedVector2Array, closed: bool = false, horizontal: bool = false) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := anchors.size()
	var segment_count := count if closed else count - 1
	for index in segment_count:
		var before := anchors[posmod(index - 1, count) if closed else maxi(0, index - 1)]
		var start := anchors[index]
		var finish := anchors[(index + 1) % count]
		var after := anchors[(index + 2) % count if closed else mini(count - 1, index + 2)]
		var control_a := start + (finish - before) / 6.0
		var control_b := finish - (after - start) / 6.0
		if horizontal:
			# Далёкие опорные точки не должны заворачивать силуэт назад.
			control_a.x = clampf(control_a.x, start.x, finish.x)
			control_b.x = clampf(control_b.x, start.x, finish.x)
		for step in 16:
			result.append(start.bezier_interpolate(control_a, control_b, finish, float(step) / 16.0))
	if not closed:
		result.append(anchors[-1])
	return result


func _stream_ribbon(centers: PackedVector2Array, bank: float, top: Color, bottom: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var colors := PackedColorArray()
	for center in centers:
		var depth := clampf((center.y - 455.0) / 165.0, 0.0, 1.0)
		var width := 1.0 + depth * depth * 49.0 + bank * depth
		left.append(center - Vector2(width, 0))
		right.append(center + Vector2(width, 0))
		colors.append(top.lerp(bottom, depth))
	var other_colors := colors.duplicate()
	right.reverse()
	other_colors.reverse()
	left.append_array(right)
	colors.append_array(other_colors)
	draw_polygon(left, colors)


func _gradient_rect(rect: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)
	]), PackedColorArray([top, top, bottom, bottom]))


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, radius.y / radius.x))
	draw_circle(Vector2.ZERO, radius.x, color, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
