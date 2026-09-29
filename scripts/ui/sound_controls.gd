class_name SoundControls
extends HBoxContainer
## Общий выключатель и независимая громкость музыки/эффектов для меню и паузы.

signal settings_changed

var settings_button: Button
var dialog: AcceptDialog
var music_slider: HSlider
var effects_slider: HSlider


class TouchVolumeSlider extends HSlider:
	var _touch_index: int = -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed and not event.canceled and _touch_index < 0:
				_touch_index = event.index
				grab_focus()
				_set_touch_value(event.position.x)
				accept_event()
			elif event.index == _touch_index:
				_touch_index = -1
				accept_event()
		elif event is InputEventScreenDrag and event.index == _touch_index:
			_set_touch_value(event.position.x)
			accept_event()

	func _notification(what: int) -> void:
		if what in [NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
			_touch_index = -1

	func _set_touch_value(pointer_x: float) -> void:
		var half_grabber := get_theme_icon("grabber").get_width() * 0.5
		var ratio := clampf((pointer_x - half_grabber) / maxf(size.x - half_grabber * 2.0, 1.0), 0.0, 1.0)
		value = lerpf(min_value, max_value, 1.0 - ratio if is_layout_rtl() else ratio)


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var toggle := SoundToggle.new()
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(toggle)
	toggle.pressed.connect(settings_changed.emit)
	settings_button = Button.new()
	settings_button.text = "♫"
	settings_button.tooltip_text = "Настройки звука"
	settings_button.custom_minimum_size = Vector2(56, 56)
	settings_button.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed"]:
		settings_button.add_theme_stylebox_override(state, toggle.get_theme_stylebox(state))
		settings_button.add_theme_color_override("font_" + state + "_color" if state != "normal" else "font_color", Color("254b4b"))
	settings_button.pressed.connect(open_settings)
	add_child(settings_button)
	dialog = AcceptDialog.new()
	var dialog_theme := Theme.new()
	dialog_theme.default_font_size = 20
	dialog_theme.set_color("font_color", "Label", Color("fff9e9"))
	dialog.theme = dialog_theme
	dialog.title = "Настройки звука"
	dialog.ok_button_text = "Закрыть"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.min_size = Vector2i(420, 260)
	dialog.size = Vector2i(460, 320)
	dialog.add_theme_constant_override("buttons_min_width", 160)
	dialog.add_theme_constant_override("buttons_min_height", 56)
	add_child(dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	dialog.add_child(content)
	music_slider = _add_volume(content, "Музыка", &"Music")
	effects_slider = _add_volume(content, "Эффекты", &"SFX")
	var hint := Label.new()
	hint.text = "Громкость сохраняется автоматически"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 400
	hint.add_theme_font_size_override("font_size", 16)
	content.add_child(hint)


func open_settings() -> void:
	music_slider.set_value_no_signal(volume_for(&"Music") * 100.0)
	effects_slider.set_value_no_signal(volume_for(&"SFX") * 100.0)
	dialog.popup_centered(Vector2i(460, 320))
	music_slider.grab_focus()


func _add_volume(content: VBoxContainer, label_text: String, bus_name: StringName) -> HSlider:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 20)
	content.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	var slider := TouchVolumeSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(280, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = volume_for(bus_name) * 100.0
	slider.tooltip_text = label_text
	row.add_child(slider)
	var value_label := Label.new()
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value_label.custom_minimum_size.x = 64
	value_label.text = "%d%%" % int(slider.value)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		set_volume(bus_name, value / 100.0)
		value_label.text = "%d%%" % int(value)
		settings_changed.emit()
	)
	dialog.about_to_popup.connect(func() -> void:
		value_label.text = "%d%%" % int(slider.value)
	)
	return slider


static func volume_for(bus_name: StringName) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	return AudioServer.get_bus_volume_linear(index) if index >= 0 else 1.0


static func set_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_linear(index, clampf(value, 0.0, 1.0))
