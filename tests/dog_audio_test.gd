extends SceneTree
## Лай при приближении кота, ограничение хора и жизненный цикл звука.

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const HOUSE_SCENE := preload("res://scenes/actors/dog_house.tscn")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bus_index := AudioServer.get_bus_index(&"SFX")
	_check(bus_index >= 0, "Barks use the shared SFX bus")
	AudioServer.set_bus_mute(bus_index, false)
	for stream: AudioStreamWAV in [DogVoice.BARK_SCOUT, DogVoice.BARK_ARMORED, DogVoice.BARK_JUMPER]:
		_check(stream.get_length() >= 0.18 and stream.get_length() <= 0.5, "Bark has bounded duration")
		_check(not stream.data.is_empty() and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Imported bark contains audio without looping")
	await _test_variants()
	await _test_idle_and_shelter()
	await _test_early_alert_and_frost()
	await _test_approach()
	await _test_repeat_requires_approach()
	await _test_pause_mute_and_destruction(bus_index)
	await _test_idle_large_pack()
	await _test_large_pack()
	# Аудиосервер освобождает остановленные потоки после удаления проигрывателей.
	# Даём завершиться очистке и стеку последнего сценария до выхода из процесса.
	await create_timer(0.3).timeout
	print("Dog audio checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_variants() -> void:
	var world := _make_world()
	var streams: Array[AudioStreamWAV] = [DogVoice.BARK_SCOUT, DogVoice.BARK_ARMORED, DogVoice.BARK_JUMPER]
	for index in CharacterCatalog.DOGS.size():
		var dog := _make_dog(world, CharacterCatalog.DOGS[index])
		var voice := dog.get_node("Voice") as DogVoice
		_check(voice.stream == streams[index], "Dog variant selects its own bark")
		_check(voice.bus == &"SFX" and voice.max_polyphony == 1, "Each dog has one voice routed through SFX")
		_check(voice.volume_db >= -6.0 and voice.volume_db <= -3.0, "Bark remains audible over the -18 dB background music")
	var fallback := _make_dog(world)
	_check((fallback.get_node("Voice") as DogVoice).stream == DogVoice.BARK_SCOUT, "Dog without a definition uses the scout bark")
	_check(fallback.bark_cooldown_seconds >= 0.6 and fallback.bark_cooldown_seconds <= 1.0, "Default bark cadence leaves a short audible pause")
	world.queue_free()
	await process_frame


func _test_idle_and_shelter() -> void:
	var world := _make_world()
	var house := HOUSE_SCENE.instantiate() as DogHouse
	house.position = Vector2(600, 300) - house.dog_offset()
	house.freeze = true
	house.collision_layer = 0
	house.collision_mask = 0
	world.add_child(house)
	var resident := _make_dog(world)
	_check(resident._idle_bark_delay_left >= 0.7 and resident._idle_bark_delay_left <= 1.9, "A level starts with a bark in the first two seconds")
	resident.enter_shelter(house)
	resident._idle_bark_delay_left = 0.02
	var neighbor := _make_dog(world)
	neighbor._idle_bark_delay_left = 0.03
	var resident_voice := resident.get_node("Voice") as DogVoice
	var neighbor_voice := neighbor.get_node("Voice") as DogVoice
	await create_timer(0.16).timeout
	_check(resident.is_sheltered() and resident_voice.play_count == 1, "A dog inside a kennel barks without waiting for a shot")
	_check(neighbor_voice.play_count == 0, "Idle pack answers with only one voice")
	_check(resident.expression == &"bark" and resident_voice.playing, "Idle bark synchronizes the sheltered dog's mouth")
	await create_timer(0.5).timeout
	neighbor._idle_bark_delay_left = 0.02
	await create_timer(0.16).timeout
	_check(neighbor_voice.play_count == 0, "The end of a bark does not start a delayed idle chorus")
	paused = true
	var cooldown := resident_voice._idle_pack_cooldown_left
	var idle_delay := neighbor._idle_bark_delay_left
	await create_timer(0.16, true).timeout
	_check(is_equal_approx(cooldown, resident_voice._idle_pack_cooldown_left) and is_equal_approx(idle_delay, neighbor._idle_bark_delay_left), "Pause preserves both idle timers and pack silence")
	paused = false
	var cat := _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(110, 0))
	await create_timer(0.16).timeout
	_check(neighbor_voice.play_count == 1 and resident_voice.play_count == 2, "Incoming cat reactions take priority over the idle pack interval")
	world.queue_free()
	await create_timer(0.1).timeout


func _test_early_alert_and_frost() -> void:
	var world := _make_world()
	var dog := _make_dog(world)
	var voice := dog.get_node("Voice") as DogVoice
	var cat := _make_cat(world, Vector2(120, 300))
	cat.launch(Vector2(110, 0))
	await create_timer(0.16).timeout
	_check(voice.play_count == 1 and cat.position.distance_to(dog.position) > 350.0, "Dog barks early enough to hear the voice before an incoming hit")
	world.queue_free()
	await create_timer(0.1).timeout
	world = _make_world()
	dog = _make_dog(world)
	voice = dog.get_node("Voice") as DogVoice
	dog.apply_frost(0.7)
	dog._idle_bark_delay_left = 0.02
	cat = _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(110, 0))
	await create_timer(0.16).timeout
	_check(voice.play_count == 0 and dog._bark_time_left == 0.0, "Frozen dog rejects both idle barking and an incoming cat")
	await create_timer(0.7).timeout
	_check(voice.play_count == 1, "Thawed dog can react to the still approaching cat")
	dog.apply_frost(0.3)
	_check(not voice.playing and dog._bark_time_left == 0.0, "Freezing a barking dog interrupts its voice and mouth animation")
	world.queue_free()
	await create_timer(0.1).timeout


