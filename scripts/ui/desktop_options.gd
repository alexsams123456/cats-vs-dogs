class_name DesktopOptions
extends Button
## Настройки ПК в отдельном окне; захват клавиши не запускает игровые действия.

signal settings_changed

var preferences: DesktopPreferences = DesktopPreferences.new()
var dialog: AcceptDialog
var binding_buttons: Array[Button] = []
var fullscreen_toggle: CheckButton
var shake_toggle: CheckButton
var particles_toggle: CheckButton
var status: Label
var _listening: int = -1


class BindingCapture extends Control:
	signal key_received(event: InputEvent)

	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			key_received.emit(event)


func _ready() -> void:
	text = tr("ПК")
	tooltip_text = tr("Управление и экран")
	custom_minimum_size = Vector2(56, 56)
	visible = not OS.has_feature("mobile")
	pressed.connect(open_settings)
	dialog = AcceptDialog.new()
	dialog.title = tr("Настройки ПК")
	dialog.ok_button_text = tr("Закрыть")
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.min_size = Vector2i(480, 540)
	dialog.size = Vector2i(540, 580)
	dialog.add_theme_constant_override("buttons_min_width", 160)
	dialog.add_theme_constant_override("buttons_min_height", 44)
	var ui_theme := Theme.new()
	ui_theme.default_font = preload("res://assets/fonts/interface_font.tres")
	ui_theme.default_font_size = 18
	ui_theme.set_color("font_color", "Label", Color("fff9e9"))
	dialog.theme = ui_theme
	add_child(dialog)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	dialog.add_child(content)
	var capture := BindingCapture.new()
	capture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capture.key_received.connect(_handle_key)
	content.add_child(capture)
	for index in DesktopPreferences.ACTIONS.size():
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := _label(tr(DesktopPreferences.TITLES[index]))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(170, 42)
		button.pressed.connect(_listen.bind(index))
		row.add_child(button)
		binding_buttons.append(button)
	fullscreen_toggle = _toggle(content, "Полный экран")
	fullscreen_toggle.disabled = OS.has_feature("web") or DisplayServer.get_name() == "headless"
	fullscreen_toggle.toggled.connect(func(value: bool) -> void:
		preferences.fullscreen = value
		settings_changed.emit()
	)
	shake_toggle = _toggle(content, "Тряска камеры")
	shake_toggle.toggled.connect(func(value: bool) -> void:
		preferences.screen_shake = value
		settings_changed.emit()
	)
	particles_toggle = _toggle(content, "Меньше частиц")
	particles_toggle.toggled.connect(func(value: bool) -> void:
		preferences.reduced_particles = value
		settings_changed.emit()
	)
	content.add_child(_label(tr("Мышь: потяни рогатку и отпусти. Колесо: масштаб. Esc: пауза или отмена выбора клавиши.")))
	status = _label(tr("Настройки сохраняются автоматически"))
	content.add_child(status)
	var reset := Button.new()
	reset.text = tr("Сбросить клавиши")
	reset.custom_minimum_size.y = 42
	reset.pressed.connect(func() -> void:
		preferences.keys = DesktopPreferences.DEFAULT_KEYS.duplicate()
		_listening = -1
		_refresh()
		settings_changed.emit()
	)
	content.add_child(reset)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			_listening = -1
	)


func open_settings() -> void:
	_listening = -1
	_refresh()
	dialog.popup_centered(Vector2i(540, 580))
	binding_buttons[0].grab_focus()


func _listen(index: int) -> void:
	_listening = index
	_refresh()
	status.text = tr("Нажми новую клавишу. Esc — отмена.")


func _handle_key(event: InputEvent) -> void:
	if not dialog.visible or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		dialog.set_input_as_handled()
		if event.echo:
			return
		if _listening >= 0:
			_listening = -1
			_refresh()
		else:
			dialog.hide()
		return
	if _listening < 0:
		return
	dialog.set_input_as_handled()
	if event.echo:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
		status.text = tr("Выбери одну клавишу без Ctrl, Alt или Shift.")
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var error := preferences.bind_key(_listening, code)
	if error != OK:
		status.text = tr("Эта клавиша занята или недоступна.")
		return
	_listening = -1
	_refresh()
	settings_changed.emit()


func _refresh() -> void:
	for index in binding_buttons.size():
		binding_buttons[index].text = tr("Нажми клавишу…") if index == _listening else preferences.key_name(index)
	fullscreen_toggle.set_pressed_no_signal(preferences.fullscreen)
	shake_toggle.set_pressed_no_signal(preferences.screen_shake)
	particles_toggle.set_pressed_no_signal(preferences.reduced_particles)
	status.text = tr("Настройки сохраняются автоматически")


func _toggle(content: VBoxContainer, title: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = tr(title)
	toggle.custom_minimum_size.y = 38
	content.add_child(toggle)
	return toggle


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	return label
