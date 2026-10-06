extends SceneTree
## Звук следует принятым игровым событиям, переживает тело и ограничен по голосам.

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const BLOCK_SCENE := preload("res://scenes/actors/wooden_block.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus_index := AudioServer.get_bus_index(&"SFX")
	AudioServer.set_bus_mute(bus_index, false)
	for sound: AudioStreamWAV in [WorldAudio.TENSION, WorldAudio.RELEASE, WorldAudio.FLIGHT,
			WorldAudio.WOOD, WorldAudio.GLASS, WorldAudio.STONE, WorldAudio.METAL, WorldAudio.VICTORY, WorldAudio.IMPACT]:
		_check(sound.get_length() >= 0.1 and sound.get_length() <= 1.3, "Every effect has a short bounded duration")
		_check(not sound.data.is_empty() and sound.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Effects contain samples and never loop")
	await _test_sling()
	await _test_materials()
	await _test_resting_contacts()
	await _test_limits_pause_and_cleanup(bus_index)
	await create_timer(0.3).timeout
	print("World audio checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_sling() -> void:
	var world := _make_world()
	var sling := Slingshot.new()
	sling.position = Vector2(250, 300)
	world.add_child(sling)
	var cat := _make_cat(world)
	sling.load_projectile(cat)
	# Покрывает подключение к рогатке, созданной раньше аудиокомпонента.
	var audio := WorldAudio.new()
	world.add_child(audio)
	var events: Array[StringName] = []
	audio.effect_played.connect(func(effect_id: StringName) -> void: events.append(effect_id))
	await process_frame
	await create_timer(0.05).timeout
	_mouse_button(sling, true, Vector2(250, 300))
	_mouse_motion(sling, Vector2(254, 300))
	_mouse_button(sling, false, Vector2(254, 300))
	_check(events.is_empty() and not cat.was_launched, "A click with tiny pull neither sounds nor spends a shot")
	_mouse_button(sling, true, Vector2(250, 300))
	_mouse_motion(sling, Vector2(185, 325))
	_check(events == [&"tension"], "Mouse pull starts exactly one short tension sound")
	await create_timer(0.3).timeout
	for index in 30:
		_mouse_motion(sling, Vector2(180 - index, 330))
	_check(events == [&"tension"] and _active_voices(audio) == 0, "Holding and moving the pull never restart or loop tension")
	_mouse_button(sling, false, Vector2(170, 330))
	_check(events == [&"tension", &"release", &"flight"] and cat.was_launched, "Valid release triggers snap and one short flight sound")
	cat.queue_free()
	await create_timer(0.4).timeout
	cat = _make_cat(world)
	sling.load_projectile(cat)
	_touch(sling, true, Vector2(250, 300))
	_touch_drag(sling, Vector2(180, 325))
	_touch(sling, false, Vector2(180, 325), true)
	_check(events.count(&"tension") == 2 and events.count(&"release") == 1 and not cat.was_launched, "Canceled touch sounds the pull but does not launch")
	await create_timer(0.25).timeout
	_touch(sling, true, Vector2(250, 300))
	_touch_drag(sling, Vector2(180, 325))
	_touch(sling, false, Vector2(180, 325))
	_check(events.count(&"tension") == 3 and events.count(&"release") == 2 and events.count(&"flight") == 2, "A fresh touch gesture gets one sound per stage")
	world.queue_free()
	await process_frame


func _test_materials() -> void:
	var world := _make_world()
	var audio := WorldAudio.new()
	world.add_child(audio)
	var events: Array[StringName] = []
	audio.effect_played.connect(func(effect_id: StringName) -> void: events.append(effect_id))
	var metal := _make_block(world, &"metal")
	await process_frame
	metal.receive_hit(metal.impact_threshold - 1.0)
	_check(events.is_empty(), "Weak contact stays silent")
	metal.receive_hit(metal.impact_threshold)
	for index in 40:
		metal.receive_hit(metal.impact_threshold)
	_check(events == [&"metal"] and metal.hits_left == 2, "One accepted nonfatal material hit sounds once; cooldown rejects repeated contacts")
	await create_timer(0.28).timeout
	var body_ref: WeakRef = weakref(metal)
	metal.receive_hit(10000.0)
	await create_timer(0.04).timeout
	_check(body_ref.get_ref() == null and events.count(&"metal") == 2, "Destruction emits one sound and removes the physical body")
	_check(_active_voices(audio) > 0, "Material sound continues after its body is freed")
	await create_timer(0.7).timeout
	for material_id in BlockMaterials.IDS:
		var block := _make_block(world, material_id)
		await process_frame
		block.destroy()
		await create_timer(0.03).timeout
		_check(events.back() == material_id, "Newly added block selects its material sound: " + material_id)
		await create_timer(0.7).timeout
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.material_id = &"glass"
	house.freeze = true
	world.add_child(house)
	await process_frame
	house.receive_hit(10000.0)
	await create_timer(0.03).timeout
	_check(events.back() == &"glass", "House uses the same material effects as blocks")
	var unrelated := _make_world()
	var outsider := _make_block(unrelated, &"wood")
	await process_frame
	var previous_count := audio.play_count
	outsider.destroy()
	await create_timer(0.03).timeout
	_check(audio.play_count == previous_count, "A round cannot hear material events from another scene")
	unrelated.queue_free()
	world.queue_free()
	await process_frame


func _test_resting_contacts() -> void:
	var world := _make_world()
	var audio := WorldAudio.new()
	world.add_child(audio)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(500, 280)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 20)
	collision.shape = shape
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var block := _make_block(world, &"metal")
	block.position = Vector2(500, 200)
	block.freeze = false
	await create_timer(1.1).timeout
	_check(is_instance_valid(block) and audio.play_count == 0, "Spawn settling and resting ground contacts produce no audio spam")
	world.queue_free()
	await process_frame


func _test_limits_pause_and_cleanup(bus_index: int) -> void:
	var world := _make_world()
	var audio := WorldAudio.new()
	world.add_child(audio)
	var blocks: Array[WoodenBlock] = []
	for index in 200:
		blocks.append(_make_block(world, BlockMaterials.IDS[index % BlockMaterials.IDS.size()]))
	var sling := Slingshot.new()
	world.add_child(sling)
	await process_frame
	for block in blocks:
		block.destroy()
	await create_timer(0.025).timeout
	_check(audio.play_count == 4, "A simultaneous avalanche merges rapid events for each material")
	sling.launched.emit(null)
	_check(_active_voices(audio) == WorldAudio.MAX_VOICES, "Four materials and a launch fill exactly six physical voices")
	for index in 30:
		sling.launched.emit(null)
	_check(audio.play_count == 6 and _active_voices(audio) == WorldAudio.MAX_VOICES, "Excess requests cannot allocate extra players or overlap a voice")
	audio.play_victory()
	audio.play_victory()
	_check(audio.play_count == 7 and _active_voices(audio) == WorldAudio.MAX_VOICES, "Victory takes a voice during an avalanche and cannot replay")
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		_check(player != null and player.bus == &"SFX" and player.max_polyphony == 1, "Every physical voice follows the shared sound bus")
	paused = true
	await create_timer(0.08, true).timeout
	var count_before := audio.play_count
	sling.launched.emit(null)
	var all_paused := true
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		if player.playing:
			all_paused = all_paused and player.stream_paused
	_check(all_paused and audio.play_count == count_before, "Pause freezes active effects and rejects new sounds")
	paused = false
	await create_timer(0.03).timeout
	var any_resumed := false
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		any_resumed = any_resumed or (player.playing and not player.stream_paused)
	_check(any_resumed, "Effects resume with the round")
	AudioServer.set_bus_mute(bus_index, true)
	sling.launched.emit(null)
	_check(audio.play_count == count_before, "Muted SFX prevents all new physical sounds")
	AudioServer.set_bus_mute(bus_index, false)
	# Аудиопоток очищает playing после последнего сэмпла отдельным циклом микшера.
	# Ждём реального освобождения с пределом, а не точной границы длительности WAV.
	await _wait_for_idle_voices(audio, 2.0)
	_check(_active_voices(audio) == 0 and audio.get_child_count() == WorldAudio.MAX_VOICES, "Finished one-shot effects release bounded pool capacity")
	_check(audio.play_count == count_before, "Waiting for audio tails cannot create new effects")
	sling.launched.emit(null)
	_check(audio.play_count == count_before + 2, "Unmuting allows later launches to use the pool again")
	var audio_ref: WeakRef = weakref(audio)
	var player_ref: WeakRef = weakref(audio.get_child(0))
	world.queue_free()
	await create_timer(0.05).timeout
	_check(audio_ref.get_ref() == null and player_ref.get_ref() == null, "Leaving the round frees the component and every active voice")


func _make_world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	return world


func _make_cat(world: Node2D) -> CatProjectile:
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.freeze = true
	cat.gravity_scale = 0.0
	cat.collision_layer = 0
	cat.collision_mask = 0
	world.add_child(cat)
	return cat


func _make_block(world: Node2D, material_id: StringName) -> WoodenBlock:
	var block := BLOCK_SCENE.instantiate() as WoodenBlock
	block.material_id = material_id
	block.freeze = true
	world.add_child(block)
	return block


func _active_voices(audio: WorldAudio) -> int:
	var active := 0
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.playing:
			active += 1
	return active


func _wait_for_idle_voices(audio: WorldAudio, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while _active_voices(audio) > 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout


func _mouse_button(sling: Slingshot, pressed: bool, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	if pressed:
		sling._unhandled_input(event)
	else:
		sling._input(event)


func _mouse_motion(sling: Slingshot, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	sling._input(event)


func _touch(sling: Slingshot, pressed: bool, position: Vector2, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 3
	event.pressed = pressed
	event.canceled = canceled
	event.position = position
	if pressed:
		sling._unhandled_input(event)
	else:
		sling._input(event)


func _touch_drag(sling: Slingshot, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 3
	event.position = position
	sling._input(event)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
