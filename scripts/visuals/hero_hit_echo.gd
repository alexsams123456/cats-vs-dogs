class_name HeroHitEcho
extends Node2D
## A short, collision-free curtain call with a pop, soft clouds and falling stars.

const LIFETIME: float = 1.1
const CREAM := Color("fff3d5")
const PEACH := Color("efba91")
const GOLD := Color("ffc96b")
const AMBER := Color("bd784e")

var definition: CharacterDefinition
var visual_time: float = 0.0
var phase: float = 0.0
var initial_rotation: float = 0.0
var drift_velocity: Vector2 = Vector2.ZERO
var elapsed: float = 0.0


func _process(delta: float) -> void:
	elapsed += delta
	visual_time += delta
	if elapsed >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var drift: Vector2 = drift_velocity.limit_length(180.0) * minf(elapsed, 0.32) * 0.35
	_draw_flash(drift)
	_draw_clouds(drift, false)
	_draw_hero(drift)
	_draw_clouds(drift, true)
	_draw_stars(drift)


func _draw_flash(drift: Vector2) -> void:
	var progress: float = clampf(elapsed / 0.25, 0.0, 1.0)
	if progress >= 1.0:
		return
	var fade: float = (1.0 - progress) * (1.0 - progress)
	var center: Vector2 = drift + Vector2(0, -3.0 - progress * 8.0)
	HeroVisual._ellipse(self, center, Vector2(32, 25) * (0.65 + progress * 1.6), Color(GOLD, fade * 0.24))
	HeroVisual._ellipse(self, center, Vector2(23, 19) * (0.8 + progress), Color(CREAM, fade * 0.46))
	for index in 7:
		var angle: float = -PI + float(index) * TAU / 7.0 + phase * 0.13
		var ray := Vector2.from_angle(angle)
		draw_line(center + ray * (27.0 + progress * 17.0), center + ray * (32.0 + progress * 24.0), Color(CREAM, fade), 2.1 * (1.0 - progress * 0.6), true)


func _draw_hero(drift: Vector2) -> void:
	if elapsed >= 0.46:
		return
	var fur := definition.fur_color if definition != null else Color("e9dfc3")
	var accent := definition.accent_color if definition != null else Color("95715a")
	var kind: StringName = definition.id if definition != null else &"scout"
	var pop: float = smoothstep(0.045, 0.22, elapsed)
	var vanish: float = smoothstep(0.31, 0.46, elapsed)
	var squash: float = sin(clampf(elapsed / 0.095, 0.0, 1.0) * PI)
	var stretch: float = sin(clampf((elapsed - 0.065) / 0.19, 0.0, 1.0) * PI)
	var size := Vector2(1.0 + squash * 0.22 - stretch * 0.1, 1.0 - squash * 0.19 + stretch * 0.15)
	size *= 1.0 - vanish * 0.65
	var tilt: float = (0.26 + sin(phase) * 0.13) * pop
	var center: Vector2 = drift + Vector2(sin(pop * PI) * 3.0, -26.0 * pop + vanish * 7.0)
	draw_set_transform(center, initial_rotation + tilt, size)
	HeroVisual.paint(self, &"dog", kind, fur, accent, visual_time, phase, &"defeated", false)
	draw_set_transform(Vector2.ZERO)


