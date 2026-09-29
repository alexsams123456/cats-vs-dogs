class_name BlockMaterialDefinition
extends Resource
## Shared physical properties and original procedural colors for building parts.

@export var id: StringName = &"wood"
@export var display_name: String = "Дерево"
@export var mass: float = 1.4
@export var impact_threshold: float = 345.0
@export_range(1, 10) var hit_points: int = 1
@export_range(0.0, 1.0) var friction: float = 0.9
@export var base_color: Color = Color("c78a50")
@export var edge_color: Color = Color("785035")
@export var detail_color: Color = Color("a46c41")
@export var highlight_color: Color = Color("edb678")
