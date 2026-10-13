class_name CharacterDefinition
extends Resource
## Shared identity for roster cards, portraits and actor behavior.

@export var id: StringName
@export_enum("cat", "dog") var species: String = "cat"
@export var display_name: String
@export var tagline: String
@export_multiline var description: String
@export var ability_hint: String
@export var ability_action: String
@export var fur_color: Color = Color("ed9551")
@export var accent_color: Color = Color("387c73")
## Множители общих параметров DogTarget; нулевая скорость отключает патруль.
@export_range(0.0, 2.0) var patrol_speed_scale: float = 0.0
@export_range(0.0, 2.0) var patrol_distance_scale: float = 1.0
## Нулевая длительность ходьбы означает непрерывный патруль.
@export_range(0.0, 5.0) var patrol_walk_seconds: float = 0.0
@export_range(0.0, 5.0) var patrol_rest_seconds: float = 0.0
