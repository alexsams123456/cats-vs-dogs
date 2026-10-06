class_name LevelCanvas
extends Control
## Поле редактирования: координаты уровня не зависят от размеров окна.

signal edit_started
signal edit_finished
signal selection_changed
signal tool_changed
signal placement_rejected(message: String)

enum Tool { SELECT, DOG, POST, BEAM, BOX, DOG_HOUSE, TOWER, HANGING_WEIGHT, BUILDING }

const WORLD_SIZE := Vector2(1280, 720)
const BUILD_AREA := Rect2(400, 100, 840, 520)
const TOWER_SIZE := Vector2(180, 160)
const NO_POINTER := -2
const MOUSE_POINTER := -1

var draft: LevelDefinition:
	set(value):
		draft = value
		if is_instance_valid(_backdrop) and draft != null:
			_backdrop.set_biome(StringName(draft.biome))
var tool: Tool = Tool.SELECT
var material_id: StringName = &"wood"
var house_type: StringName = &"classic"
var building_index: int = 0
var grid_enabled: bool = true
var show_guides: bool = true
var read_only: bool = false
var selected_kind: int = -1
var selected_index: int = -1
var _pointer: int = NO_POINTER
var _drag_origin := Vector2.ZERO
var _object_origin := Vector2.ZERO
var _backdrop: Node2D


func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	_backdrop = Node2D.new()
	_backdrop.set_script(preload("res://scripts/world/backdrop.gd"))
	_backdrop.show_behind_parent = true
	_backdrop.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_backdrop)
	if draft != null:
		_backdrop.set_biome(StringName(draft.biome))
	resized.connect(_update_transform)
	_update_transform()


func _scale_factor() -> float:
	return maxf(0.01, minf(size.x / WORLD_SIZE.x, size.y / WORLD_SIZE.y))


func _origin() -> Vector2:
	return (size - WORLD_SIZE * _scale_factor()) * 0.5


func world_to_local(point: Vector2) -> Vector2:
	return _origin() + point * _scale_factor()


func local_to_world(point: Vector2) -> Vector2:
	return (point - _origin()) / _scale_factor()


func _update_transform() -> void:
	if is_instance_valid(_backdrop):
		_backdrop.position = _origin()
		_backdrop.scale = Vector2.ONE * _scale_factor()
	queue_redraw()


func set_tool(value: Tool) -> void:
	cancel_drag()
	tool = value
	tool_changed.emit()
	queue_redraw()


func clear_selection() -> void:
	selected_kind = -1
	selected_index = -1
	selection_changed.emit()
	queue_redraw()


func selected_position() -> Vector2:
	if selected_kind == 0:
		return draft.dog_positions[selected_index]
	if selected_kind == 1:
		return draft.block_positions[selected_index]
	if selected_kind == 2:
		return draft.weight_positions[selected_index]
	return Vector2.ZERO


func selected_size() -> Vector2:
	if selected_kind == 2:
		return HangingWeightVisual.BOUNDS.size
	if selected_kind == 1:
		return draft.block_sizes[selected_index]
	if selected_kind == 0 and not draft.dog_house_material_at(selected_index).is_empty():
		return DogHouse.size_for(selected_house_type())
	return Vector2(50, 50)


func selected_material() -> StringName:
	if selected_kind == 1:
		return draft.block_material_at(selected_index)
	if selected_kind == 0:
		return draft.dog_house_material_at(selected_index)
	return &""


func selected_house_type() -> StringName:
	if selected_kind == 0:
		return draft.dog_house_type_at(selected_index)
	return &""


func set_selected_house_type(value: StringName) -> void:
	if not value in DogHouseTypes.IDS or selected_house_type().is_empty() or selected_house_type() == value:
		return
	cancel_drag()
	edit_started.emit()
	draft.normalize_materials()
	draft.dog_house_types[selected_index] = String(value)
	move_selected(selected_position())
	edit_finished.emit()


