class_name RewardCollection
extends VBoxContainer
## Коллекция с условиями и прогрессом, доступная мышью и касанием.

var profile: PlayerProfile
var cards: Array[PanelContainer] = []
var summary: Label
var scroll: ScrollContainer
var _grid: GridContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 10)
	summary = _label(_fraction("Награды: %d / %d") % [profile.rewards.size(), RewardCatalog.IDS.size()], 28)
	add_child(summary)
	add_child(_label(tr("Собирай значки за победы и испытания. Награды сохраняются на этом устройстве."), 17))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	for index in RewardCatalog.IDS.size():
		_add_card(index)
	resized.connect(_update_columns)
	_update_columns()


func _add_card(index: int) -> void:
	var unlocked := profile.rewards.has(RewardCatalog.IDS[index])
	var card := PanelContainer.new()
	card.name = RewardCatalog.IDS[index]
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff4cf") if unlocked else Color("e7ecdf")
	style.border_color = Color("e9b84c") if unlocked else Color("c4d0be")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", style)
	_grid.add_child(card)
	cards.append(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var badge := MenuIcon.new()
	badge.kind = RewardCatalog.ICONS[index]
	badge.color = Color("a66d26") if unlocked else Color("8b9982")
	badge.custom_minimum_size = Vector2(64, 64)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	row.add_child(column)
	column.add_child(_label(tr(RewardCatalog.TITLES[index]), 22))
	column.add_child(_label(tr(RewardCatalog.DETAILS[index]), 17))
	var value := RewardCatalog.progress(index, profile)
	var state := _label(tr("Получено") if unlocked else _fraction("Прогресс: %d / %d") % [value.x, value.y], 16)
	state.add_theme_color_override("font_color", Color("986321") if unlocked else Color("65765c"))
	column.add_child(state)
	var bar := ProgressBar.new()
	bar.max_value = value.y
	bar.value = value.y if unlocked else value.x
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	column.add_child(bar)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _fraction(key: String) -> String:
	return tr(key).replace("%d / %d", "\u2066%d / %d\u2069")


func _update_columns() -> void:
	_grid.columns = 2 if size.x >= 1050 else 1
