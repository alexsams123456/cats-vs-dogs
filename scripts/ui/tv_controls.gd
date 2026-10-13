class_name TVControls
extends Node
## Отдельный режим пульта, включённый только TV-пресетом или аргументом --tv.

var angle: float = 35.0
var power: float = 1.0
var _app: GameApp
var _preview_cat: CatProjectile
var _focus_scope: Node


static func is_enabled() -> bool:
	return OS.has_feature("android_tv") or "--tv" in OS.get_cmdline_user_args()


func _ready() -> void:
	_app = get_parent() as GameApp
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _app._transition_pending:
		return
	var game := _app.game
	if is_instance_valid(game) and not get_tree().paused and game.state in [GameRound.RoundState.READY, GameRound.RoundState.FLYING]:
		var owner := get_viewport().gui_get_focus_owner()
		if owner != null:
			owner.release_focus()
		_focus_scope = null
		if game.state == GameRound.RoundState.READY:
			if game.slingshot.loaded_projectile != _preview_cat or not game.slingshot.is_dragging:
				_update_aim(game)
		return
	var scope: Node = _app.campaign if is_instance_valid(_app.campaign) else _app.menu
	if is_instance_valid(game):
		if not game.hud._overlay.visible:
			return
		scope = game.hud._overlay
	if not is_instance_valid(scope):
		return
	var controls := scope.find_children("*", "Control", true, false)
	var first: Control
	for node: Node in controls:
		var control := node as Control
		if not control.is_visible_in_tree() or control.focus_mode != Control.FOCUS_ALL:
			continue
		if control is BaseButton and control.disabled:
			continue
		if first == null:
			first = control
		if control is BaseButton and not control.has_meta(&"tv_focus"):
			var style := StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("ffb32f")
			style.set_border_width_all(5)
			style.set_corner_radius_all(15)
			control.add_theme_stylebox_override("focus", style)
			control.add_theme_color_override("font_focus_color", control.get_theme_color("font_color"))
			control.set_meta(&"tv_focus", true)
	var owner := get_viewport().gui_get_focus_owner()
	var outside_overlay := is_instance_valid(game) and owner != null and owner.get_viewport() == get_viewport() and not scope.is_ancestor_of(owner)
	if first != null and (scope != _focus_scope or owner == null or not owner.is_visible_in_tree() or outside_overlay):
		if is_instance_valid(game) and get_tree().paused:
			game.hud._resume_button.grab_focus()
		elif owner == null or not scope.is_ancestor_of(owner):
			first.grab_focus()
	_focus_scope = scope


func _input(event: InputEvent) -> void:
	if _app._transition_pending or not event is InputEventKey:
		return
	var game := _app.game
	var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
	if key in [KEY_ESCAPE, KEY_BACK]:
		if event.pressed and not event.echo:
			_app._go_back()
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(game):
		return
	if get_tree().paused or game.state not in [GameRound.RoundState.READY, GameRound.RoundState.FLYING]:
		return
	if key not in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER]:
		return
	# Поглощаем и отпускание OK: оно не должно попасть в кнопку HUD.
	get_viewport().set_input_as_handled()
	if not event.pressed:
		return
	if key in [KEY_ENTER, KEY_KP_ENTER]:
		if event.echo:
			return
		if game.state == GameRound.RoundState.READY:
			game.slingshot.launch_from_pull(_aim_pull(game.slingshot))
		else:
			game.use_ability()
	elif game.state == GameRound.RoundState.READY:
		match key:
			KEY_UP: angle = minf(angle + 2.0, 80.0)
			KEY_DOWN: angle = maxf(angle - 2.0, 5.0)
			KEY_LEFT: power = maxf(power - 0.05, 0.25)
			KEY_RIGHT: power = minf(power + 0.05, 1.0)
		_update_aim(game)


func _aim_pull(slingshot: Slingshot) -> Vector2:
	return Vector2(-cos(deg_to_rad(angle)), sin(deg_to_rad(angle))) * slingshot.max_pull * power


func _update_aim(game: GameRound) -> void:
	_preview_cat = game.slingshot.loaded_projectile
	game.slingshot.preview_remote_pull(_aim_pull(game.slingshot))
	game.hud.set_tv_aim(angle, power)