func set_selected_material(value: StringName) -> void:
	if not value in BlockMaterials.IDS or selected_material().is_empty() or selected_material() == value:
		return
	cancel_drag()
	edit_started.emit()
	draft.normalize_materials()
	if selected_kind == 1:
		draft.block_materials[selected_index] = String(value)
	else:
		draft.dog_house_materials[selected_index] = String(value)
	selection_changed.emit()
	edit_finished.emit()
	queue_redraw()


func _selection_offset() -> Vector2:
	if selected_kind == 2:
		return HangingWeightVisual.BOUNDS.get_center()
	if selected_kind == 0 and not selected_material().is_empty():
		return -DogHouse.offset_for(selected_house_type())
	return Vector2.ZERO


func constrain_position(point: Vector2, object_size: Vector2) -> Vector2:
	var half_size := object_size * 0.5
	return point.clamp(BUILD_AREA.position + half_size, BUILD_AREA.end - half_size)


func move_selected(point: Vector2) -> void:
	if selected_kind < 0:
		return
	var offset := _selection_offset()
	point = constrain_position(point + offset, selected_size()) - offset
	if selected_kind == 0:
		draft.dog_positions[selected_index] = point
	elif selected_kind == 2:
		draft.weight_positions[selected_index] = point
	else:
		draft.block_positions[selected_index] = point
	selection_changed.emit()
	queue_redraw()


func delete_selected() -> void:
	if selected_kind < 0:
		return
	cancel_drag()
	edit_started.emit()
	draft.normalize_materials()
	if selected_kind == 0:
		draft.dog_positions.remove_at(selected_index)
		if not draft.dog_kinds.is_empty():
			draft.dog_kinds.remove_at(selected_index)
		draft.dog_house_materials.remove_at(selected_index)
		draft.dog_house_types.remove_at(selected_index)
	elif selected_kind == 2:
		draft.weight_positions.remove_at(selected_index)
	else:
		draft.block_positions.remove_at(selected_index)
		draft.block_sizes.remove_at(selected_index)
		draft.block_materials.remove_at(selected_index)
	clear_selection()
	edit_finished.emit()


func rotate_selected() -> void:
	if selected_kind != 1:
		return
	cancel_drag()
	edit_started.emit()
	var dimensions := selected_size()
	draft.block_sizes[selected_index] = Vector2(dimensions.y, dimensions.x)
	move_selected(selected_position())
	edit_finished.emit()


func _gui_input(event: InputEvent) -> void:
	if read_only or _pointer != NO_POINTER or draft == null:
		return
	if event is InputEventMouseButton and event.device != -1:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_begin(local_to_world(event.position), MOUSE_POINTER)
			accept_event()
	elif event is InputEventScreenTouch and event.pressed and not event.canceled:
		_begin(local_to_world(event.position), event.index)
		accept_event()


func _input(event: InputEvent) -> void:
	if read_only or _pointer == NO_POINTER:
		return
	var released := false
	var point := Vector2.ZERO
	if _pointer == MOUSE_POINTER:
		if event is InputEventMouseMotion and event.device != -1:
			point = event.position
		elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			point = event.position
			released = true
		else:
			return
	elif event is InputEventScreenDrag and event.index == _pointer:
		point = event.position
	elif event is InputEventScreenTouch and event.index == _pointer:
		if event.canceled:
			cancel_drag()
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			return
		point = event.position
		released = true
	else:
		return
	var local_point := get_global_transform_with_canvas().affine_inverse() * point
	var destination := _object_origin + local_to_world(local_point) - _drag_origin
	# Простое выделение не смещает исходные объекты на сетку.
	if destination.distance_to(_object_origin) > 2.0:
		move_selected(_snap(destination))
	elif not selected_position().is_equal_approx(_object_origin):
		move_selected(_object_origin)
	if released:
		_pointer = NO_POINTER
		edit_finished.emit()
	get_viewport().set_input_as_handled()


