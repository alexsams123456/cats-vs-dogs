class_name GameHUD
extends CanvasLayer
## UI stays interactive while the physics tree is paused.

signal restart_requested
signal pause_requested
signal menu_requested
signal ability_requested
signal next_requested
signal camera_reset_requested

const INK := Color("254b4b")
const CREAM := Color("fff7df")
const TEAL := Color("387c73")

enum AbilityState { BEFORE_LAUNCH, READY, USED, CONTACTED, AUTOMATIC, WAITING }

var _root: Control
var _margin: MarginContainer
var _level_label: Label
var _stats: Label
var _hint: Label
var _overlay: ColorRect
var _result_title: Label
var _result_detail: Label
var _resume_button: Button
var _pause_button: Button
var _overlay_menu_button: Button
var _ability_button: Button
var _power_hint: Label
var _queue_label: Label
var _score_hint: Label
var _next_button: Button
var _pause_details: VBoxContainer
var _current_portrait: CharacterPortrait
var _current_card: PanelContainer
var _current_name: Label
var _ability_status: Label
var _ability_state: AbilityState = AbilityState.BEFORE_LAUNCH
var _cat_definition: CharacterDefinition
var _dog_definition: CharacterDefinition
var _editor_preview: bool = false
var _campaign_mode: bool = false
var _has_next_level: bool = false
var _mixed_dogs: bool = false
var _par_shots: int = 0
var _default_hint: String = ""
var _tutorial_hint: String = ""
var _help_button: Button
var _camera_button: Button
var _camera_hint: Label
var _help_card: PanelContainer
var _help_portrait: CharacterPortrait
var _help_name: Label
var _help_description: Label
var _touch_ui: bool = false
var _flying: bool = false
var _result_shown: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var theme := Theme.new()
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", INK)
	_root.theme = theme
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var brand := VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(brand)
	_level_label = _label("", 23)
	_level_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_level_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brand.add_child(_level_label)
	_stats = _label("", 18)
	brand.add_child(_stats)
	_camera_button = _button("Весь двор", camera_reset_requested.emit)
	_camera_button.custom_minimum_size = Vector2(136, 48)
	header.add_child(_camera_button)
	_help_button = _button("Справка", _toggle_help)
	_help_button.toggle_mode = true
	_help_button.custom_minimum_size = Vector2(136, 48)
	header.add_child(_help_button)
	_pause_button = _button("Пауза", pause_requested.emit)
	_pause_button.custom_minimum_size = Vector2(136, 48)
	header.add_child(_pause_button)
	_build_help(column)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	_build_footer(column)
	_build_overlay()
	set_touch_ui(OS.has_feature("mobile") or DisplayServer.is_touchscreen_available())
	get_viewport().size_changed.connect(_update_safe_margins)
	_update_safe_margins()


