class_name GameRound
extends Node2D
## Owns one level attempt; actors report outcomes through signals.

signal restart_requested
signal menu_requested
signal next_requested
signal round_completed(won: bool, shots_used: int, stars: int)

enum RoundState { READY, FLYING, WON, LOST }

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const BLOCK_SCENE := preload("res://scenes/actors/wooden_block.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")
const WEIGHT_SCENE := preload("res://scenes/actors/hanging_weight.tscn")
const MUSIC_SCENE := preload("res://scenes/audio/background_music.tscn")
const AimGestureVisual := preload("res://scripts/visuals/aim_gesture.gd")
const MIN_FLIGHT_TIME := 1.2
const SETTLE_TIME := 0.8
const MAX_FLIGHT_TIME := 10.0
const WORLD_BOUNDS := Rect2(-400, -1000, 2200, 2100)

@export var level: LevelDefinition
@export var cat_definition: CharacterDefinition = CharacterCatalog.CATS[0]
@export var dog_definition: CharacterDefinition = CharacterCatalog.DOGS[0]

var state: RoundState = RoundState.READY
var shots_left: int = 0
var dogs_left: int = 0
var editor_preview: bool = false
var campaign_mode: bool = false
var has_next_level: bool = false
var background_music: BackgroundMusic
var _flight_time: float = 0.0
var _still_time: float = 0.0
var _active_cat: CatProjectile
var _tutorial_ability_used: bool = false
var _tutorial_shelter_opened: bool = false
var _aim_gesture: AimGestureVisual

@onready var actors: Node2D = $Actors
@onready var slingshot: Slingshot = $Slingshot
@onready var hud: GameHUD = $HUD
@onready var cat_queue: CatQueue = $CatQueue
@onready var camera: GameCamera = $Camera2D


func _ready() -> void:
	if level == null or not level.is_valid():
		push_error("Invalid level resource: check shots and matching block arrays.")
		return
	# App передаёт общий поток; самостоятельный запуск сцены тоже имеет музыку.
	if not is_instance_valid(background_music):
		background_music = MUSIC_SCENE.instantiate() as BackgroundMusic
		add_child(background_music)
	shots_left = level.shots
	dogs_left = level.dog_positions.size()
	$Backdrop.set_biome(StringName(level.biome))
	hud.restart_requested.connect(restart)
	hud.pause_requested.connect(toggle_pause)
	hud.menu_requested.connect(return_to_menu)
	hud.next_requested.connect(_request_next)
	hud.ability_requested.connect(use_ability)
	hud.camera_reset_requested.connect(camera.reset_view)
	hud.set_editor_preview(editor_preview)
	hud.set_campaign(campaign_mode, has_next_level, level.par_shots)
	hud.set_result_cast(level.cat_sequence if not level.cat_sequence.is_empty() else PackedStringArray([String(cat_definition.id)]))
	slingshot.launched.connect(_on_launched)
	camera.aim_cancel_requested.connect(slingshot.cancel_drag)
	for index in level.block_positions.size():
		var block := BLOCK_SCENE.instantiate() as WoodenBlock
		block.position = level.block_positions[index]
		block.size = level.block_sizes[index]
		block.material_id = level.block_material_at(index)
		actors.add_child(block)
	for point in level.weight_positions:
		var weight := WEIGHT_SCENE.instantiate() as HangingWeight
		weight.position = point
		actors.add_child(weight)
	for index in level.dog_positions.size():
		var house: DogHouse
		var house_material := level.dog_house_material_at(index)
		if house_material != &"":
			house = HOUSE_SCENE.instantiate() as DogHouse
			house.material_id = house_material
			house.house_type = level.dog_house_type_at(index)
			house.position = level.dog_positions[index] - house.dog_offset()
			house.destroyed.connect(_on_shelter_destroyed)
			actors.add_child(house)
		var dog := DOG_SCENE.instantiate() as DogTarget
		dog.definition = dog_definition if level.dog_kinds.is_empty() else CharacterCatalog.find_dog(StringName(level.dog_kinds[index]))
		dog.position = level.dog_positions[index]
		dog.defeated.connect(_on_dog_defeated)
		actors.add_child(dog)
		if house != null:
			dog.enter_shelter(house)
	_load_cat()
	if campaign_mode and not editor_preview and level.tutorial == &"aim":
		_aim_gesture = AimGestureVisual.new()
		_aim_gesture.name = "AimGesture"
		slingshot.add_child(_aim_gesture)
	_update_hud()


