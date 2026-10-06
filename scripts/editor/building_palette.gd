class_name BuildingPalette
extends AcceptDialog
## Нажимаемые целиком карточки с крупным предпросмотром готовых построек.

signal building_selected(index: int)

var cards: Array[Button] = []


func _ready() -> void:
	title = "Готовые постройки"
	ok_button_text = "Закрыть"
	get_ok_button().custom_minimum_size.y = 48
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	var hint := Label.new()
	hint.text = "Выбери постройку и нажми на свободное место поля. Она встанет на землю вместе с собаками."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	column.add_child(hint)
	for index in BuildingTemplates.LEVELS.size():
		var card := Button.new()
		card.custom_minimum_size.y = 152
		card.pressed.connect(func() -> void:
			hide()
			building_selected.emit(index)
		)
		column.add_child(card)
		cards.append(card)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side: String in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 12)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		margin.add_child(row)
		var preview := LevelThumbnail.new()
		preview.draft = BuildingTemplates.LEVELS[index]
		preview.view_bounds = BuildingTemplates.bounds_for(preview.draft).grow(24)
		row.add_child(preview)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(details)
		for text: String in [preview.draft.title, BuildingTemplates.HINTS[index]]:
			var label := Label.new()
			label.text = text
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 18)
			details.add_child(label)
		for child: Node in card.find_children("*", "Control", true, false):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_palette() -> void:
	var available := (get_parent() as Control).get_viewport_rect().size
	popup_centered(Vector2i(minf(760, available.x - 40), minf(600, available.y - 40)))
