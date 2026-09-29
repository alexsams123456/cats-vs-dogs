class_name DestructibleBody
extends RigidBody2D
## Shared impact handling; sustained structural loads are not new collisions.

@export var impact_threshold: float = 260.0
@export var spawn_grace_seconds: float = 0.75
@export var hit_cooldown_seconds: float = 0.25

var is_destroyed: bool = false
var _age: float = 0.0
var _hit_cooldown_left: float = 0.0
var _contact_impulses: Dictionary = {}
var impact_motion := preload("res://scripts/actors/impact_motion.gd").new()


func _physics_process(delta: float) -> void:
	# Sleeping bodies may skip integration; grace still ends while they rest.
	_age += delta
	_hit_cooldown_left = maxf(0.0, _hit_cooldown_left - delta)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	impact_motion.capture(state)
	if is_destroyed:
		return
	var contacts: Dictionary = {}
	for contact_index in state.get_contact_count():
		var collider := state.get_contact_collider_object(contact_index)
		var collider_id: int = state.get_contact_collider_id(contact_index)
		if not contacts.has(collider_id):
			contacts[collider_id] = {"collider": collider, "impulse": 0.0, "speed": 0.0, "incoming_speed": 0.0, "motion": 0.0}
		var contact: Dictionary = contacts[collider_id]
		var incoming_velocity := state.get_contact_local_velocity_at_position(contact_index) - state.get_contact_collider_velocity_at_position(contact_index)
		contact.incoming_speed = maxf(contact.incoming_speed, incoming_velocity.length())
		# Stored contact velocities can include the solver's temporary compression
		# of a light support. Read the resolved body velocities at each contact point.
		var local_offset := state.get_contact_local_position(contact_index) - state.transform.origin
		var collider_velocity := state.get_contact_collider_velocity_at_position(contact_index)
		var previous_collider_velocity := collider_velocity
		if collider is RigidBody2D:
			var collider_state := PhysicsServer2D.body_get_direct_state(collider.get_rid())
			if collider_state != null:
				var collider_offset := state.get_contact_collider_position(contact_index) - collider_state.transform.origin
				collider_velocity = collider_state.get_velocity_at_local_position(collider_offset)
				previous_collider_velocity = collider_velocity
				if collider.freeze:
					previous_collider_velocity = Vector2.ZERO
				elif collider is DestructibleBody or collider is CatProjectile:
					previous_collider_velocity = collider.impact_motion.velocity_before_step(collider_offset)
		var relative_velocity := state.get_velocity_at_local_position(local_offset) - collider_velocity
		var previous_velocity: Vector2 = impact_motion.velocity_before_step(local_offset) - previous_collider_velocity
		# Sum all contact points: the solver may redistribute a resting load between them.
		contact.impulse += state.get_contact_impulse(contact_index).length()
		contact.speed = maxf(contact.speed, relative_velocity.length())
		contact.motion = maxf(contact.motion, previous_velocity.length())
	var previous_impulses := _contact_impulses
	_contact_impulses = {}
	for collider_id: int in contacts:
		_contact_impulses[collider_id] = contacts[collider_id].impulse
	# Track the load during grace too, before damage becomes possible.
	if _age < spawn_grace_seconds:
		return
	for collider_id: int in contacts:
		var contact: Dictionary = contacts[collider_id]
		if _ignore_contact(contact.collider):
			continue
		# Pressure can briefly separate and rejoin a resting contact. It is an
		# impact only when either body actually moved before or after this step.
		if maxf(contact.motion, contact.speed) < 35.0:
			continue
		# Only the new impulse counts; the constant weight of upper floors does not.
		# A new collision still registers when the solver has already stopped both bodies.
		var impulse_gain := maxf(0.0, contact.impulse - float(previous_impulses.get(collider_id, 0.0)))
		var impact_speed := maxf(contact.speed, impulse_gain / mass)
		# A fresh collision needs its incoming speed: a light cat can be stopped
		# by a heavy shelter without giving that shelter a large final velocity.
		if not previous_impulses.has(collider_id):
			impact_speed = maxf(impact_speed, contact.incoming_speed)
		# A frozen target cannot run its own contact integration.
		var frozen_dog := contact.collider as DogTarget
		if frozen_dog != null and frozen_dog.frost_time_left > 0.0:
			frozen_dog.receive_hit(impact_speed)
		if impact_speed >= impact_threshold:
			receive_hit(impact_speed)
			return


func receive_hit(strength: float) -> void:
	if not _can_receive_hit(strength):
		return
	_hit_cooldown_left = hit_cooldown_seconds
	destroy()


func _can_receive_hit(strength: float) -> bool:
	return not is_destroyed and _hit_cooldown_left <= 0.0 and strength >= impact_threshold


func _ignore_contact(_collider: Object) -> bool:
	return false


func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	# Contact callbacks cannot safely remove collision objects immediately.
	_finish_destroy.call_deferred()


func _finish_destroy() -> void:
	freeze = true
	collision_layer = 0
	collision_mask = 0
	_on_destroyed()
	queue_free()


func _on_destroyed() -> void:
	pass
