class_name SoundToggle
extends Button
## AudioServer retains the shared setting when menu and round scenes change.


func _ready() -> void:
	custom_minimum_size = Vector2(158, 56)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("e3ecdb")
	style.set_corner_radius_all(14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("d3e3ca")
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		add_theme_color_override(state, Color("254b4b"))
	pressed.connect(_toggle)
	_refresh()


func _toggle() -> void:
	set_muted(not is_muted())
	_refresh()


func _refresh() -> void:
	var muted := is_muted()
	text = "Звук: выкл" if muted else "Звук: вкл"
	tooltip_text = "Включить звуки" if muted else "Выключить звуки"


static func is_muted() -> bool:
	var bus_index := AudioServer.get_bus_index(&"SFX")
	return bus_index >= 0 and AudioServer.is_bus_mute(bus_index)


static func set_muted(value: bool) -> void:
	for bus_name in [&"SFX", &"Music"]:
		var bus_index := AudioServer.get_bus_index(bus_name)
		if bus_index >= 0:
			AudioServer.set_bus_mute(bus_index, value)
