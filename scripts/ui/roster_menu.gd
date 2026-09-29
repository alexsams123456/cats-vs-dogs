class_name RosterMenu
extends Control
## Выбор героев только для отдельной песочницы.

signal play_requested(cat_id: StringName, dog_id: StringName)
signal editor_requested
signal campaign_requested
signal selection_changed(cat_id: StringName, dog_id: StringName)

const INK := Color("254b4b")
const CREAM := Color("fff7df")
const PAPER := Color("fffdf5")
const TEAL := Color("387c73")
const ORANGE := Color("efa05a")
const MUTED := Color("73847a")
const CARDS_PER_PAGE: int = 3

var selected_cat_id: StringName = &"classic"
var selected_dog_id: StringName = &"scout"
var card_buttons: Array[Button] = []
var species_buttons: Dictionary[StringName, Button] = {}
var play_button: Button
var editor_button: Button
var campaign_button: Button
var current_page: int = 0
var page_count: int = 1
var previous_page_button: Button
var next_page_button: Button
var page_label: Label

var _species: StringName = &"cat"
var _margin: MarginContainer
var _cards: HBoxContainer
var _cat_tab: Button
var _dog_tab: Button
var _section_label: Label
var _summary: Label
var _card_ids: Array[StringName] = []
var _card_status: Array[Label] = []
var _card_footers: Array[PanelContainer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu_theme := Theme.new()
	menu_theme.default_font_size = 20
	menu_theme.set_color("font_color", "Label", INK)
	theme = menu_theme
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_margin.add_child(content)
	_build_header(content)
	_build_tabs(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_cards = HBoxContainer.new()
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 20)
	scroll.add_child(_cards)
	_build_pagination(content)
	_build_footer(content)
	resized.connect(_update_safe_margins)
	_update_safe_margins()
	show_species(_species)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var direction: int = 0
	if key.keycode == KEY_PAGEUP or key.physical_keycode == KEY_PAGEUP:
		direction = -1
	elif key.keycode == KEY_PAGEDOWN or key.physical_keycode == KEY_PAGEDOWN:
		direction = 1
	if direction == 0:
		return
	show_page(current_page + direction)
	if not card_buttons.is_empty():
		card_buttons[0].grab_focus()
	get_viewport().set_input_as_handled()


func set_selection(cat_id: StringName, dog_id: StringName) -> void:
	if _find_definition(cat_id, &"cat") != null:
		selected_cat_id = cat_id
	if _find_definition(dog_id, &"dog") != null:
		selected_dog_id = dog_id
	if is_instance_valid(_cards):
		show_page(_selected_page())


func show_species(species: StringName) -> void:
	if species != &"cat" and species != &"dog":
		return
	_species = species
	if not is_instance_valid(_cards):
		return
	show_page(_selected_page())


func show_page(index: int) -> void:
	if not is_instance_valid(_cards):
		return
	var definitions: Array[CharacterDefinition] = _definitions(_species)
	page_count = ceili(float(definitions.size()) / float(CARDS_PER_PAGE))
	current_page = clampi(index, 0, page_count - 1)
	var focused_card: bool = card_buttons.has(get_viewport().gui_get_focus_owner())
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	card_buttons.clear()
	_card_ids.clear()
	_card_status.clear()
	_card_footers.clear()
	var first: int = current_page * CARDS_PER_PAGE
	var end: int = mini(first + CARDS_PER_PAGE, definitions.size())
	for card_index in range(first, end):
		_build_card(definitions[card_index])
	for empty_slot in range(CARDS_PER_PAGE - card_buttons.size()):
		var spacer := Control.new()
		spacer.custom_minimum_size.x = 240
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards.add_child(spacer)
	previous_page_button.disabled = current_page == 0
	next_page_button.disabled = current_page == page_count - 1
	var visible_range := str(end) if first + 1 == end else "%d–%d" % [first + 1, end]
	page_label.text = tr("%s из %d  ·  %d / %d") % [visible_range, definitions.size(), current_page + 1, page_count]
	_refresh_selection()
	if focused_card and not card_buttons.is_empty():
		card_buttons[0].grab_focus()


func select_character(id: StringName) -> void:
	if _find_definition(id, _species) == null:
		return
	if _species == &"cat":
		selected_cat_id = id
	else:
		selected_dog_id = id
	if is_instance_valid(_cards):
		if not _card_ids.has(id):
			show_page(_selected_page())
		else:
			_refresh_selection()
	selection_changed.emit(selected_cat_id, selected_dog_id)


func _selected_page() -> int:
	var selected_id := selected_cat_id if _species == &"cat" else selected_dog_id
	var definitions: Array[CharacterDefinition] = _definitions(_species)
	for index in definitions.size():
		if definitions[index].id == selected_id:
			return floori(float(index) / float(CARDS_PER_PAGE))
	return 0


func _definitions(species: StringName) -> Array[CharacterDefinition]:
	return CharacterCatalog.CATS if species == &"cat" else CharacterCatalog.DOGS


func _build_header(content: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 74
	header.add_theme_constant_override("separation", 24)
	content.add_child(header)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -5)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	brand.add_child(_label("КОШКИ", 36, INK))
	brand.add_child(_label("ПРОТИВ СОБАК", 21, TEAL))
	var intro := _label("ПЕСОЧНИЦА\nПробуй героев и способности", 22, INK)
	intro.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(intro)
	header.add_child(SoundToggle.new())


func _build_tabs(content: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	_cat_tab = _button("Кошки", Vector2(176, 56))
	_cat_tab.toggle_mode = true
	_cat_tab.pressed.connect(show_species.bind(&"cat"))
	row.add_child(_cat_tab)
	_dog_tab = _button("Собаки", Vector2(176, 56))
	_dog_tab.toggle_mode = true
	_dog_tab.pressed.connect(show_species.bind(&"dog"))
	row.add_child(_dog_tab)
	species_buttons[&"cat"] = _cat_tab
	species_buttons[&"dog"] = _dog_tab
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_section_label = _label("", 17, MUTED)
	_section_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_section_label)


func _build_card(definition: CharacterDefinition) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(240, 350)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.toggle_mode = true
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = definition.ability_hint
	card.set_meta("character_id", definition.id)
	card.pressed.connect(select_character.bind(definition.id))
	_cards.add_child(card)
	card_buttons.append(card)
	_card_ids.append(definition.id)
	var padding := MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + edge, 12)
	card.add_child(padding)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_child(stack)
	var portrait := CharacterPortrait.new()
	portrait.definition = definition
	portrait.custom_minimum_size.y = 108
	stack.add_child(portrait)
	var character_name := _label(definition.display_name, 26, INK)
	character_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	character_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(character_name)
	var badge_frame := PanelContainer.new()
	badge_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := _style(definition.accent_color.lerp(CREAM, 0.86), 10)
	badge_style.content_margin_left = 12
	badge_style.content_margin_right = 12
	badge_style.content_margin_top = 3
	badge_style.content_margin_bottom = 3
	badge_frame.add_theme_stylebox_override("panel", badge_style)
	stack.add_child(badge_frame)
	var badge := _label(definition.tagline, 14, TEAL)
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.custom_minimum_size.x = 192
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_frame.add_child(badge)
	var description := _label(definition.description, 17, MUTED)
	description.custom_minimum_size.y = 60
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(spacer)
	var footer := PanelContainer.new()
	footer.custom_minimum_size.y = 36
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(footer)
	_card_footers.append(footer)
	var status := _label("", 17, INK)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(status)
	_card_status.append(status)