func _begin(point: Vector2, pointer: int) -> void:
	if tool != Tool.SELECT:
		if BUILD_AREA.has_point(point):
			_add_object(point)
		return
	clear_selection()
	for index in range(draft.weight_positions.size() - 1, -1, -1):
		var bounds := Rect2(draft.weight_positions[index] + HangingWeightVisual.BOUNDS.position, HangingWeightVisual.BOUNDS.size)
		if bounds.grow(8.0 / _scale_factor()).has_point(point):
			selected_kind = 2
			selected_index = index
			break
	for index in range(draft.dog_positions.size() - 1, -1, -1):
		if selected_kind >= 0:
			break
		var dog_point := draft.dog_positions[index]
		var type_id := draft.dog_house_type_at(index)
		var house_size := DogHouse.size_for(type_id)
		var house_bounds := Rect2(dog_point - DogHouse.offset_for(type_id) - house_size * 0.5, house_size)
		var hits_house := not draft.dog_house_material_at(index).is_empty() and house_bounds.grow(8.0 / _scale_factor()).has_point(point)
		if hits_house or point.distance_to(dog_point) <= maxf(30.0, 22.0 / _scale_factor()):
			selected_kind = 0
			selected_index = index
			break
	if selected_kind < 0:
		for index in range(draft.block_positions.size() - 1, -1, -1):
			var bounds := Rect2(draft.block_positions[index] - draft.block_sizes[index] * 0.5, draft.block_sizes[index])
			if bounds.grow(8.0 / _scale_factor()).has_point(point):
				selected_kind = 1
				selected_index = index
				break
	selection_changed.emit()
	queue_redraw()
	if selected_kind >= 0:
		edit_started.emit()
		_pointer = pointer
		_drag_origin = point
		_object_origin = selected_position()


func _add_object(point: Vector2) -> void:
	if tool == Tool.BUILDING:
		_add_building(point)
		return
	var adds_dog := tool == Tool.DOG or tool == Tool.DOG_HOUSE
	var adds_weight := tool == Tool.HANGING_WEIGHT
	var block_count := 3 if tool == Tool.TOWER else 1
	if (adds_dog and draft.dog_positions.size() >= LevelDefinition.MAX_OBJECTS) or (adds_weight and draft.weight_positions.size() >= LevelDefinition.MAX_OBJECTS) or (not adds_dog and not adds_weight and draft.block_positions.size() + block_count > LevelDefinition.MAX_OBJECTS):
		return
	edit_started.emit()
	draft.normalize_materials()
	point = _snap(point)
	if adds_weight:
		selected_kind = 2
		selected_index = draft.weight_positions.size()
		var offset := HangingWeightVisual.BOUNDS.get_center()
		draft.weight_positions.append(constrain_position(point + offset, HangingWeightVisual.BOUNDS.size) - offset)
	elif adds_dog:
		selected_kind = 0
		selected_index = draft.dog_positions.size()
		if not draft.dog_kinds.is_empty():
			draft.dog_kinds.append("scout")
		if tool == Tool.DOG_HOUSE:
			var offset := DogHouse.offset_for(house_type)
			draft.dog_positions.append(constrain_position(point - offset, DogHouse.size_for(house_type)) + offset)
			draft.dog_house_materials.append(String(material_id))
			draft.dog_house_types.append(String(house_type))
		else:
			draft.dog_positions.append(constrain_position(point, Vector2(50, 50)))
			draft.dog_house_materials.append("")
			draft.dog_house_types.append("")
	elif tool == Tool.TOWER:
		point = constrain_position(point, TOWER_SIZE)
		selected_kind = 1
		selected_index = draft.block_positions.size() + 2
		_append_block(point + Vector2(-70, 10), Vector2(40, 140))
		_append_block(point + Vector2(70, 10), Vector2(40, 140))
		_append_block(point + Vector2(0, -70), Vector2(180, 20))
	else:
		var dimensions := Vector2(40, 140)
		if tool == Tool.BEAM:
			dimensions = Vector2(180, 20)
		elif tool == Tool.BOX:
			dimensions = Vector2(80, 80)
		selected_kind = 1
		selected_index = draft.block_positions.size()
		_append_block(constrain_position(point, dimensions), dimensions)
	tool = Tool.SELECT
	tool_changed.emit()
	selection_changed.emit()
	edit_finished.emit()
	queue_redraw()