func _build_footer(column: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(footer)
	_current_card = PanelContainer.new()
	_current_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_current_card.size_flags_vertical = Control.SIZE_SHRINK_END
	var style := _style(Color("fff7e8"))
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_current_card.add_theme_stylebox_override("panel", style)
	footer.add_child(_current_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_current_card.add_child(row)
	_current_portrait = CharacterPortrait.new()
	_current_portrait.process_mode = Node.PROCESS_MODE_PAUSABLE
	_current_portrait.custom_minimum_size = Vector2(64, 64)
	row.add_child(_current_portrait)
	var identity := VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.custom_minimum_size.x = 220
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(identity)
	_current_name = _label("", 20)
	_current_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(_current_name)
	_ability_status = _label("", 16)
	_ability_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(_ability_status)
	_ability_button = _button("", ability_requested.emit)
	_ability_button.custom_minimum_size = Vector2(220, 56)
	_ability_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ability_button.add_theme_stylebox_override("normal", _style(Color("f6c15f")))
	_ability_button.add_theme_stylebox_override("hover", _style(Color("ffce78")))
	_ability_button.add_theme_color_override("font_color", INK)
	_ability_button.add_theme_color_override("font_hover_color", INK)
	row.add_child(_ability_button)
	_hint = _label("", 19)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_hint)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		set_touch_ui(true)
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		set_touch_ui(false)
	elif event is InputEventKey and event.pressed:
		set_touch_ui(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		restart_requested.emit()
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_requested.emit()
	elif event.is_action_pressed("ability"):
		get_viewport().set_input_as_handled()
		ability_requested.emit()


func set_loadout(cat: CharacterDefinition, dog: CharacterDefinition, mixed_dogs: bool = false) -> void:
	_cat_definition = cat
	_dog_definition = dog
	_mixed_dogs = mixed_dogs
	_help_portrait.definition = cat
	_current_portrait.definition = cat
	_current_name.text = tr("Сейчас: %s") % tr(cat.display_name)
	_help_name.text = tr(cat.display_name)
	_help_description.text = tr(cat.description)
	_help_card.hide()
	_help_button.set_pressed_no_signal(false)
	_ability_button.visible = not cat.ability_action.is_empty()
	set_ability_state(AbilityState.BEFORE_LAUNCH if _ability_button.visible else AbilityState.AUTOMATIC)
	_refresh_input_hints()


func set_ability_state(value: AbilityState) -> void:
	_ability_state = value
	_ability_button.disabled = value != AbilityState.READY
	match value:
		AbilityState.BEFORE_LAUNCH:
			_ability_status.text = tr("Запусти кота")
		AbilityState.READY:
			_ability_status.text = tr("Готово")
		AbilityState.USED:
			_ability_status.text = tr("Использовано")
		AbilityState.CONTACTED:
			_ability_status.text = tr("После удара недоступно")
		AbilityState.AUTOMATIC:
			_ability_status.text = tr("Автоматически")
		AbilityState.WAITING:
			_ability_status.text = tr("Подождём, пока всё уляжется…")


func set_editor_preview(value: bool) -> void:
	_editor_preview = value
	_overlay_menu_button.text = "Вернуться в редактор" if value else "К песочнице"


func set_campaign(value: bool, has_next: bool, par_shots: int) -> void:
	_campaign_mode = value
	_has_next_level = has_next
	_par_shots = par_shots
	_score_hint.text = _score_thresholds() if par_shots > 0 else ""
	_score_hint.visible = par_shots > 0
	if value:
		_overlay_menu_button.text = "В главное меню"


func set_queue(names: PackedStringArray, flying: bool) -> void:
	var translated_names := PackedStringArray()
	for character_name in names:
		translated_names.append(tr(character_name))
	_queue_label.text = tr("Далее: %s" if flying else "Отряд: %s") % " → ".join(translated_names)
	_queue_label.visible = not names.is_empty()


func set_tutorial_hint(message: String) -> void:
	_tutorial_hint = message
	if _result_shown:
		return
	if _touch_ui and message == "Шаг 2/2. Нажми кнопку способности или E в полёте, до удара.":
		message = "Шаг 2/2. Нажми кнопку способности в полёте, до удара."
	_hint.text = tr(message) if not message.is_empty() else _default_hint


func update_status(level_title: String, cats: int, dogs: int, flying: bool) -> void:
	if flying and not _flying:
		_help_card.hide()
		_help_button.set_pressed_no_signal(false)
	_flying = flying
	_level_label.text = tr("Проба  /  %s") % level_title if _editor_preview else level_title
	_stats.text = tr("Кошки: %d   •   Собаки: %d    ") % [cats, dogs]
	_default_hint = tr("Потяни кошку назад и отпусти — мышью или пальцем") if not flying and not _campaign_mode else ""
	set_tutorial_hint(_tutorial_hint)


func show_pause(value: bool) -> void:
	_overlay.visible = value
	_resume_button.visible = value
	_next_button.hide()
	_pause_details.show()
	_result_detail.hide()
	_result_title.text = "Передышка"
	_result_detail.text = "Приключение подождёт. Продолжим?"
	_pause_button.text = "Продолжить" if value else "Пауза"


func show_result(won: bool, shots_used: int = 0, stars: int = 0) -> void:
	_result_shown = true
	_overlay.show()
	_resume_button.hide()
	_pause_details.hide()
	_result_detail.show()
	_pause_button.disabled = true
	_result_title.text = "Победа за кошками!" if won else "Ещё одна попытка?"
	_result_detail.text = "Все собаки выбиты. Отличный бросок!" if won else "Кошки закончились. Попробуй другую траекторию."
	if _par_shots > 0:
		_result_detail.text = ("★".repeat(stars) + "☆".repeat(3 - stars) + "\n" if won else "") + tr("Выстрелов: %d\n%s") % [shots_used, _score_thresholds()]
	_next_button.visible = won and _campaign_mode and _has_next_level
	if won and _campaign_mode and not _has_next_level:
		_result_title.text = "Все уровни пройдены!"
	_hint.text = ""
	_power_hint.text = ""
	_ability_button.hide()
	_queue_label.hide()
	_score_hint.hide()
	_help_card.hide()
	_help_button.hide()
	_camera_button.hide()
	_camera_hint.hide()
	_current_card.hide()


func set_touch_ui(value: bool) -> void:
	_touch_ui = value
	_refresh_input_hints()
	set_tutorial_hint(_tutorial_hint)


func _refresh_input_hints() -> void:
	if _result_shown:
		return
	_camera_hint.text = tr("Два пальца: масштаб и перемещение двора." if _touch_ui else "Колесо мыши: приблизить или отдалить двор.")
	if _cat_definition == null:
		return
	var active := not _cat_definition.ability_action.is_empty()
	_ability_button.text = tr(_cat_definition.ability_action) + ("" if _touch_ui else "  ·  E")
	var hint := tr("Нажми кнопку способности в полёте, до удара.") if _touch_ui and active else tr(_cat_definition.ability_hint)
	_power_hint.text = tr(_cat_definition.display_name) + ": " + hint


func _toggle_help() -> void:
	_help_card.visible = _help_button.button_pressed


func _build_help(column: VBoxContainer) -> void:
	var help_row := HBoxContainer.new()
	# Keep the card above the slingshot, also for right-to-left text.
	help_row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	help_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(help_row)
	_help_card = PanelContainer.new()
	_help_card.layout_direction = Control.LAYOUT_DIRECTION_LOCALE
	_help_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_card.custom_minimum_size.x = 560
	var style := _style(Color("fff7e8"))
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_color = Color("dfd8bc")
	style.set_border_width_all(2)
	_help_card.add_theme_stylebox_override("panel", style)
	help_row.add_child(_help_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_help_card.add_child(row)
	_help_portrait = CharacterPortrait.new()
	_help_portrait.process_mode = Node.PROCESS_MODE_PAUSABLE
	_help_portrait.custom_minimum_size = Vector2(72, 72)
	_help_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_help_portrait)
	var explanation := VBoxContainer.new()
	explanation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(explanation)
	_help_name = _label("", 21)
	explanation.add_child(_help_name)
	_help_description = _label("", 17)
	_help_description.custom_minimum_size.x = 378
	_help_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_child(_help_description)
	_power_hint = _label("", 16)
	_power_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_child(_power_hint)
	_camera_hint = _label("", 16)
	_camera_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_child(_camera_hint)
	_help_card.hide()


func _score_thresholds() -> String:
	return tr("★★★ ≤ %d выстр.  ·  ★★ ≤ %d выстр.  ·  ★ за победу") % [_par_shots, _par_shots + 1]


func set_save_warning() -> void:
	_result_detail.text = tr(_result_detail.text) + "\n" + tr("Не удалось записать прогресс. Результат сохранён до закрытия игры.")


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.mouse_force_pass_scroll_events = false
	_overlay.color = Color(0.08, 0.19, 0.19, 0.48)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(600, 300)
	var style := _style(CREAM)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	card.add_child(content)
	_result_title = _label("", 36)
	_result_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_title.custom_minimum_size.x = 528
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_result_title)
	_result_detail = _label("", 21)
	_result_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_detail.custom_minimum_size.x = 528
	content.add_child(_result_detail)
	_pause_details = VBoxContainer.new()
	_pause_details.add_theme_constant_override("separation", 10)
	content.add_child(_pause_details)
	_queue_label = _label("", 17)
	_queue_label.custom_minimum_size.x = 528
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_details.add_child(_queue_label)
	_score_hint = _label("", 17)
	_score_hint.custom_minimum_size.x = 528
	_score_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause_details.add_child(_score_hint)
	_next_button = _button("Следующий уровень", next_requested.emit)
	_next_button.hide()
	content.add_child(_next_button)
	_resume_button = _button("Продолжить", pause_requested.emit)
	content.add_child(_resume_button)
	content.add_child(SoundControls.new())
	content.add_child(_button("Сыграть заново", restart_requested.emit))
	_overlay_menu_button = _button("К песочнице", menu_requested.emit)
	content.add_child(_overlay_menu_button)
	_overlay.hide()


func _update_safe_margins() -> void:
	var margins := Vector4(28, 22, 28, 22)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		var view := get_viewport().get_visible_rect().size
		if screen.x > 0 and screen.y > 0 and safe.has_area():
			var ratio := view / Vector2(screen)
			margins.x += safe.position.x * ratio.x
			margins.y += safe.position.y * ratio.y
			margins.z += (screen.x - safe.end.x) * ratio.x
			margins.w += (screen.y - safe.end.y) * ratio.y
	for entry in [["left", margins.x], ["top", margins.y], ["right", margins.z], ["bottom", margins.w]]:
		_margin.add_theme_constant_override("margin_" + entry[0], int(entry[1]))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.mouse_force_pass_scroll_events = false
	button.text = text
	button.custom_minimum_size = Vector2(136, 64)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_color_override("font_pressed_color", CREAM)
	button.add_theme_color_override("font_disabled_color", Color("507269"))
	button.add_theme_stylebox_override("normal", _style(TEAL))
	button.add_theme_stylebox_override("hover", _style(Color("47988b")))
	button.add_theme_stylebox_override("pressed", _style(INK))
	button.add_theme_stylebox_override("disabled", _style(Color("c3d5c7")))
	button.pressed.connect(action)
	return button


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(18)
	style.content_margin_left = 20
	style.content_margin_right = 20
	return style
