class_name DogHouse
extends WoodenBlock
## A physical shelter. The level links its destruction to its resident's release.

const SIZE := Vector2(140, 124)
const DOG_OFFSET := Vector2(0, 37)

@export var house_type: StringName = &"classic"


func _ready() -> void:
	var definition := DogHouseTypes.get_definition(house_type)
	house_type = definition.id
	size = definition.size
	super._ready()
	mass *= definition.mass_multiplier
	hits_left += definition.extra_hit_points
	_max_hit_points = hits_left
	if house_type != &"classic":
		var hull := ConvexPolygonShape2D.new()
		hull.points = DogHouseVisual.collision_outline(house_type)
		$CollisionShape2D.shape = hull
	queue_redraw()


func dog_offset() -> Vector2:
	return offset_for(house_type)


func _draw() -> void:
	paint(self, material_id, damage_ratio(), house_type)


static func size_for(type_id: StringName) -> Vector2:
	return DogHouseTypes.get_definition(type_id).size


static func offset_for(type_id: StringName) -> Vector2:
	return DogHouseTypes.get_definition(type_id).dog_offset


static func paint(canvas: CanvasItem, material_id: StringName, damage: float = 0.0, type_id: StringName = &"classic") -> void:
	DogHouseVisual.paint(canvas, material_id, damage, type_id)
