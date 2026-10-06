class_name LevelReviewDialog
extends AcceptDialog
## Список подсказок с переходом к конкретному объекту; черновик не меняет.

signal object_requested(kind: int, index: int)
signal play_requested

const DISPLAY_LIMIT: int = 12

var message: Label
var test_button: Button
var issue_buttons: Array[Button] = []
var _list: VBoxContainer


func _ready() -> void:
	title = "Проверить двор"
	ok_button_text = "Закрыть"
	get_ok_button().custom_minimum_size.y = 48
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)
	message = _label()
	_list.add_child(message)
	test_button = Button.new()
	test_button.text = "Испытать уровень"
	test_button.custom_minimum_size.y = 48
	test_button.pressed.connect(func() -> void:
		hide()
		play_requested.emit()
	)
	_list.add_child(test_button)


func show_review(level: LevelDefinition) -> void:
	for button in issue_buttons:
		_list.remove_child(button)
		button.queue_free()
	issue_buttons.clear()
	var issues := LevelLayoutReview.inspect(level)
	message.text = tr("По геометрии замечаний нет. Проверь устойчивость и проходимость в пробном бою.") if issues.is_empty() else tr("Подсказок: %d. Нажми на подсказку, чтобы выбрать объект. Это не проверка проходимости.") % issues.size()
	if level.dog_positions.is_empty():
		message.text = tr("Добавь хотя бы одну собаку, чтобы появилась цель уровня.") + "\n" + message.text
	if level.title.strip_edges().is_empty():
		message.text = tr("Укажи название") + "\n" + message.text
	if issues.size() > DISPLAY_LIMIT:
		message.text += "\n" + tr("Показаны первые %d подсказок. Исправь их и проверь двор снова.") % DISPLAY_LIMIT
	for issue: Dictionary in issues.slice(0, DISPLAY_LIMIT):
		var button := Button.new()
		button.custom_minimum_size.y = 100
		button.pressed.connect(func() -> void:
			hide()
			object_requested.emit(issue.kind, issue.index)
		)
		_list.add_child(button)
		issue_buttons.append(button)
		var label := _label()
		label.text = LevelLayoutReview.describe(issue)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 12
		label.offset_right = -12
		label.offset_top = 8
		label.offset_bottom = -8
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_child(label)
	test_button.disabled = not level.is_valid()
	_list.move_child(test_button, _list.get_child_count() - 1)
	var available := (get_parent() as Control).get_viewport_rect().size
	popup_centered(Vector2i(minf(760, available.x - 40), minf(600, available.y - 40)))


func _label() -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