func _test_approach() -> void:
	var world := _make_world()
	var dog := _make_dog(world)
	var voice := dog.get_node("Voice") as DogVoice
	var cat := _make_cat(world, Vector2(300, 300))
	await create_timer(0.16).timeout
	_check(voice.play_count == 0 and dog.expression == &"idle", "Waiting cat and dog stay quiet")
	cat.launch(Vector2(-200, 0))
	await create_timer(0.16).timeout
	_check(voice.play_count == 0, "Cat flying away does not trigger a bark")
	cat.queue_free()
	await process_frame
	cat = _make_cat(world, Vector2(0, 300))
	cat.launch(Vector2(180, 0))
	await create_timer(0.16).timeout
	_check(voice.play_count == 0, "Distant approaching cat does not trigger a bark")
	cat.queue_free()
	await process_frame
	cat = _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(110, 0))
	await create_timer(0.16).timeout
	_check(cat.position.x > 300.0 and voice.play_count == 1, "Actual launched cat triggers a bark while moving toward the dog")
	_check(voice.playing and dog.expression == &"bark" and dog._bark_time_left > 0.0, "Playing bark opens the dog's mouth")
	_check(dog.position == Vector2(600, 300) and dog.scale == Vector2.ONE and dog.get_node("CollisionShape2D").scale == Vector2.ONE, "Barking preserves body and collision transforms")
	await create_timer(0.5).timeout
	_check(voice.play_count == 1 and not voice.playing, "A repeated bark leaves a pause after the first voice")
	await create_timer(0.5).timeout
	_check(voice.play_count == 2, "A still approaching cat triggers a second bark within a little over one second")
	await create_timer(0.9).timeout
	_check(voice.play_count == 2 and not voice.playing, "One incoming cat triggers at most two barks")
	cat.queue_free()
	await process_frame
	cat = _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(180, 0))
	await create_timer(0.16).timeout
	_check(voice.play_count == 3, "A new incoming cat can trigger a bark after cooldown")
	cat.queue_free()
	await process_frame
	cat = _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(180, 0))
	await create_timer(0.13).timeout
	_check(voice.play_count == 3, "A new incoming cat cannot bypass the bark cooldown")
	world.queue_free()
	await create_timer(0.1).timeout