func _build_pagination(content: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	previous_page_button = _button("← Назад", Vector2(176, 64))
	previous_page_button.tooltip_text = "Предыдущие герои · Page Up"
	previous_page_button.pressed.connect(func() -> void: show_page(current_page - 1))
	row.add_child(previous_page_button)
	page_label = _label("", 18, MUTED)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(page_label)
	next_page_button = _button("Дальше →", Vector2(176, 64))
	next_page_button.tooltip_text = "Следующие герои · Page Down"
	next_page_button.pressed.connect(func() -> void: show_page(current_page + 1))
	row.add_child(next_page_button)
	for button in [previous_page_button, next_page_button]:
		button.add_theme_stylebox_override("normal", _style(PAPER, 14))
		button.add_theme_stylebox_override("hover", _style(Color("e3ecdb"), 14))
		button.add_theme_stylebox_override("pressed", _style(Color("d3e3ca"), 14))
		button.add_theme_stylebox_override("disabled", _style(Color("efeedb"), 14))
		button.add_theme_color_override("font_disabled_color", MUTED)


func _build_footer(content: VBoxContainer) -> void:
	var footer := PanelContainer.new()
	footer.custom_minimum_size.y = 80
	var footer_style := _style(INK, 22)
	footer_style.content_margin_left = 24
	footer_style.content_margin_right = 12
	footer_style.content_margin_top = 10
	footer_style.content_margin_bottom = 10
	footer.add_theme_stylebox_override("panel", footer_style)
	content.add_child(footer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	footer.add_child(row)
	var team := VBoxContainer.new()
	team.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	team.add_theme_constant_override("separation", 2)
	row.add_child(team)
	_summary = _label("", 23, CREAM)
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	team.add_child(_summary)
	team.add_child(_label("Герои для песочницы", 17, Color("bfd8c9")))
	campaign_button = _button("В меню", Vector2(190, 60))
	campaign_button.tooltip_text = "Шесть дворов, смешанные отряды и звёзды за прохождение"
	campaign_button.add_theme_stylebox_override("normal", _style(Color("e3ecdb"), 15))
	campaign_button.add_theme_stylebox_override("hover", _style(PAPER, 15))
	campaign_button.add_theme_stylebox_override("pressed", _style(Color("d3e3ca"), 15))
	campaign_button.pressed.connect(campaign_requested.emit)
	row.add_child(campaign_button)
	editor_button = _button("Редактор", Vector2(160, 60))
	editor_button.tooltip_text = "Создать свой уровень и попробовать его в бою"
	editor_button.add_theme_stylebox_override("normal", _style(CREAM, 15))
	editor_button.add_theme_stylebox_override("hover", _style(PAPER, 15))
	editor_button.add_theme_stylebox_override("pressed", _style(Color("dfdfcc"), 15))
	editor_button.pressed.connect(editor_requested.emit)
	row.add_child(editor_button)
	play_button = _button("Свободный бой", Vector2(208, 60))
	play_button.add_theme_font_size_override("font_size", 22)
	play_button.add_theme_stylebox_override("normal", _style(ORANGE, 15))
	play_button.add_theme_stylebox_override("hover", _style(ORANGE.lightened(0.12), 15))
	play_button.add_theme_stylebox_override("pressed", _style(ORANGE.darkened(0.10), 15))
	play_button.pressed.connect(func() -> void: play_requested.emit(selected_cat_id, selected_dog_id))
	row.add_child(play_button)


func _refresh_selection() -> void:
	var selected_id := selected_cat_id if _species == &"cat" else selected_dog_id
	for index in card_buttons.size():
		var chosen := _card_ids[index] == selected_id
		var card := card_buttons[index]
		card.set_pressed_no_signal(chosen)
		var normal := _card_style(chosen)
		card.add_theme_stylebox_override("normal", normal)
		card.add_theme_stylebox_override("pressed", normal)
		var hovered := _card_style(chosen)
		hovered.bg_color = Color("fffaf0")
		card.add_theme_stylebox_override("hover", hovered)
		card.add_theme_stylebox_override("hover_pressed", hovered)
		card.add_theme_stylebox_override("focus", _focus_style())
		_card_status[index].text = "В команде  ✓" if chosen else "Выбрать  →"
		_card_status[index].add_theme_color_override("font_color", CREAM if chosen else TEAL)
		_card_footers[index].add_theme_stylebox_override("panel", _style(TEAL if chosen else Color("edf1e5"), 12))
	_style_tab(_cat_tab, _species == &"cat")
	_style_tab(_dog_tab, _species == &"dog")
	_section_label.text = "10 КОШЕК · 10 СПОСОБНОСТЕЙ" if _species == &"cat" else "КТО ЗАЩИЩАЕТ ДВОР?"
	var cat := _find_definition(selected_cat_id, &"cat")
	var dog := _find_definition(selected_dog_id, &"dog")
	_summary.text = "%s    ×    %s" % [tr(cat.display_name), tr(dog.display_name)]


func _style_tab(button: Button, chosen: bool) -> void:
	button.set_pressed_no_signal(chosen)
	var background := TEAL if chosen else Color("ececda")
	button.add_theme_stylebox_override("normal", _style(background, 16))
	button.add_theme_stylebox_override("pressed", _style(background, 16))
	button.add_theme_stylebox_override("hover", _style(background.lightened(0.06), 16))
	button.add_theme_stylebox_override("hover_pressed", _style(background.lightened(0.06), 16))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, CREAM if chosen else TEAL)


func _update_safe_margins() -> void:
	var horizontal := maxf(24.0, (size.x - 1168.0) * 0.5)
	var vertical := maxf(20.0, (size.y - 680.0) * 0.5)
	var margins := Vector4(horizontal, vertical, horizontal, vertical)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0 and safe.has_area():
			var ratio := size / Vector2(screen)
			margins.x = maxf(margins.x, safe.position.x * ratio.x + 20.0)
			margins.y = maxf(margins.y, safe.position.y * ratio.y + 20.0)
			margins.z = maxf(margins.z, (screen.x - safe.end.x) * ratio.x + 20.0)
			margins.w = maxf(margins.w, (screen.y - safe.end.y) * ratio.y + 20.0)
	for entry in [["left", margins.x], ["top", margins.y], ["right", margins.z], ["bottom", margins.w]]:
		_margin.add_theme_constant_override("margin_" + entry[0], int(entry[1]))
	queue_redraw()


func _find_definition(id: StringName, species: StringName) -> CharacterDefinition:
	var definitions: Array[CharacterDefinition] = _definitions(species)
	for definition: CharacterDefinition in definitions:
		if definition.id == id:
			return definition
	return null


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_stylebox_override("focus", _focus_style())
	return button


func _card_style(chosen: bool) -> StyleBoxFlat:
	var style := _style(PAPER, 24)
	style.border_color = ORANGE if chosen else Color("dedfca")
	style.set_border_width_all(3 if chosen else 1)
	style.shadow_color = Color(0.15, 0.29, 0.26, 0.08)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 4)
	return style


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style


