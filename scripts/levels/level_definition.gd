class_name LevelDefinition
extends Resource
## Данные уровня в координатах мира; поверхность земли — y = 620.

const MAX_OBJECTS: int = 200
const BIOMES: Array[StringName] = [&"backyard", &"mountain", &"glacier"]

@export var title: String = "Первый двор"
@export_enum("backyard", "mountain", "glacier") var biome: String = "backyard"
@export_range(1, 20) var shots: int = 4
@export var dog_positions: PackedVector2Array = PackedVector2Array()
@export var block_positions: PackedVector2Array = PackedVector2Array()
@export var block_sizes: PackedVector2Array = PackedVector2Array()
@export var block_materials: PackedStringArray = PackedStringArray()
## Empty entries mark dogs without a shelter; an empty array supports older levels.
@export var dog_house_materials: PackedStringArray = PackedStringArray()
## Older sheltered dogs use the classic shape when this array is empty.
@export var dog_house_types: PackedStringArray = PackedStringArray()
## Empty rosters keep the heroes selected in the menu for older/editor levels.
@export var cat_sequence: PackedStringArray = PackedStringArray()
@export var dog_kinds: PackedStringArray = PackedStringArray()
@export var tutorial: StringName = &""
## Zero disables scoring for older levels; otherwise this is the three-star limit.
@export_range(0, 20) var par_shots: int = 0


func is_valid() -> bool:
	if title.strip_edges().is_empty() or shots < 1 or shots > 20:
		return false
	if StringName(biome) not in BIOMES:
		return false
	if par_shots < 0 or par_shots > shots:
		return false
	if tutorial not in [&"", &"aim", &"ability", &"shelter"]:
		return false
	if not cat_sequence.is_empty() and cat_sequence.size() != shots:
		return false
	if not dog_kinds.is_empty() and dog_kinds.size() != dog_positions.size():
		return false
	for kind in cat_sequence:
		if CharacterCatalog.find_cat(StringName(kind)).id != StringName(kind):
			return false
	for kind in dog_kinds:
		if CharacterCatalog.find_dog(StringName(kind)).id != StringName(kind):
			return false
	if dog_positions.is_empty() or dog_positions.size() > MAX_OBJECTS:
		return false
	if block_positions.size() != block_sizes.size() or block_positions.size() > MAX_OBJECTS:
		return false
	if not block_materials.is_empty() and block_materials.size() != block_positions.size():
		return false
	if not dog_house_materials.is_empty() and dog_house_materials.size() != dog_positions.size():
		return false
	if not dog_house_types.is_empty() and dog_house_types.size() != dog_positions.size():
		return false
	for material_id in block_materials:
		if not BlockMaterials.is_known(material_id):
			return false
	for material_id in dog_house_materials:
		if not material_id.is_empty() and not BlockMaterials.is_known(material_id):
			return false
	for index in dog_house_types.size():
		if dog_house_material_at(index).is_empty():
			if not dog_house_types[index].is_empty():
				return false
		elif not DogHouseTypes.is_known(dog_house_types[index]):
			return false
	for position in dog_positions:
		if not position.is_finite():
			return false
	for position in block_positions:
		if not position.is_finite():
			return false
	for size in block_sizes:
		if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0:
			return false
	return true


func stars_for_shots(shots_used: int) -> int:
	if par_shots == 0:
		return 0
	if shots_used <= par_shots:
		return 3
	return 2 if shots_used <= par_shots + 1 else 1


func block_material_at(index: int) -> StringName:
	return &"wood" if block_materials.is_empty() else StringName(block_materials[index])


func dog_house_material_at(index: int) -> StringName:
	return &"" if dog_house_materials.is_empty() else StringName(dog_house_materials[index])


func dog_house_type_at(index: int) -> StringName:
	if dog_house_material_at(index).is_empty():
		return &""
	return &"classic" if dog_house_types.is_empty() else StringName(dog_house_types[index])


func normalize_materials() -> void:
	if block_materials.is_empty():
		block_materials.resize(block_positions.size())
		block_materials.fill("wood")
	if dog_house_materials.is_empty():
		dog_house_materials.resize(dog_positions.size())
		dog_house_materials.fill("")
	if dog_house_types.is_empty():
		dog_house_types.resize(dog_positions.size())
		for index in dog_positions.size():
			dog_house_types[index] = "" if dog_house_material_at(index).is_empty() else "classic"
