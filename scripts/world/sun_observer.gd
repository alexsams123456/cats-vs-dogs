class_name SunObserver
extends Node
## Наблюдает за раундом: меняет только взгляд и выражение декоративного солнца.

const SURPRISE_DURATION := 0.85
const DELIGHT_DURATION := 1.35
const EVENT_ATTENTION_DURATION := 0.45

var _cats: Array[CatProjectile] = []
var _loaded_cat: CatProjectile
var _active_cat: CatProjectile
var _reaction_left: float = 0.0
var _reaction_priority: int = 0
var _attention_left: float = 0.0
var _event_focus := Vector2.ZERO
var _last_mood: StringName = &"happy"
var _round_finished: bool = false

@onready var _round: GameRound = get_parent() as GameRound
@onready var _actors: Node2D = _round.get_node("Actors") as Node2D
@onready var _slingshot: Slingshot = _round.get_node("Slingshot") as Slingshot
@onready var _ambient: AmbientLife = _round.get_node("Backdrop/AmbientLife") as AmbientLife
@onready var _sun: SunFace = _ambient.sun_face


func _ready() -> void:
	_sun.reset()
	_actors.child_entered_tree.connect(_observe_actor)
	_actors.child_exiting_tree.connect(_forget_actor)
	for actor: Node in _actors.get_children():
		_observe_actor(actor)
	_slingshot.launched.connect(_on_launched)
	_slingshot.tension_started.connect(_on_tension_started)
	_round.round_completed.connect(_on_round_completed)
	_focus_on(_slingshot.global_position)


func _process(delta: float) -> void:
	if _round_finished:
		return
	_reaction_left = maxf(0.0, _reaction_left - delta)
	_attention_left = maxf(0.0, _attention_left - delta)
	if _round.state == GameRound.RoundState.READY:
		var loaded := _slingshot.loaded_projectile
		if is_instance_valid(loaded) and loaded != _loaded_cat:
			_loaded_cat = loaded
			_active_cat = null
			_reset_expression()
		_set_mood(&"focused" if _slingshot.is_dragging else &"happy")
		if is_instance_valid(loaded):
			_focus_on(loaded.global_position)
	elif _round.state == GameRound.RoundState.FLYING:
		_set_mood(&"focused")
		if _attention_left > 0.0:
			_focus_on(_event_focus)
		else:
			_follow_flight()


func _observe_actor(actor: Node) -> void:
	if actor is CatProjectile:
		_cats.append(actor)
		actor.ability_used.connect(_on_ability_used.bind(actor))
		actor.ability_availability_changed.connect(_on_cat_contact.bind(actor))
	elif actor is DogTarget:
		actor.defeated.connect(_on_dog_defeated.bind(actor))
	elif actor is WoodenBlock:
		actor.destroyed.connect(_on_structure_destroyed.bind(actor))
		actor.material_hit.connect(_on_material_hit.bind(actor))


func _forget_actor(actor: Node) -> void:
	if actor is CatProjectile:
		_cats.erase(actor)


func _on_tension_started() -> void:
	if not _round_finished:
		_set_mood(&"focused")


func _on_launched(cat: CatProjectile) -> void:
	if _round_finished:
		return
	_active_cat = cat
	_set_mood(&"focused")
	_focus_on(cat.global_position)


func _follow_flight() -> void:
	var airborne_center := Vector2.ZERO
	var airborne_count := 0
	var moving_cat: CatProjectile
	var greatest_speed := 0.0
	for cat: CatProjectile in _cats:
		if not is_instance_valid(cat) or cat.is_queued_for_deletion() or not cat.was_launched:
			continue
		if not cat.has_contacted():
			airborne_center += cat.global_position
			airborne_count += 1
		var speed := cat.linear_velocity.length_squared()
		if speed > greatest_speed:
			greatest_speed = speed
			moving_cat = cat
	if airborne_count > 0:
		# После разделения взгляд следует середине веера оставшихся котят.
		_focus_on(airborne_center / float(airborne_count))
	elif is_instance_valid(moving_cat):
		_focus_on(moving_cat.global_position)
	elif is_instance_valid(_active_cat) and not _active_cat.is_queued_for_deletion():
		_focus_on(_active_cat.global_position)


func _on_ability_used(cat: CatProjectile) -> void:
	_react_at(&"surprised", SURPRISE_DURATION, 1, cat.global_position)


func _on_cat_contact(cat: CatProjectile) -> void:
	if cat.has_contacted():
		_react_at(&"surprised", SURPRISE_DURATION, 1, cat.global_position)


func _on_structure_destroyed(block: WoodenBlock) -> void:
	_react_at(&"surprised", SURPRISE_DURATION, 1, block.global_position)


func _on_material_hit(_material_id: StringName, block: WoodenBlock) -> void:
	_react_at(&"surprised", SURPRISE_DURATION, 1, block.global_position)


func _on_dog_defeated(dog: DogTarget) -> void:
	_react_at(&"delighted", DELIGHT_DURATION, 2, dog.global_position)


func _react_at(emotion: StringName, duration: float, priority: int, world_position: Vector2) -> void:
	if _round_finished or _round.state != GameRound.RoundState.FLYING:
		return
	# Падающая башня не перезапускает удивление каждым обломком и не перебивает радость.
	if _reaction_left > 0.0 and priority <= _reaction_priority:
		return
	_reaction_left = duration
	_reaction_priority = priority
	_attention_left = EVENT_ATTENTION_DURATION
	_event_focus = world_position
	_focus_on(world_position)
	_sun.react(emotion, duration)


func _on_round_completed(won: bool, _shots_used: int, _stars: int) -> void:
	_round_finished = true
	_reset_expression()
	_set_mood(&"delighted" if won else &"sad")


func _reset_expression() -> void:
	_reaction_left = 0.0
	_reaction_priority = 0
	_attention_left = 0.0
	_sun.reset()
	_last_mood = &"happy"


func _set_mood(mood: StringName) -> void:
	if mood == _last_mood:
		return
	_last_mood = mood
	_sun.set_mood(mood)


func _focus_on(world_position: Vector2) -> void:
	_sun.focus_on(_ambient.to_local(world_position))