func _append_block(point: Vector2, dimensions: Vector2) -> void:
	draft.block_positions.append(point)
	draft.block_sizes.append(dimensions)
	draft.block_materials.append(String(material_id))


func _add_building(point: Vector2) -> void:
	var addition := BuildingTemplates.at_position(building_index, _snap(point))
	var error := BuildingTemplates.placement_error(draft, addition)
	if not error.is_empty():
		placement_rejected.emit(error)
		return
	edit_started.emit()
	BuildingTemplates.append_to(draft, addition)
	selected_kind = 1
	selected_index = draft.block_positions.size() - 1
	tool = Tool.SELECT
	tool_changed.emit()
	selection_changed.emit()
	edit_finished.emit()
	queue_redraw()


func _snap(point: Vector2) -> Vector2:
	return point.snapped(Vector2(10, 10)) if grid_enabled else point


func cancel_drag() -> void:
	if _pointer == NO_POINTER:
		return
	_pointer = NO_POINTER
	move_selected(_object_origin)
	edit_finished.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_drag()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_drag()


func _draw() -> void:
	var zoom := _scale_factor()
	draw_set_transform(_origin(), 0, Vector2.ONE * zoom)
	if grid_enabled:
		for x in range(400, 1241, 10):
			draw_line(Vector2(x, 100), Vector2(x, 620), Color(0.2, 0.4, 0.35, 0.13 if x % 20 == 0 else 0.06), 1.0)
		for y in range(100, 621, 10):
			draw_line(Vector2(400, y), Vector2(1240, y), Color(0.2, 0.4, 0.35, 0.13 if y % 20 == 0 else 0.06), 1.0)
	if show_guides:
		draw_rect(BUILD_AREA, Color(0.2, 0.4, 0.35, 0.35), false, 2.0)
	draw_line(Vector2(235, 609), Vector2(235, 510), Color("b98149"), 22.0, true)
	draw_line(Vector2(235, 510), Vector2(207, 451), Color("b98149"), 17.0, true)
	draw_line(Vector2(235, 510), Vector2(263, 451), Color("b98149"), 17.0, true)
	draw_line(Vector2(207, 451), Vector2(263, 451), Color("765b4d"), 6.0, true)
	if draft != null:
		for index in draft.block_positions.size():
			draw_set_transform(world_to_local(draft.block_positions[index]), 0, Vector2.ONE * zoom)
			BlockVisual.paint(self, draft.block_sizes[index], draft.block_material_at(index))
		for index in draft.dog_positions.size():
			var house_material := draft.dog_house_material_at(index)
			if not house_material.is_empty():
				var type_id := draft.dog_house_type_at(index)
				draw_set_transform(world_to_local(draft.dog_positions[index] - DogHouse.offset_for(type_id)), 0, Vector2.ONE * zoom)
				DogHouse.paint(self, house_material, 0.0, type_id)
		for index in draft.dog_positions.size():
			draw_set_transform(world_to_local(draft.dog_positions[index]), 0, Vector2.ONE * zoom)
			var dog := CharacterCatalog.find_dog(StringName(draft.dog_kinds[index]) if not draft.dog_kinds.is_empty() else &"scout")
			HeroVisual.paint(self, &"dog", dog.id, dog.fur_color, dog.accent_color, 0, 0)
		for point in draft.weight_positions:
			draw_set_transform(world_to_local(point), 0, Vector2.ONE * zoom)
			HangingWeightVisual.paint(self)
		if selected_kind >= 0:
			draw_set_transform(_origin(), 0, Vector2.ONE * zoom)
			var selection := Rect2(selected_position() + _selection_offset() - selected_size() * 0.5, selected_size()).grow(7)
			draw_rect(selection, Color("efa05a"), false, 3.0 / zoom)
	draw_set_transform(Vector2.ZERO)
