class_name ImpactFeedback
extends Node
## Собирает принятые сильные удары раунда; в одном кадре выбирает самый сильный.

signal impact_presented(point: Vector2, intensity: float, material_id: StringName)

@export var minimum_strength: float = 450.0
@export var full_strength: float = 1600.0
@export var impact_interval: float = 0.09
@export var max_bursts: int = 6
var reduced_particles: bool = false

var _cooldown_left: float = 0.0
var _pending: Dictionary = {}

@onready var _round: GameRound = get_parent() as GameRound
@onready var _actors: Node2D = _round.get_node("Actors") as Node2D


func _ready() -> void:
	_actors.child_entered_tree.connect(_observe_actor)
	for actor in _actors.get_children():
		_observe_actor(actor)


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func _observe_actor(actor: Node) -> void:
	if actor is DestructibleBody:
		actor.impact_received.connect(_on_impact_received.bind(weakref(actor)))


func _on_impact_received(strength: float, reference: WeakRef) -> void:
	if strength < minimum_strength or not can_process() or _round.state != GameRound.RoundState.FLYING or _cooldown_left > 0.0:
		return
	var body := reference.get_ref() as DestructibleBody
	if body == null or strength <= float(_pending.get("strength", 0.0)):
		return
	var material_threshold := body.impact_threshold * (1.0 if body is HangingWeight else 1.35)
	if strength < material_threshold:
		return
	if _pending.is_empty():
		_present_pending.call_deferred()
	var material_id: StringName = &"wood"
	if body is WoodenBlock:
		material_id = body.material_id
	elif body is HangingWeight:
		material_id = &"metal"
	elif body is DogTarget:
		material_id = &"fur"
	var direction := body.impact_motion.velocity_before_step(Vector2.ZERO).normalized()
	_pending = {"strength": strength, "point": body.global_position, "material": material_id, "direction": direction}


func _present_pending() -> void:
	var hit := _pending
	_pending = {}
	if hit.is_empty() or not can_process() or is_queued_for_deletion() or _round.is_queued_for_deletion():
		return
	_cooldown_left = impact_interval
	var intensity := clampf((float(hit.strength) - minimum_strength) / maxf(1.0, full_strength - minimum_strength), 0.0, 1.0)
	if get_child_count() < max_bursts:
		var burst := ImpactBurst.new()
		burst.intensity = intensity
		burst.fragment_count = 4 if reduced_particles else 12
		burst.material_id = hit.material
		burst.direction = hit.direction
		add_child(burst)
		burst.global_position = hit.point
	_round.camera.punch(intensity, hit.direction)
	impact_presented.emit(hit.point, intensity, hit.material)
