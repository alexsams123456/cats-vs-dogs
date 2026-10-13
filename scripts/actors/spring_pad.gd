class_name SpringPad
extends StaticBody2D
## Неподвижная пружина: один подброс тела за попытку исключает вечный цикл.

signal activated(body: RigidBody2D)

@export_range(200.0, 1000.0, 20.0) var launch_speed: float = 640.0
@export var minimum_fall_speed: float = 35.0

var _launched: Dictionary = {}
var _animation_left: float = 0.0

@onready var trigger: Area2D = $Trigger


func _physics_process(delta: float) -> void:
	if _animation_left > 0.0:
		_animation_left = maxf(0.0, _animation_left - delta)
		queue_redraw()
	for candidate: Node2D in trigger.get_overlapping_bodies():
		var body := candidate as RigidBody2D
		if body == null or body.freeze or _launched.has(body.get_instance_id()):
			continue
		if not (body is CatProjectile or body is WoodenBlock or body is HangingWeight):
			continue
		if body is DestructibleBody and body.is_destroyed:
			continue
		if body.global_position.y >= global_position.y - 18.0 or body.linear_velocity.y < minimum_fall_speed:
			continue
		var speed := launch_speed
		if body is CatProjectile:
			if not body.was_launched:
				continue
			speed *= body.flight_speed_scale
		_launched[body.get_instance_id()] = true
		body.sleeping = false
		body.linear_velocity = Vector2(body.linear_velocity.x, -speed)
		body.impact_motion.seed(body.linear_velocity, body.angular_velocity)
		_animation_left = 0.24
		queue_redraw()
		activated.emit(body)


func _draw() -> void:
	SpringPadVisual.paint(self, sin(_animation_left / 0.24 * PI))