func _draw_clouds(drift: Vector2, foreground: bool) -> void:
	var progress: float = clampf((elapsed - 0.19) / 0.91, 0.0, 1.0)
	if progress <= 0.0 or progress >= 1.0:
		return
	var unfurl: float = 1.0 - pow(1.0 - progress, 3.0)
	var fade: float = 1.0 - smoothstep(0.38, 1.0, progress)
	var growth: float = smoothstep(0.0, 0.2, progress)
	# Subpixel puffs can collapse into degenerate polygons at high frame rates.
	if growth < 0.03:
		return
	var count: int = 5 if foreground else 7
	for index in count:
		var part: float = float(index) / float(count)
		var angle: float = part * TAU + (0.25 if foreground else -0.45) + sin(phase) * 0.16
		var direction := Vector2.from_angle(angle)
		var spread: float = (12.0 + unfurl * 24.0) if foreground else (17.0 + unfurl * 30.0)
		var center: Vector2 = drift + Vector2(0, -21.0 - progress * 17.0) + direction * Vector2(spread, spread * 0.67)
		center.x += sin(part * 13.0 + progress * 3.0) * progress * 5.0
		var radius: float = (13.5 + sin(part * 17.0 + 0.8) * 2.8) * growth * (1.0 - progress * 0.42)
		var opacity: float = fade * (0.94 if foreground else 0.76)
		var shade: Color = PEACH.lerp(CREAM, 0.37 + part * 0.24)
		HeroVisual._ellipse(self, center + Vector2(0, 2.0), Vector2(radius * 1.07, radius * 0.79), Color(PEACH, opacity * 0.75))
		HeroVisual._ellipse(self, center, Vector2(radius, radius * 0.8), Color(shade, opacity))
		HeroVisual._ellipse(self, center + Vector2(-radius * 0.25, -radius * 0.27), Vector2(radius * 0.65, radius * 0.43), Color(CREAM, opacity * 0.78))
	if foreground:
		var core: float = growth * (1.0 - smoothstep(0.17, 0.64, progress))
		HeroVisual._ellipse(self, drift + Vector2(0, -23), Vector2(20, 17) * growth, Color(CREAM, core))


func _draw_stars(drift: Vector2) -> void:
	for index in 7:
		var delay: float = 0.065 + float(index % 3) * 0.034
		var progress: float = clampf((elapsed - delay) / (LIFETIME - delay), 0.0, 1.0)
		if progress <= 0.0 or progress >= 1.0:
			continue
		var angle: float = -2.9 + float(index) * 0.44 + sin(phase + float(index)) * 0.085
		var direction := Vector2.from_angle(angle)
		var distance: float = 27.0 + (1.0 - pow(1.0 - progress, 2.0)) * (25.0 + float(index % 3) * 5.0)
		var center: Vector2 = drift + Vector2(0, -9) + direction * distance + Vector2(0, 39.0 * progress * progress)
		var fade: float = smoothstep(0.0, 0.09, progress) * (1.0 - smoothstep(0.42, 1.0, progress))
		var radius: float = (4.4 + float(index % 3) * 0.85) * (1.0 - progress * 0.43)
		var spin: float = float(index) * 0.6 + progress * (2.3 if index % 2 == 0 else -2.0)
		_draw_star_trail(center, direction, progress, fade)
		_star(center + Vector2(0, 0.9), radius + 0.7, spin, Color(AMBER, fade * 0.65))
		_star(center, radius, spin, Color(GOLD.lerp(CREAM, float(index % 2) * 0.38), fade))
		draw_circle(center + Vector2(-0.8, -1.1), maxf(radius * 0.2, 0.5), Color(CREAM, fade * 0.95))
		var spark: Vector2 = center - direction * (9.0 + progress * 3.0) + Vector2(0, 7.0)
		HeroVisual._star(self, spark, 1.9 * (1.0 - progress * 0.6), -spin, Color(CREAM, fade * 0.85))


func _draw_star_trail(center: Vector2, direction: Vector2, progress: float, fade: float) -> void:
	if progress > 0.66:
		return
	var points := PackedVector2Array()
	for index in 6:
		var part: float = float(index) / 5.0
		points.append(center - direction * part * 12.0 + Vector2(0, -part * progress * 9.0 + sin(part * PI) * 2.2))
	draw_polyline(points, Color(CREAM, fade * (1.0 - progress / 0.66) * 0.6), 1.25, true)


func _star(center: Vector2, radius: float, spin: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 10:
		var angle: float = -PI * 0.5 + float(index) * TAU / 10.0 + spin
		points.append(center + Vector2.from_angle(angle) * radius * (1.0 if index % 2 == 0 else 0.47))
	draw_colored_polygon(points, color)