func _test_repeat_requires_approach() -> void:
	var world := _make_world()
	var dog := _make_dog(world)
	var voice := dog.get_node("Voice") as DogVoice
	var cat := _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(110, 0))
	await create_timer(0.16).timeout
	_check(voice.play_count == 1, "An approaching cat starts the first bark before changing direction")
	cat.linear_velocity = Vector2(-110, 0)
	await create_timer(1.0).timeout
	_check(voice.play_count == 1, "A cat flying away cannot trigger the second bark after cooldown")
	cat.position = Vector2(300, 300)
	cat.linear_velocity = Vector2.ZERO
	await create_timer(0.16).timeout
	_check(voice.play_count == 1, "A stopped cat cannot trigger the second bark")
	cat.linear_velocity = Vector2(110, 0)
	await create_timer(0.16).timeout
	_check(voice.play_count == 2, "The same cat can trigger its second bark when it approaches again")
	world.queue_free()
	await create_timer(0.1).timeout


func _test_pause_mute_and_destruction(bus_index: int) -> void:
	var world := _make_world()
	var dog := _make_dog(world, CharacterCatalog.find_dog(&"armored"))
	var voice := dog.get_node("Voice") as DogVoice
	dog._request_bark(1)
	await create_timer(0.03).timeout
	paused = true
	var visual_time := dog.visual_time
	var mouth_time := dog._bark_time_left
	var cooldown_time := dog._bark_cooldown_left
	var play_count := voice.play_count
	dog.bark_requested.emit()
	await create_timer(0.16, true).timeout
	_check(is_equal_approx(dog.visual_time, visual_time) and is_equal_approx(dog._bark_time_left, mouth_time), "Pause freezes dog animation and mouth timing")
	_check(is_equal_approx(dog._bark_cooldown_left, cooldown_time), "Pause also preserves the interval before the next bark")
	_check(voice.stream_paused and voice.play_count == play_count, "Pause suspends active bark and rejects new requests")
	paused = false
	await create_timer(0.03).timeout
	_check(dog.visual_time > visual_time and not voice.stream_paused, "Dog animation and bark resume after pause")
	await create_timer(0.5).timeout
	_check(dog._bark_time_left == 0.0 and dog.expression == &"idle", "Mouth closes when the bark finishes")
	var toggle := SoundToggle.new()
	root.add_child(toggle)
	toggle.pressed.emit()
	dog.bark_requested.emit()
	await process_frame
	_check(AudioServer.is_bus_mute(bus_index) and voice.play_count == play_count, "Shared sound button prevents new barks")
	_check(dog._bark_time_left == 0.0 and dog.expression == &"idle", "Muted bark does not start a silent mouth animation")
	toggle.pressed.emit()
	dog.bark_requested.emit()
	await process_frame
	_check(not AudioServer.is_bus_mute(bus_index) and voice.play_count == play_count + 1 and voice.playing, "Shared sound button restores barks")
	dog.receive_hit(700.0)
	await process_frame
	_check(dog.expression == &"hit" and not dog.shield_active, "Shield hit expression takes priority over an active bark")
	play_count = voice.play_count
	var voice_ref: WeakRef = weakref(voice)
	dog.destroy()
	dog.bark_requested.emit()
	_check(voice.play_count == play_count, "Destroyed dog cannot start another bark")
	await create_timer(0.1).timeout
	_check(voice_ref.get_ref() == null, "Destroying a dog releases its active audio player")
	dog = _make_dog(world)
	voice = dog.get_node("Voice") as DogVoice
	dog.bark_requested.emit()
	play_count = voice.play_count
	voice_ref = weakref(voice)
	dog.queue_free()
	dog.bark_requested.emit()
	_check(voice.play_count == play_count, "Dog queued for deletion cannot start another bark")
	await create_timer(0.1).timeout
	_check(voice_ref.get_ref() == null, "Queued dog releases its active audio player")
	dog = _make_dog(world)
	voice = dog.get_node("Voice") as DogVoice
	dog.bark_requested.emit()
	voice_ref = weakref(voice)
	world.queue_free()
	toggle.queue_free()
	await create_timer(0.1).timeout
	_check(voice_ref.get_ref() == null and get_nodes_in_group(&"dog_voices").is_empty(), "Leaving the scene releases voices and their shared limit")


