extends Node2D
## Spawns battle field decorations: animated gargoyles at corners and bone piles along edges.

const GARGOYLE_TEXTURE = preload("res://assets/backgrounds/decor/fiery_gargoyle.png")
const BONES_TEXTURE = preload("res://assets/backgrounds/decor/bones.png")

# Gargoyle: 432x108 strip → 4 frames of 108x108
const GARGOYLE_FRAME_W := 108
const GARGOYLE_FRAME_H := 108
const GARGOYLE_FRAMES := 4
const GARGOYLE_SCALE := 1.5

# Bones: 192x160 grid → 6 cols × 5 rows of 32x32
const BONES_FRAME_W := 32
const BONES_FRAME_H := 32
const BONES_COLS := 6
const BONES_ROWS := 5
const BONES_TOTAL := 30
const BONES_BASE_SCALE := 1.0

# Battle field inner boundaries (wall inner edges)
const FIELD_LEFT   := 90.0
const FIELD_RIGHT  := 630.0
const FIELD_TOP    := 190.0
const FIELD_BOTTOM := 1140.0

# Gargoyle corner centers: exactly at field corners, no padding
var _corner_positions := [
	Vector2(FIELD_LEFT  + 40, FIELD_TOP),     # top-left
	Vector2(FIELD_RIGHT - 40, FIELD_TOP),     # top-right
	Vector2(FIELD_LEFT  + 10, FIELD_BOTTOM),  # bottom-left
	Vector2(FIELD_RIGHT - 10, FIELD_BOTTOM),  # bottom-right
]

var _gargoyles: Array[Sprite2D] = []
var _gargoyle_frames: Array[int] = []
var _gargoyle_fps: Array[float] = []
var _gargoyle_timers: Array[float] = []


func _ready() -> void:
	_spawn_gargoyles()
	_spawn_bones()


func _spawn_gargoyles() -> void:
	for i in range(2):  ## top-left + top-right only; bottom corners are used by the HUD
		var spr := Sprite2D.new()
		spr.texture = GARGOYLE_TEXTURE
		spr.region_enabled = true
		var frame := randi() % GARGOYLE_FRAMES
		spr.region_rect = Rect2(frame * GARGOYLE_FRAME_W, 0, GARGOYLE_FRAME_W, GARGOYLE_FRAME_H)
		spr.position = _corner_positions[i]
		spr.scale = Vector2(GARGOYLE_SCALE, GARGOYLE_SCALE)
		add_child(spr)
		_gargoyles.append(spr)
		_gargoyle_frames.append(frame)
		_gargoyle_fps.append(randf_range(6.0, 10.0))
		_gargoyle_timers.append(0.0)


func _spawn_bones() -> void:
	var count := randi_range(10, 15)
	var candidates := _build_bone_candidates()
	candidates.shuffle()

	var used_frames: Array[int] = []
	var spawned := 0

	for pos in candidates:
		if spawned >= count:
			break
		var frame_idx := _pick_unused_frame(used_frames)
		if frame_idx < 0:
			break
		used_frames.append(frame_idx)

		var col := frame_idx % BONES_COLS
		var row := frame_idx / BONES_COLS

		var spr := Sprite2D.new()
		spr.texture = BONES_TEXTURE
		spr.region_enabled = true
		spr.region_rect = Rect2(col * BONES_FRAME_W, row * BONES_FRAME_H, BONES_FRAME_W, BONES_FRAME_H)
		spr.position = pos
		var s := BONES_BASE_SCALE * randf_range(1.0, 1.5)
		spr.scale = Vector2(s, s)
		add_child(spr)
		spawned += 1


func _build_bone_candidates() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	const CORNER_AVOID := 90.0  # keep clear of gargoyle corners

	# Left edge (6 slots)
	for y_step in [300, 450, 600, 750, 900, 1080]:
		var p := Vector2(randf_range(FIELD_LEFT + 10, FIELD_LEFT + 55),
				float(y_step) + randf_range(-25, 25))
		if _away_from_corners(p, CORNER_AVOID):
			positions.append(p)

	# Right edge (6 slots)
	for y_step in [300, 450, 600, 750, 900, 1080]:
		var p := Vector2(randf_range(FIELD_RIGHT - 55, FIELD_RIGHT - 10),
				float(y_step) + randf_range(-25, 25))
		if _away_from_corners(p, CORNER_AVOID):
			positions.append(p)

	# Top edge (4 slots)
	for x_step in [210, 300, 420, 510]:
		var p := Vector2(float(x_step) + randf_range(-25, 25),
				randf_range(FIELD_TOP + 10, FIELD_TOP + 50))
		if _away_from_corners(p, CORNER_AVOID):
			positions.append(p)

	# Bottom edge (4 slots)
	for x_step in [210, 300, 420, 510]:
		var p := Vector2(float(x_step) + randf_range(-25, 25),
				randf_range(FIELD_BOTTOM - 50, FIELD_BOTTOM - 10))
		if _away_from_corners(p, CORNER_AVOID):
			positions.append(p)

	# Center (fewer slots → lower probability)
	for _i in range(6):
		positions.append(Vector2(
			randf_range(FIELD_LEFT + 80, FIELD_RIGHT - 80),
			randf_range(FIELD_TOP + 120, FIELD_BOTTOM - 120)
		))

	return positions


func _away_from_corners(pos: Vector2, radius: float) -> bool:
	for cp in _corner_positions:
		if pos.distance_to(cp) < radius:
			return false
	return true


func _pick_unused_frame(used: Array[int]) -> int:
	var available: Array[int] = []
	for i in range(BONES_TOTAL):
		if i not in used:
			available.append(i)
	if available.is_empty():
		return -1
	return available[randi() % available.size()]


func _process(delta: float) -> void:
	for i in range(_gargoyles.size()):
		_gargoyle_timers[i] += delta
		if _gargoyle_timers[i] >= 1.0 / _gargoyle_fps[i]:
			_gargoyle_timers[i] -= 1.0 / _gargoyle_fps[i]
			_gargoyle_frames[i] = (_gargoyle_frames[i] + 1) % GARGOYLE_FRAMES
			_gargoyles[i].region_rect = Rect2(
				_gargoyle_frames[i] * GARGOYLE_FRAME_W, 0,
				GARGOYLE_FRAME_W, GARGOYLE_FRAME_H
			)