func _physics_process(delta: float) -> void:
	_refresh_tutorial()
	if state != RoundState.FLYING:
		return
	_flight_time += delta
	var still := true
	for actor in actors.get_children():
		if not actor is RigidBody2D or actor.is_queued_for_deletion():
			continue
		var actor_position: Vector2 = actor.position
		if actor is DogTarget and actor.is_sheltered():
			actor_position = actor.shelter.transform * actor.shelter.dog_offset()
		if not WORLD_BOUNDS.has_point(actor_position):
			if actor is DogTarget:
				actor.destroy()
			elif actor is DestructibleBody:
				actor.destroy()
			else:
				if actor == _active_cat:
					hud.set_ability_state(GameHUD.AbilityState.USED if _active_cat.ability_spent else GameHUD.AbilityState.WAITING)
					_active_cat = null
				actor.queue_free()
			continue
		if not actor.sleeping and (actor.linear_velocity.length() > 22.0 or absf(actor.angular_velocity) > 0.4):
			still = false
		if actor is DogTarget and actor.frost_time_left > 0.0 and not actor.is_destroyed:
			# A suspended target can still fall after thawing and change the outcome.
			still = false
	_still_time = _still_time + delta if still else 0.0
	# The timer may prepare another cat, but cannot decide the final result
	# while bodies are still moving or a frozen target can fall after thawing.
	var can_advance := shots_left > 0 and _flight_time >= MAX_FLIGHT_TIME
	if _flight_time >= MIN_FLIGHT_TIME and (_still_time >= SETTLE_TIME or can_advance):
		# Give deferred destruction signals this frame time to update the target count.
		_finish_shot.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		if state == RoundState.READY or state == RoundState.FLYING:
			set_paused(true)


func _load_cat() -> void:
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.definition = _cat_at(level.shots - shots_left)
	cat.ability_used.connect(_on_ability_used)
	cat.ability_availability_changed.connect(_refresh_ability)
	actors.add_child(cat)
	slingshot.load_projectile(cat)
	slingshot.set_enabled(true)
	state = RoundState.READY
	hud.set_loadout(cat.definition, dog_definition, not level.dog_kinds.is_empty())
	_update_queue()


func _cat_at(index: int) -> CharacterDefinition:
	return cat_definition if level.cat_sequence.is_empty() else CharacterCatalog.find_cat(StringName(level.cat_sequence[index]))


func _update_queue() -> void:
	var names := PackedStringArray()
	var reserves: Array[CharacterDefinition] = []
	var next_index := level.shots - shots_left
	for index in range(level.shots - shots_left, level.shots):
		var definition := _cat_at(index)
		names.append(definition.display_name)
		if state == RoundState.FLYING or index > next_index:
			reserves.append(definition)
	hud.set_queue(names, state == RoundState.FLYING)
	cat_queue.set_cats(reserves)


func _on_launched(projectile: CatProjectile) -> void:
	_active_cat = projectile
	shots_left -= 1
	state = RoundState.FLYING
	_flight_time = 0.0
	_still_time = 0.0
	_update_queue()
	_update_hud()


func _on_dog_defeated() -> void:
	if state == RoundState.WON or state == RoundState.LOST:
		return
	dogs_left = maxi(0, dogs_left - 1)
	_update_hud()
	if dogs_left == 0:
		_complete_round(true)


