class_name DogHouseDefinition
extends Resource
## Форма конуры не зависит от материала её стен.

@export var id: StringName = &"classic"
@export var display_name: String = "Классическая"
@export_multiline var description: String = "Конура с двускатной крышей и обычной прочностью."
@export var size: Vector2 = Vector2(140, 124)
@export var dog_offset: Vector2 = Vector2(0, 37)
@export_range(0, 10) var extra_hit_points: int = 1
@export_range(0.1, 10.0) var mass_multiplier: float = 2.0
