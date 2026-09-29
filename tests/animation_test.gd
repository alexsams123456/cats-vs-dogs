extends SceneTree
## Animation/audio lifecycle checks; physics and collision transforms stay intact.

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")
const BACKDROP := preload("res://scripts/world/backdrop.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_idle_cadence()
	var bus_index := AudioServer.get_bus_index(&"SFX")
	_check(bus_index >= 0, "Project loads its SFX audio bus")
	for stream: AudioStreamWAV in [CatVoice.MEOW_CLASSIC, CatVoice.MEOW_BOMB, CatVoice.MEOW_ZIGZAG]:
		_check(stream.get_length() > 0.35 and stream.get_length() < 0.6, "Meow has bounded duration")
		_check(not stream.data.is_empty() and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Imported meow contains audio without looping")
	var world := Node2D.new()
	root.add_child(world)
	var backdrop := BACKDROP.new()
	world.add_child(backdrop)
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.definition = CharacterCatalog.CATS[0]
	cat.position = Vector2(200, 180)
	cat.freeze = true
	cat.gravity_scale = 0.0
	world.add_child(cat)
	var voice := cat.get_node("Voice") as CatVoice
	await create_timer(0.2).timeout
	_check(backdrop.animation_time > 0.0 and cat.visual_time > 0.0, "Idle world and hero animate")
	_check(voice.play_count == 0 and cat.meow_count == 0, "Waiting cat stays quiet")
	_check(cat.position == Vector2(200, 180) and cat.scale == Vector2.ONE, "Idle animation leaves the body transform unchanged")
	cat.set_aiming(true)
	await process_frame
	_check(cat.expression == &"aim", "Aiming changes the facial expression")
	cat.set_aiming(false)
	cat.launch(Vector2(300, 0))
	_check(cat.meow_count == 1 and voice.play_count == 1, "Launch synchronizes mouth and sound")
	_check(voice.playing, "Launch starts the audio player")
	await create_timer(0.06).timeout
	paused = true
	var world_time: float = backdrop.animation_time
	var hero_time := cat.visual_time
	await create_timer(0.2, true).timeout
	_check(is_equal_approx(backdrop.animation_time, world_time), "Pause freezes world animation")
	_check(is_equal_approx(cat.visual_time, hero_time), "Pause freezes hero expression timing")
	_check(voice.stream_paused, "Pause suspends active meow playback")
	paused = false
	await create_timer(0.1).timeout
	_check(backdrop.animation_time > world_time and cat.visual_time > hero_time, "Animation resumes after pause")
	_check(not voice.stream_paused, "Audio resumes after pause")
	await create_timer(0.59).timeout
	_check(cat.meow_count >= 2 and voice.play_count >= 2, "Cat meows again within 0.75 seconds of flight")
	var toggle := SoundToggle.new()
	root.add_child(toggle)
	toggle.pressed.emit()
	_check(AudioServer.is_bus_mute(bus_index), "Sound button mutes the shared SFX bus")
	var previous_play_count := voice.play_count
	voice.play_meow()
	_check(voice.play_count == previous_play_count, "Muted voice does not start a new sound")
	await create_timer(2.0).timeout
	_check(cat.meow_count <= CatProjectile.MAX_MEOWS, "Long flights have a bounded number of meows")
	_check(cat.scale.is_equal_approx(Vector2.ONE) and cat.get_node("CollisionShape2D").scale.is_equal_approx(Vector2.ONE), "Flying squash never resizes collision geometry")
	toggle.pressed.emit()
	_check(not AudioServer.is_bus_mute(bus_index), "Sound button restores audio")
	toggle.queue_free()
	world.queue_free()
	await process_frame
	await _test_meow_limit()
	await _test_impact()
	print("Animation checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_idle_cadence() -> void:
	for fps in [30, 60]:
		for phase in [0.0, 1.7, 8.6, 24.3]:
			var blinks: int = 0
			var smiles: int = 0
			var open_frames: int = 0
			var relaxed_frames: int = 0
			var independent_frames: int = 0
			var was_closed: bool = false
			var was_smiling: bool = false
			var ear_min: float = 0.0
			var ear_max: float = 0.0
			var previous_smile: float = HeroVisual._idle_smile(0.0, phase)
			var smooth_smiles: bool = true
			for frame in 12 * fps:
				var time: float = float(frame) / float(fps)
				var blink: float = HeroVisual._blink(time, phase)
				var smile: float = HeroVisual._idle_smile(time, phase)
				var left_ear: float = HeroVisual._ear_twitch(time, phase, -1.0)
				var right_ear: float = HeroVisual._ear_twitch(time, phase, 1.0)
				if blink < 0.2 and not was_closed:
					blinks += 1
				if smile > 0.9 and not was_smiling:
					smiles += 1
				if blink > 0.9:
					open_frames += 1
				if smile < 0.1:
					relaxed_frames += 1
				if absf(left_ear - right_ear) > 0.8:
					independent_frames += 1
				ear_min = minf(ear_min, left_ear)
				ear_max = maxf(ear_max, left_ear)
				smooth_smiles = smooth_smiles and absf(smile - previous_smile) < 0.25
				previous_smile = smile
				was_closed = blink < 0.2
				was_smiling = smile > 0.9
			_check(blinks >= 6 and blinks <= 10, "Idle heroes blink often at both display rates")
			_check(open_frames > 9 * fps, "Frequent blinks stay short and readable")
			_check(smiles >= 3 and smiles <= 5 and relaxed_frames > 5 * fps, "Idle heroes alternate smiles with a relaxed face")
			_check(smooth_smiles, "Smiles ease in and out instead of snapping")
			_check(ear_min < -2.0 and ear_max > 2.0 and independent_frames > 3 * fps, "Both ears make visible independent twitches")
	_check(not is_equal_approx(HeroVisual._idle_smile(0.7, 0.0), HeroVisual._idle_smile(0.7, 1.7)), "Neighboring heroes smile at different times")


func _test_meow_limit() -> void:
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.position = Vector2(0, -500)
	cat.gravity_scale = 0.0
	root.add_child(cat)
	cat.launch(Vector2(300, 0))
	await create_timer(3.5).timeout
	_check(cat.meow_count == CatProjectile.MAX_MEOWS, "A long uninterrupted flight uses the full voice budget")
	var voice := cat.get_node("Voice") as CatVoice
	_check(voice.play_count == CatProjectile.MAX_MEOWS, "Each flight meow plays once without overlapping itself")
	cat.queue_free()
	await process_frame


func _test_impact() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(600, 400)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 20)
	collision.shape = shape
	floor_body.add_child(collision)
	world.add_child(floor_body)
	var cat := CAT_SCENE.instantiate() as CatProjectile
	cat.position = Vector2(600, 300)
	cat.gravity_scale = 0.0
	world.add_child(cat)
	cat.launch(Vector2(0, 250))
	await create_timer(0.4).timeout
	_check(cat.expression == &"hit", "First impact produces a surprised face")
	var count_at_impact := cat.meow_count
	await create_timer(1.2).timeout
	_check(cat.meow_count == count_at_impact, "Landed cats stop requesting flight meows")
	var dog := DOG_SCENE.instantiate() as DogTarget
	dog.definition = CharacterCatalog.find_dog(&"armored")
	dog.position = Vector2(100, 100)
	dog.freeze = true
	world.add_child(dog)
	await create_timer(0.1).timeout
	_check(dog.visual_time > 0.0, "Dogs animate while waiting")
	dog.receive_hit(700.0)
	await process_frame
	_check(dog.expression == &"hit" and not dog.shield_active, "Shield impact changes the dog's face")
	_check(dog.scale == Vector2.ONE and dog.get_node("CollisionShape2D").scale == Vector2.ONE, "Dog animation preserves collision geometry")
	world.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