func _focus_style() -> StyleBoxFlat:
	var style := _style(Color.TRANSPARENT, 18)
	style.border_color = ORANGE
	style.set_border_width_all(3)
	style.expand_margin_left = 3
	style.expand_margin_top = 3
	style.expand_margin_right = 3
	style.expand_margin_bottom = 3
	return style


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), CREAM)
	draw_circle(Vector2(size.x + 36, -20), 310.0, Color("eeeacb"))
	draw_circle(Vector2(-90, size.y + 90), 320.0, Color("dce7d5"))
	_draw_paw(Vector2(size.x - 66, 66), -0.35, Color("e1dbb8"))
	_draw_paw(Vector2(52, size.y - 54), 0.4, Color("c3d5bd"))
	draw_arc(Vector2(size.x - 30, size.y + 74), 220.0, PI, TAU, 64, Color("e4dbc0"), 2.0, true)
	draw_arc(Vector2(size.x - 30, size.y + 74), 235.0, PI, TAU, 64, Color("e4dbc0"), 2.0, true)


func _draw_paw(center: Vector2, angle: float, color: Color) -> void:
	draw_set_transform(center, angle)
	draw_circle(Vector2(0, 6), 14.0, color)
	for point in [Vector2(-18, -11), Vector2(-6, -21), Vector2(8, -21), Vector2(20, -9)]:
		draw_circle(point, 6.5, color)
	draw_set_transform(Vector2.ZERO)