func _finish_shot() -> void:
	if state != RoundState.FLYING:
		return
	if dogs_left == 0:
		return
	# A bounded turn also prevents old cats from accumulating on slower phones.
	for actor in actors.get_children():
		if actor is CatProjectile:
			actor.queue_free()
	if shots_left > 0:
		_load_cat()
		_update_hud()
	else:
		_complete_round(false)


func _complete_round(won: bool) -> void:
	state = RoundState.WON if won else RoundState.LOST
	camera.cancel_gesture()
	slingshot.set_enabled(false)
	_update_hud()
	var shots_used := level.shots - shots_left
	var stars := level.stars_for_shots(shots_used) if won else 0
	hud.show_result(won, shots_used, stars)
	round_completed.emit(won, shots_used, stars)


func _update_hud() -> void:
	var shown_title := level.title if editor_preview else tr(level.title)
	hud.update_status(shown_title, shots_left, dogs_left, state == RoundState.FLYING)
	_refresh_ability()
	_refresh_tutorial()


func _refresh_ability() -> void:
	if state != RoundState.FLYING or not is_instance_valid(_active_cat):
		return
	if _active_cat.definition.ability_action.is_empty():
		hud.set_ability_state(GameHUD.AbilityState.AUTOMATIC)
	elif _active_cat.ability_spent:
		hud.set_ability_state(GameHUD.AbilityState.USED)
	elif _active_cat.can_activate_ability():
		hud.set_ability_state(GameHUD.AbilityState.READY)
	elif _active_cat.has_contacted():
		hud.set_ability_state(GameHUD.AbilityState.CONTACTED)
	else:
		hud.set_ability_state(GameHUD.AbilityState.WAITING)


func use_ability() -> void:
	if state != RoundState.FLYING or get_tree().paused:
		return
	if is_instance_valid(_active_cat):
		_active_cat.activate_ability()


func _on_ability_used() -> void:
	_tutorial_ability_used = true
	_refresh_ability()
	_refresh_tutorial()


func _on_shelter_destroyed() -> void:
	_tutorial_shelter_opened = true
	_refresh_tutorial()


func _refresh_tutorial() -> void:
	if is_instance_valid(_aim_gesture):
		_aim_gesture.set_enabled(state == RoundState.READY and shots_left == level.shots)
	if level == null or state == RoundState.WON or state == RoundState.LOST:
		return
	var message := ""
	match level.tutorial:
		&"aim":
			if shots_left < level.shots:
				message = "Выстрел получился! Чем сильнее натяжение, тем дальше полёт."
			elif slingshot.is_dragging:
				message = "Шаг 2/2. Потяни назад, наведи точки на собаку и отпусти."
			else:
				message = "Шаг 1/2. Возьми кошку у рогатки мышью или пальцем."
		&"ability":
			if _tutorial_ability_used:
				message = "Приём сработал! У каждого кота своя способность."
			elif state == RoundState.FLYING and is_instance_valid(_active_cat) and _active_cat.can_activate_ability():
				message = "Шаг 2/2. Нажми кнопку способности или E в полёте, до удара."
			elif state == RoundState.FLYING:
				message = "Приём доступен до удара. Попробуй со следующим котом."
			else:
				message = "Шаг 1/2. Запусти кота в сторону собаки."
		&"shelter":
			message = "Шаг 2/2. Укрытие открыто! Теперь попади в собаку." if _tutorial_shelter_opened else "Шаг 1/2. Разрушь будку: пока она цела, собака защищена."
	hud.set_tutorial_hint(message)


func _request_next() -> void:
	if campaign_mode and has_next_level and state == RoundState.WON:
		get_tree().paused = false
		next_requested.emit()


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func set_paused(value: bool) -> void:
	if state == RoundState.WON or state == RoundState.LOST:
		return
	if value:
		camera.cancel_gesture()
	get_tree().paused = value
	hud.show_pause(value)


func restart() -> void:
	get_tree().paused = false
	if restart_requested.get_connections().is_empty():
		get_tree().reload_current_scene()
	else:
		restart_requested.emit()


func return_to_menu() -> void:
	camera.cancel_gesture()
	get_tree().paused = false
	menu_requested.emit()
