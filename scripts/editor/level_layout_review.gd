class_name LevelLayoutReview
extends RefCounted
## Геометрические подсказки; не заменяют физическую пробу или решение уровня.

const BUILD_AREA := Rect2(400, 100, 840, 520)
const SUPPORT_GAP: float = 4.0
const MESSAGES: Dictionary = {
	&"outside": "За границей поля: передвинь объект внутрь рамки.",
	&"overlap": "Объекты пересекаются: раздвинь их, чтобы избежать резкого толчка на старте.",
	&"unsupported": "Не видно опоры: объект может упасть до первого броска.",
	&"covered": "Плотное укрытие: проверь, можно ли добраться до собаки выбранными котами.",
}


static func objects(level: LevelDefinition) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in level.dog_positions.size():
		var dimensions := Vector2(50, 50)
		var center := level.dog_positions[index]
		var sheltered := not level.dog_house_material_at(index).is_empty()
		if sheltered:
			var type_id := level.dog_house_type_at(index)
			dimensions = DogHouse.size_for(type_id)
			center -= DogHouse.offset_for(type_id)
		var bounds := Rect2(center - dimensions * 0.5, dimensions)
		result.append({"kind": 0, "index": index, "bounds": bounds, "extent": bounds, "solid": sheltered})
	for index in level.block_positions.size():
		var dimensions := level.block_sizes[index]
		var bounds := Rect2(level.block_positions[index] - dimensions * 0.5, dimensions)
		result.append({"kind": 1, "index": index, "bounds": bounds, "extent": bounds, "solid": true})
	for index in level.weight_positions.size():
		var point := level.weight_positions[index]
		var bounds := Rect2(point - HangingWeightVisual.WEIGHT_SIZE * 0.5, HangingWeightVisual.WEIGHT_SIZE)
		result.append({"kind": 2, "index": index, "bounds": bounds, "extent": Rect2(point + HangingWeightVisual.BOUNDS.position, HangingWeightVisual.BOUNDS.size), "solid": true})
	return result


static func inspect(level: LevelDefinition) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	# Незавершённый черновик без собак тоже можно проверить.
	if level == null or level.block_positions.size() != level.block_sizes.size():
		return issues
	var bodies := objects(level)
	var supported: Dictionary = {}
	for slot in bodies.size():
		var body: Dictionary = bodies[slot]
		var bounds: Rect2 = body.bounds
		if not BUILD_AREA.grow(0.1).encloses(body.extent):
			issues.append(_issue(&"outside", body))
		if absf(bounds.end.y - BUILD_AREA.end.y) <= SUPPORT_GAP or body.kind == 2:
			supported[slot] = true
		for other_slot in range(slot):
			if _overlaps(body, bodies[other_slot]):
				issues.append(_issue(&"overlap", body))
				break
	# Обход связей от земли: парящие объекты не поддерживают друг друга.
	# Не более квадратичного числа проверок даже для предельного черновика.
	var dependents: Dictionary = {}
	for lower in bodies.size():
		if not bodies[lower].solid:
			continue
		dependents[lower] = []
		for upper in bodies.size():
			if upper != lower and _supports(bodies[lower].bounds, bodies[upper].bounds):
				dependents[lower].append(upper)
	var queue: Array = supported.keys()
	var cursor := 0
	while cursor < queue.size():
		var lower: int = queue[cursor]
		cursor += 1
		for upper: int in dependents.get(lower, []):
			if not supported.has(upper):
				supported[upper] = true
				queue.append(upper)
	for slot in bodies.size():
		var body: Dictionary = bodies[slot]
		if not supported.has(slot):
			issues.append(_issue(&"unsupported", body))
		if body.kind == 0 and _densely_covered(level, body):
			issues.append(_issue(&"covered", body))
	return issues


static func _supports(lower: Rect2, upper: Rect2) -> bool:
	var gap := lower.position.y - upper.end.y
	var contact := minf(lower.end.x, upper.end.x) - maxf(lower.position.x, upper.position.x)
	return gap >= -2.0 and gap <= SUPPORT_GAP and contact >= minf(8.0, upper.size.x * 0.25)


static func _overlaps(first: Dictionary, second: Dictionary) -> bool:
	var first_circle: bool = first.kind == 0 and not first.solid
	var second_circle: bool = second.kind == 0 and not second.solid
	var first_bounds: Rect2 = first.bounds
	var second_bounds: Rect2 = second.bounds
	if first_circle and second_circle:
		return first_bounds.get_center().distance_to(second_bounds.get_center()) < 48.0
	if first_circle:
		var center := first_bounds.get_center()
		return center.distance_to(center.clamp(second_bounds.position, second_bounds.end)) < 23.0
	if second_circle:
		return _overlaps(second, first)
	var intersection := first_bounds.intersection(second_bounds)
	return intersection.size.x > 2.0 and intersection.size.y > 2.0


static func _densely_covered(level: LevelDefinition, dog: Dictionary) -> bool:
	if level.dog_house_material_at(dog.index) in [&"stone", &"metal"]:
		return true
	var center: Vector2 = level.dog_positions[dog.index]
	var sides := [false, false, false]
	for index in level.block_positions.size():
		if level.block_material_at(index) not in [&"stone", &"metal"]:
			continue
		var bounds := Rect2(level.block_positions[index] - level.block_sizes[index] * 0.5, level.block_sizes[index])
		if center.y >= bounds.position.y and center.y <= bounds.end.y:
			sides[0] = sides[0] or (center.x - bounds.end.x >= 25.0 and center.x - bounds.end.x <= 100.0)
			sides[1] = sides[1] or (bounds.position.x - center.x >= 25.0 and bounds.position.x - center.x <= 100.0)
		if center.x >= bounds.position.x and center.x <= bounds.end.x:
			sides[2] = sides[2] or (center.y - bounds.end.y >= 25.0 and center.y - bounds.end.y <= 100.0)
	return sides[0] and sides[1] and sides[2]


static func _issue(code: StringName, body: Dictionary) -> Dictionary:
	return {"code": code, "kind": body.kind, "index": body.index}


static func describe(issue: Dictionary) -> String:
	var names: Array[String] = ["Собака", "Блок", "Подвешенный груз"]
	return "%s %d · %s" % [TranslationServer.translate(names[issue.kind]), issue.index + 1, TranslationServer.translate(MESSAGES[issue.code])]
