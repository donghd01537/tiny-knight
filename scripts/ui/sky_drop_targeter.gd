extends Control
## Sky Drop targeting overlay.
## Full-screen transparent Control inside the CanvasLayer.
## Shows a range ring around the caster and a crosshair at the chosen landing spot.
## mouse_filter must be IGNORE so it never blocks touch events.

const RANGE_FILL   := Color(1.0, 0.85, 0.2, 0.07)
const RANGE_BORDER := Color(1.0, 0.85, 0.2, 0.70)
const TARGET_FILL  := Color(1.0, 0.85, 0.2, 0.50)
const TARGET_RING  := Color(1.0, 1.0,  1.0, 0.85)
const TARGET_RADIUS := 16.0

var _owner_pos := Vector2.ZERO
var _target_pos := Vector2.ZERO
var _range := 230.0


func show_at(owner_pos: Vector2, target_pos: Vector2, range: float) -> void:
	_owner_pos = owner_pos
	_target_pos = target_pos
	_range = range
	visible = true
	queue_redraw()


func update_positions(owner_pos: Vector2, target_pos: Vector2) -> void:
	_owner_pos = owner_pos
	_target_pos = target_pos
	queue_redraw()


func _draw() -> void:
	# Soft filled range area
	draw_circle(_owner_pos, _range, RANGE_FILL)
	# Range boundary ring
	draw_arc(_owner_pos, _range, 0.0, TAU, 80, RANGE_BORDER, 2.5)
	# Landing spot
	draw_circle(_target_pos, TARGET_RADIUS, TARGET_FILL)
	draw_arc(_target_pos, TARGET_RADIUS + 2.0, 0.0, TAU, 40, TARGET_RING, 2.0)
	# Crosshair
	var s := TARGET_RADIUS * 0.55
	draw_line(_target_pos + Vector2(-s, 0), _target_pos + Vector2(s, 0), TARGET_RING, 1.5)
	draw_line(_target_pos + Vector2(0, -s), _target_pos + Vector2(0, s), TARGET_RING, 1.5)
