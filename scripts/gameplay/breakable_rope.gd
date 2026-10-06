class_name BreakableRope
extends Area2D
## Верёвка пропускает кота, но разрывается от быстрого тела или взрыва.

signal broken

@export var impact_threshold: float = 180.0

var is_broken: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var moving_body := body as RigidBody2D
	if moving_body == null or moving_body.freeze:
		return
	if body is CatProjectile and not body.was_launched:
		return
	receive_hit(moving_body.linear_velocity.length())


func receive_hit(strength: float) -> void:
	if is_broken or not can_process() or strength < impact_threshold:
		return
	is_broken = true
	set_deferred("monitoring", false)
	broken.emit()