func _test_idle_large_pack() -> void:
	var world := _make_world()
	var voices: Array[DogVoice] = []
	for index in 200:
		var dog := _make_dog(world)
		dog._idle_bark_delay_left = 0.02
		voices.append(dog.get_node("Voice") as DogVoice)
	await create_timer(0.2).timeout
	_check(_total_plays(voices) == 1, "A pack of 200 idle dogs starts only one greeting bark")
	await create_timer(0.5).timeout
	for voice in voices:
		voice.play_idle_bark()
	_check(_total_plays(voices) == 1, "The idle pack stays quiet after the first bark finishes")
	await create_timer(DogVoice.IDLE_PACK_INTERVAL).timeout
	_check(_total_plays(voices) == 2, "The idle pack can bark again after its shared interval")
	world.queue_free()
	await create_timer(0.1).timeout


func _test_large_pack() -> void:
	var world := _make_world()
	var voices: Array[DogVoice] = []
	for index in 200:
		var dog := _make_dog(world, CharacterCatalog.DOGS[index % CharacterCatalog.DOGS.size()])
		voices.append(dog.get_node("Voice") as DogVoice)
	var cat := _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(110, 0))
	await create_timer(0.16).timeout
	_check(_total_plays(voices) == 2, "A pack of 200 dogs starts at most two simultaneous barks")
	for voice in voices:
		voice.get_parent().bark_requested.emit()
	_check(_total_plays(voices) == 2, "Repeated signals neither overlap a voice nor exceed the shared limit")
	await create_timer(0.65).timeout
	_check(_total_plays(voices) == 2, "Rejected pack requests do not become a delayed chorus for the same cat")
	await create_timer(0.4).timeout
	_check(_total_plays(voices) == 4, "Only the two accepted dogs repeat their bark after the pause")
	var dogs_heard: int = 0
	var active_voices: int = 0
	for voice in voices:
		if voice.play_count > 0:
			dogs_heard += 1
		if voice.playing:
			active_voices += 1
	_check(dogs_heard == 2 and active_voices <= DogVoice.MAX_VOICES, "Repeat barks preserve the shared voice limit without waking rejected dogs")
	await create_timer(0.9).timeout
	_check(_total_plays(voices) == 4, "A large pack also respects the two-bark limit per incoming cat")
	cat.queue_free()
	await process_frame
	cat = _make_cat(world, Vector2(300, 300))
	cat.launch(Vector2(180, 0))
	await create_timer(0.16).timeout
	_check(_total_plays(voices) == 6, "Finished voices release capacity for the next incoming cat")
	world.queue_free()
	await create_timer(0.1).timeout
	_check(get_nodes_in_group(&"dog_voices").is_empty(), "Large pack cleanup leaves no voice reservations")


func _make_world() -> Node2D:
	var world := Node2D.new()
	root.add_child(world)
	return world


func _make_dog(world: Node2D, definition: CharacterDefinition = null) -> DogTarget:
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = definition
	dog.position = Vector2(600, 300)
	dog.freeze = true
	dog.gravity_scale = 0.0
	dog.collision_layer = 0
	dog.collision_mask = 0
	world.add_child(dog)
	return dog


func _make_cat(world: Node2D, position: Vector2) -> CatProjectile:
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.position = position
	cat.freeze = true
	cat.gravity_scale = 0.0
	cat.linear_damp = 0.0
	cat.collision_layer = 0
	cat.collision_mask = 0
	world.add_child(cat)
	return cat


func _total_plays(voices: Array[DogVoice]) -> int:
	var total: int = 0
	for voice in voices:
		total += voice.play_count
	return total


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
