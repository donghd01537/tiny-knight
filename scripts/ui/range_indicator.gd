class_name RangeIndicator
extends Node2D
## Draws a fading ring showing a skill's cast range.
## Usage: RangeIndicator.show_at(parent_node, world_position, radius)

const LIFETIME := 1.2

var _radius: float = 100.0
var _timer: float = 0.0


## Spawns a ring at `pos` with the given `radius` as a child of `parent`.
static func show_at(parent: Node, pos: Vector2, radius: float) -> void:
	var r := RangeIndicator.new()
	r._radius = radius
	parent.add_child(r)
	r.global_position = pos


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var alpha := 1.0 - (_timer / LIFETIME)
	var col := Color(1.0, 0.85, 0.2, alpha * 0.8)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, col, 3.0)
