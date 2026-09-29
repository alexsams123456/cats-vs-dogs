extends SceneTree
## Настройки звука мышью/касанием и Back в меню и паузе; профиль изолирован.

const APP_SCENE := preload("res://scenes/app.tscn")
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Для снимков настроек нужен графический запуск.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	AudioServer.set_bus_mute(0, true)
	GameLocalization.apply_locale("ru")
	var app := APP_SCENE.instantiate() as GameApp
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	for window_size: Vector2i in WINDOW_SIZES:
		root.size = window_size
		app.show_menu()
		await _layout()
		await _capture("menu")
		await _check_controls(app, _controls(app.campaign), "menu")
		app.start_campaign_level(0)
		await _layout()
		app.game.set_paused(true)
		await _layout()
		await _capture("pause")
		await _check_controls(app, _controls(app.game), "pause")
		root.go_back_requested.emit()
		_check(not paused and app.game != null, "Back resumes the round after closing settings")
	app.show_menu()
	await _layout()
	var playback: WeakRef = weakref((app.get_node("BackgroundMusic") as AudioStreamPlayer).get_stream_playback())
	app.queue_free()
	await _layout()
	var deadline := Time.get_ticks_msec() + 1000
	while playback.get_ref() != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(playback.get_ref() == null, "Capture releases its audio playback")
	print("Sound controls graphic checks: %d passed, %d failed. Images: .artifacts/sound-controls-*.png" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _check_controls(app: GameApp, controls: SoundControls, screen: String) -> void:
	_check(controls != null, "Screen exposes shared sound controls")
	if controls == null:
		return
	_check(root.get_visible_rect().encloses(controls.get_global_rect()), "Sound buttons fit the window: " + screen)
	var was_paused := paused
	for touch: bool in [false, true]:
		SoundControls.set_volume(&"Music", 0.8)
		SoundControls.set_volume(&"SFX", 0.8)
		_click(controls.settings_button, touch)
		await _layout()
		_check(controls.dialog.visible, "Settings open through a pointer: " + screen)
		_check(root.get_visible_rect().encloses(Rect2(Vector2(controls.dialog.position), Vector2(controls.dialog.size))), "Entire audio dialog fits the window")
		_check(controls.dialog.get_visible_rect().encloses(controls.dialog.get_ok_button().get_global_rect()), "Close button fits the audio dialog")
		_set_slider(controls.music_slider, 0.3, touch)
		_check(controls.music_slider.value > 20.0 and controls.music_slider.value < 40.0, "Pointer adjusts music volume")
		_check(is_equal_approx(SoundControls.volume_for(&"SFX"), 0.8), "Music slider preserves effects volume")
		_set_slider(controls.effects_slider, 0.65, touch)
		_check(controls.effects_slider.value > 55.0 and controls.effects_slider.value < 75.0, "Pointer adjusts effects volume")
		_check(SoundControls.volume_for(&"Music") < 0.4, "Effects slider preserves music volume")
		if touch:
			await _capture(screen + "-settings")
		root.go_back_requested.emit()
		await _layout()
		_check(not controls.dialog.visible and paused == was_paused, "Back closes settings without changing the screen pause")
		if screen == "menu":
			_check(app.campaign != null and app.campaign.page == &"home", "Audio Back preserves the main menu")


func _set_slider(slider: HSlider, fraction: float, touch: bool) -> void:
	var point := slider.get_global_rect().position + slider.size * Vector2(fraction, 0.5)
	var window := slider.get_window()
	var start := slider.get_global_rect().position + slider.size * Vector2(0.1, 0.5) if touch else point
	_pointer(window, start, true, touch)
	if touch:
		var drag := InputEventScreenDrag.new()
		drag.position = point
		drag.relative = point - start
		drag.index = 0
		window.push_input(drag, true)
	_pointer(window, point, false, touch)


func _click(control: Control, touch: bool) -> void:
	var point := control.get_global_rect().get_center()
	_pointer(control.get_window(), point, true, touch)
	_pointer(control.get_window(), point, false, touch)


func _pointer(window: Window, point: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
		event.pressed = pressed
		window.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		window.push_input(event, true)


func _controls(screen: Node) -> SoundControls:
	for node in screen.find_children("*", "HBoxContainer", true, false):
		if node is SoundControls:
			return node as SoundControls
	return null


func _layout() -> void:
	for frame in 6:
		await process_frame


func _capture(screen: String) -> void:
	await _layout()
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/sound-controls-%s-%dx%d.png" % [screen, root.size.x, root.size.y]
	_check(root.get_texture().get_image().save_png(path) == OK, "Saved screenshot: " + screen)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
