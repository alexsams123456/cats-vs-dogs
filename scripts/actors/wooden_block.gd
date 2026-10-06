class_name WoodenBlock
extends DestructibleBody

signal destroyed
signal material_hit(material_id: StringName)

@export var size: Vector2 = Vector2(34, 140)
@export var material_id: StringName = &"wood"

var hits_left: int = 1
var _max_hit_points: int = 1


func _ready() -> void:
	var material := BlockMaterials.get_definition(material_id)
	material_id = material.id
	mass = material.mass
	impact_threshold = material.impact_threshold
	hits_left = material.hit_points
	_max_hit_points = hits_left
	var surface := PhysicsMaterial.new()
	surface.friction = material.friction
	physics_material_override = surface
	# Each instance gets its own shape, so level data can resize individual beams.
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	$CollisionShape2D.shape = rectangle
	queue_redraw()


func receive_hit(strength: float) -> void:
	if not _can_receive_hit(strength):
		return
	_hit_cooldown_left = hit_cooldown_seconds
	impact_received.emit(strength)
	var damage: int = maxi(1, floori(strength / impact_threshold))
	hits_left = maxi(0, hits_left - damage)
	queue_redraw()
	if hits_left == 0:
		destroy()
	else:
		material_hit.emit(material_id)


func damage_ratio() -> float:
	return 1.0 - float(hits_left) / float(_max_hit_points)


func _on_destroyed() -> void:
	destroyed.emit()


func _draw() -> void:
	BlockVisual.paint(self, size, material_id, damage_ratio())
