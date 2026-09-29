extends RefCounted
## Реальное движение до текущего тика, независимо от порядка callbacks тел.

var _tick: int = -1
var _linear := Vector2.ZERO
var _angular: float = 0.0
var _previous_linear := Vector2.ZERO
var _previous_angular: float = 0.0


func seed(velocity: Vector2, spin: float) -> void:
	_linear = velocity
	_angular = spin
	_previous_linear = velocity
	_previous_angular = spin
	_tick = -1


func capture(state: PhysicsDirectBodyState2D) -> void:
	var tick := Engine.get_physics_frames()
	if _tick != tick:
		_previous_linear = _linear
		_previous_angular = _angular
		_tick = tick
	_linear = state.linear_velocity
	_angular = state.angular_velocity


func velocity_before_step(offset: Vector2) -> Vector2:
	if _tick == Engine.get_physics_frames():
		return _previous_linear + offset.orthogonal() * _previous_angular
	return _linear + offset.orthogonal() * _angular
