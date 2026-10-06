class_name BuildingTemplates
extends RefCounted
## Готовые фрагменты уровня; их параметры остаются в ресурсах levels/buildings.

const CENTER_X: float = 820.0
const LEVELS: Array[LevelDefinition] = [
	preload("res://levels/buildings/bridge.tres"),
	preload("res://levels/buildings/tower.tres"),
	preload("res://levels/buildings/weight_trap.tres"),
]
const HINTS: Array[String] = [
	"Две цели под мостом. Разрушь одну из опор.",
	"Цели на двух этажах. Попробуй обрушить верхний этаж.",
	"Попади в верёвку: груз пробьёт стеклянную крышу.",
]


static func bounds_for(level: LevelDefinition) -> Rect2:
	var bounds := Rect2()
	for body: Dictionary in LevelLayoutReview.objects(level):
		bounds = body.extent if not bounds.has_area() else bounds.merge(body.extent)
	return bounds


static func at_position(index: int, point: Vector2) -> LevelDefinition:
	var level := LEVELS[index].duplicate(true) as LevelDefinition
	var bounds := bounds_for(level)
	var left := LevelLayoutReview.BUILD_AREA.position.x - bounds.position.x
	var right := LevelLayoutReview.BUILD_AREA.end.x - bounds.end.x
	var offset := Vector2(clampf(point.x - CENTER_X, left, right), 0)
	level.dog_positions = _shift(level.dog_positions, offset)
	level.block_positions = _shift(level.block_positions, offset)
	level.weight_positions = _shift(level.weight_positions, offset)
	return level


static func placement_error(draft: LevelDefinition, addition: LevelDefinition) -> String:
	if draft.dog_positions.size() + addition.dog_positions.size() > LevelDefinition.MAX_OBJECTS or draft.block_positions.size() + addition.block_positions.size() > LevelDefinition.MAX_OBJECTS or draft.weight_positions.size() + addition.weight_positions.size() > LevelDefinition.MAX_OBJECTS:
		return "Для постройки не хватает места в лимите объектов. Удали несколько объектов."
	var bounds := bounds_for(addition).grow(-0.1)
	for body: Dictionary in LevelLayoutReview.objects(draft):
		if bounds.intersects(body.extent.grow(-0.1)):
			return "Здесь уже есть объекты. Выбери свободное место для всей постройки."
	return ""


static func append_to(draft: LevelDefinition, addition: LevelDefinition) -> void:
	draft.normalize_materials()
	addition.normalize_materials()
	draft.dog_positions.append_array(addition.dog_positions)
	draft.dog_house_materials.append_array(addition.dog_house_materials)
	draft.dog_house_types.append_array(addition.dog_house_types)
	if not draft.dog_kinds.is_empty():
		draft.dog_kinds.append_array(addition.dog_kinds)
	draft.block_positions.append_array(addition.block_positions)
	draft.block_sizes.append_array(addition.block_sizes)
	draft.block_materials.append_array(addition.block_materials)
	draft.weight_positions.append_array(addition.weight_positions)


static func _shift(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := points.duplicate()
	for index in result.size():
		result[index] += offset
	return result
