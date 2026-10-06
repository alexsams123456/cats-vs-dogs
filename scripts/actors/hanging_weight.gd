class_name HangingWeight
extends DestructibleBody
## Тяжёлый груз сохраняется после падения и участвует в завершении броска.

signal released
signal material_hit(material_id: StringName)

@export var weight_mass: float = 12.0

var suspended: bool = true

@onready var rope: BreakableRope = $Rope


func _ready() -> void:
	mass = weight_mass
	rope.broken.connect(_on_rope_broken)


func _on_rope_broken() -> void:
	if not suspended:
		return
	suspended = false
	_drop.call_deferred()


func _drop() -> void:
	if is_destroyed:
		return
	freeze = false
	sleeping = false
	# Прежние импульсы по неподвижному грузу не накапливаются до разрыва.
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	impact_motion.seed(Vector2.ZERO, 0.0)
	queue_redraw()
	released.emit()


func receive_hit(strength: float) -> void:
	if is_destroyed:
		return
	if suspended:
		rope.receive_hit(strength)
	elif _can_receive_hit(strength):
		_hit_cooldown_left = hit_cooldown_seconds
		impact_received.emit(strength)
		material_hit.emit(&"metal")


func _draw() -> void:
	HangingWeightVisual.paint(self, suspended)
