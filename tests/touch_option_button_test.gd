extends SceneTree
## Настоящие события касания в PopupMenu; без глобальной эмуляции мыши.

var _checks: int = 0
var _failures: int = 0
var _selections: int = 0
var _picker: TouchOptionButton


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	_picker = TouchOptionButton.new()
	_picker.position = Vector2(200, 160)
	_picker.size = Vector2(250, 56)
	for title: String in ["Недоступно", "Первый", "Второй"]:
		_picker.add_item(title)
	_picker.set_item_disabled(0, true)
	_picker.select(1)
	_picker.item_selected.connect(func(_index: int) -> void: _selections += 1)
	root.add_child(_picker)
	await _open()
	_touch(0, true)
	_touch(0, false)
	_check(_picker.selected == 1 and _picker.get_popup().visible and _selections == 0, "Touching a disabled item leaves the menu and selection unchanged")
	_touch(2, true)
	_touch(2, false)
	_check(_picker.selected == 2 and not _picker.get_popup().visible and _selections == 1, "A direct touch selects exactly once and closes the menu")
	await _open()
	_touch(1, true, 3)
	_touch(2, true, 4)
	_touch(2, false, 4)
	_check(_picker.get_popup().visible and _picker.selected == 2, "A second finger cannot commit the first finger's selection")
	_touch(1, false, 3)
	_check(_picker.selected == 1 and _selections == 2, "The first finger still completes its own selection")
	await _open()
	_touch(2, true)
	_touch(2, false, 0, true)
	_check(_picker.selected == 1 and not _picker.get_popup().visible and _selections == 2, "A canceled touch closes without selecting")
	await _open()
	_touch(1, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _point(2)
	_picker.get_popup().push_input(drag, true)
	_touch(2, false)
	_check(_picker.selected == 2 and _selections == 3, "Dragging a touch chooses the item under its final position")
	await _open()
	_touch(1, true, 5)
	_picker.get_popup().hide()
	await _open()
	_touch(1, true, 6)
	_touch(1, false, 6)
	_check(_picker.selected == 1 and _selections == 4, "Hiding the menu clears the active finger before reopening")
	await _open()
	for pressed: bool in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = Vector2(_picker.get_popup().position) + _point(2)
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		root.push_input(mouse, true)
	_check(_picker.selected == 2 and _selections == 5, "Ordinary mouse selection still works without duplicate signals")
	_check(Input.get_mouse_button_mask() == 0, "Touch adaptation never leaves a global mouse button pressed")
	_picker.queue_free()
	await process_frame
	print("Touch option button checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _open() -> void:
	await process_frame
	await process_frame
	_picker.show_popup()
	await process_frame
	await process_frame


func _point(index: int) -> Vector2:
	var popup := _picker.get_popup()
	return Vector2(popup.size.x * 0.5, popup.size.y * (float(index) + 0.5) / 3.0)


func _touch(item: int, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = _point(item)
	touch.index = index
	touch.pressed = pressed
	touch.canceled = canceled
	_picker.get_popup().push_input(touch, true)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
