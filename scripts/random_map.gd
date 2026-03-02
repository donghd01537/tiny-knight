extends Node2D

const TILE_SIZE: int = 32
const SIDE_TOP: int = 0
const SIDE_BOTTOM: int = 1
const SIDE_LEFT: int = 2
const SIDE_RIGHT: int = 3
const MIN_WALL_FRAMES: int = 3

@export var min_map_width: int = 112
@export var max_map_width: int = 220
@export var min_map_height: int = 84
@export var max_map_height: int = 170

@export var min_room_count: int = 5
@export var max_room_count: int = 7
@export var min_room_width: int = 12
@export var max_room_width: int = 24
@export var min_room_height: int = 12
@export var max_room_height: int = 24
@export_range(0.5, 3.0, 0.1) var room_size_scale: float = 1.5
@export var room_spacing_tiles: int = 4
@export var corridor_width_tiles: int = 4
@export var min_floor_block_tiles: int = 4
@export var min_connection_segment_tiles: int = 6
@export var min_wall_run_tiles: int = 7
@export var min_wall_images: int = 5
@export var preferred_wall_run_tiles: int = 8
@export var excluded_vertical_floor_heights: PackedInt32Array = PackedInt32Array([4, 11])

@export var map_origin_tiles: Vector2i = Vector2i(6, 6)
@export var floor_detail_chance: float = 0.35
@export var corridor_detail_chance: float = 0.12
@export var random_seed: int = 0
@export var camera_zoom_scale: float = 1.0
@export var wall_overlap_px: float = 0.0
@export var side_wall_inset_px: float = 0.0
@export var side_wall_outward_nudge_px: float = 0.0
@export_range(0.0, 0.5, 0.01) var side_wall_top_overlap_ratio: float = 0.0
@export var side_wall_extra_lift_px: float = 8.0
@export var side_wall_trim_frames: int = 0
@export var use_corner_decor: bool = true

var _floor_texture: Texture2D
var _wall_top_texture: Texture2D
var _wall_bottom_texture: Texture2D
var _wall_vertical_texture: Texture2D
var _wall_top_corner_texture: Texture2D
var _wall_inner_bottom_corner_texture: Texture2D
var _wall_outer_bottom_corner_texture: Texture2D
var _wall_inner_top_corner_texture: Texture2D

var _camera: Camera2D
var _map_size_tiles: Vector2i = Vector2i.ZERO
var _floor_frame_count: int = 1
var _floor_cells: Dictionary = {} # Vector2i -> frame index
var _rooms: Array[Rect2i] = []

# Public fields used by minimap.gd (same contract as scripts/map.gd)
var floor_rects: Array[Rect2i] = []
var world_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("map")

	if random_seed != 0:
		seed(random_seed)
	else:
		randomize()

	_floor_texture = load("res://assets/maps/floors/floors.png")
	_wall_top_texture = load("res://assets/maps/walls/top.png")
	_wall_bottom_texture = load("res://assets/maps/walls/bottom.png")
	_wall_vertical_texture = load("res://assets/maps/walls/vertical.png")
	_wall_top_corner_texture = load("res://assets/maps/walls/outer-top-corner.png")
	_wall_inner_bottom_corner_texture = load("res://assets/maps/walls/inner-top-corner.png")
	_wall_outer_bottom_corner_texture = load("res://assets/maps/walls/outer-bottom-corner.png")
	_wall_inner_top_corner_texture = load("res://assets/maps/walls/inner-bottom-corner.png")
	_camera = get_node_or_null("Camera2D")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	if not _validate_required_resources():
		return

	_floor_frame_count = max(1, int(_floor_texture.get_width() / TILE_SIZE))
	_generate_random_map()
	_log_floor_frame_usage()
	_rebuild_public_map_data()
	_place_breaker()
	_center_camera()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_generate_random_map()
		_log_floor_frame_usage()
		_rebuild_public_map_data()
		_place_breaker()
		_center_camera()
		queue_redraw()


func _generate_random_map() -> void:
	var min_h_wall_tiles: int = _min_horizontal_wall_run_tiles()
	var min_v_wall_tiles: int = _min_vertical_wall_run_tiles()
	_build_fast_multi_room_map(min_h_wall_tiles, min_v_wall_tiles)
	print("random_map generation: mode=multi_room_fast rooms=%d size=%dx%d floor_tiles=%d" % [_rooms.size(), _map_size_tiles.x, _map_size_tiles.y, _floor_cells.size()])


func _generate_multi_room_dungeon_map(min_block: int, min_h_wall_tiles: int, min_v_wall_tiles: int) -> bool:
	_build_fast_multi_room_map(min_h_wall_tiles, min_v_wall_tiles)
	return _rooms.size() >= 2 and not _floor_cells.is_empty()


func _build_fast_multi_room_map(min_h_wall_tiles: int, min_v_wall_tiles: int) -> void:
	_floor_cells.clear()
	_rooms.clear()

	var min_target_rooms: int = max(2, min(min_room_count, max_room_count))
	var max_target_rooms: int = max(min_target_rooms, max(min_room_count, max_room_count))
	var target_rooms: int = randi_range(min_target_rooms, max_target_rooms)

	var room_w_min_cfg: int = max(4, min(min_room_width, max_room_width))
	var room_w_max_cfg: int = max(room_w_min_cfg, max(min_room_width, max_room_width))
	var room_h_min_cfg: int = max(4, min(min_room_height, max_room_height))
	var room_h_max_cfg: int = max(room_h_min_cfg, max(min_room_height, max_room_height))
	var size_scale: float = max(0.5, room_size_scale)
	room_w_min_cfg = max(4, int(round(float(room_w_min_cfg) * size_scale)))
	room_w_max_cfg = max(room_w_min_cfg, int(round(float(room_w_max_cfg) * size_scale)))
	room_h_min_cfg = max(4, int(round(float(room_h_min_cfg) * size_scale)))
	room_h_max_cfg = max(room_h_min_cfg, int(round(float(room_h_max_cfg) * size_scale)))
	var room_w_min: int = max(room_w_min_cfg, min_h_wall_tiles * 2 + 2)
	var room_h_min: int = max(room_h_min_cfg, min_v_wall_tiles * 2 + 2)
	var room_w_max: int = max(room_w_min, room_w_max_cfg)
	var room_h_max: int = max(room_h_min, room_h_max_cfg)

	var map_min_w_cfg: int = max(48, min(min_map_width, max_map_width))
	var map_max_w_cfg: int = max(map_min_w_cfg, max(min_map_width, max_map_width))
	var map_min_h_cfg: int = max(40, min(min_map_height, max_map_height))
	var map_max_h_cfg: int = max(map_min_h_cfg, max(min_map_height, max_map_height))
	var gap: int = max(min_connection_segment_tiles + 4, room_spacing_tiles + 6)
	var avg_room_w: int = int(round((room_w_min + room_w_max) * 0.5))
	var avg_room_h: int = int(round((room_h_min + room_h_max) * 0.5))
	var approx_cols: int = max(1, int(ceili(sqrt(float(target_rooms)))))
	var approx_rows: int = max(1, int(ceili(float(target_rooms) / float(approx_cols))))
	var estimated_w: int = approx_cols * (avg_room_w + gap) + gap + 16
	var estimated_h: int = approx_rows * (avg_room_h + gap) + gap + 16
	var map_w: int = clampi(estimated_w, map_min_w_cfg, map_max_w_cfg)
	var map_h: int = clampi(estimated_h, map_min_h_cfg, map_max_h_cfg)
	_map_size_tiles = Vector2i(map_w, map_h)

	var dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

	var first_w: int = randi_range(room_w_min, room_w_max)
	var first_h: int = randi_range(room_h_min, room_h_max)
	var first_x: int = clampi(int(_map_size_tiles.x * 0.5) - int(first_w * 0.5), 1, _map_size_tiles.x - first_w - 1)
	var first_y: int = clampi(int(_map_size_tiles.y * 0.5) - int(first_h * 0.5), 1, _map_size_tiles.y - first_h - 1)
	_rooms.append(Rect2i(first_x, first_y, first_w, first_h))

	var placement_tries: int = target_rooms * 120
	while _rooms.size() < target_rooms and placement_tries > 0:
		placement_tries -= 1

		var parent: Rect2i = _rooms[_rooms.size() - 1]
		var parent_center: Vector2i = _room_center(parent)
		var room_w: int = randi_range(room_w_min, room_w_max)
		var room_h: int = randi_range(room_h_min, room_h_max)
		var dir: Vector2i = dirs[randi_range(0, dirs.size() - 1)]
		var step_x: int = int((parent.size.x + room_w) * 0.5) + gap
		var step_y: int = int((parent.size.y + room_h) * 0.5) + gap
		var candidate_center: Vector2i = parent_center + Vector2i(dir.x * step_x, dir.y * step_y)
		var room_x: int = clampi(candidate_center.x - int(room_w * 0.5), 1, _map_size_tiles.x - room_w - 1)
		var room_y: int = clampi(candidate_center.y - int(room_h * 0.5), 1, _map_size_tiles.y - room_h - 1)
		var candidate: Rect2i = Rect2i(room_x, room_y, room_w, room_h)

		var overlaps: bool = false
		for existing: Rect2i in _rooms:
			if candidate.grow(max(1, room_spacing_tiles)).intersects(existing.grow(max(1, room_spacing_tiles))):
				overlaps = true
				break
		if overlaps:
			continue

		_rooms.append(candidate)

	# Guarantee minimum room count with compact rescue around existing rooms.
	if _rooms.size() < min_target_rooms:
		var rescue_gap: int = max(1, room_spacing_tiles - 2)
		var rescue_tries: int = min_target_rooms * 180
		while _rooms.size() < min_target_rooms and rescue_tries > 0:
			rescue_tries -= 1
			var parent: Rect2i = _rooms[randi_range(0, _rooms.size() - 1)]
			var parent_center: Vector2i = _room_center(parent)
			var rw: int = randi_range(room_w_min, min(room_w_max, room_w_min + 3))
			var rh: int = randi_range(room_h_min, min(room_h_max, room_h_min + 3))
			var dir: Vector2i = dirs[randi_range(0, dirs.size() - 1)]
			var step_x: int = int((parent.size.x + rw) * 0.5) + gap
			var step_y: int = int((parent.size.y + rh) * 0.5) + gap
			var center: Vector2i = parent_center + Vector2i(dir.x * step_x, dir.y * step_y)
			var rx: int = clampi(center.x - int(rw * 0.5), 1, _map_size_tiles.x - rw - 1)
			var ry: int = clampi(center.y - int(rh * 0.5), 1, _map_size_tiles.y - rh - 1)
			var candidate: Rect2i = Rect2i(rx, ry, rw, rh)
			var overlaps: bool = false
			for existing: Rect2i in _rooms:
				if candidate.grow(rescue_gap).intersects(existing.grow(rescue_gap)):
					overlaps = true
					break
			if overlaps:
				continue
			_rooms.append(candidate)

	var mst_links: Array[Vector2i] = _build_room_mst_links()
	var blocked_sides_by_room: Dictionary = _collect_mst_blocked_sides(mst_links)

	for room_idx in range(_rooms.size()):
		var room: Rect2i = _rooms[room_idx]
		_paint_rect(room, floor_detail_chance)
		var blocked_sides: Dictionary = {}
		if blocked_sides_by_room.has(room_idx):
			blocked_sides = blocked_sides_by_room[room_idx]
		_paint_room_shape_bumps(room, min_h_wall_tiles, min_v_wall_tiles, blocked_sides)

	# Clean ways: connect room centers via MST (avoids door-stub artifacts).
	_carve_mst_center_links(mst_links)


func _paint_room_shape_bumps(base_room: Rect2i, min_h_wall_tiles: int, min_v_wall_tiles: int, blocked_sides: Dictionary = {}) -> void:
	var available_sides: Array[int] = []
	for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		if not blocked_sides.has(side):
			available_sides.append(side)

	if available_sides.is_empty():
		return

	available_sides.shuffle()
	var bump_attempts: int = min(randi_range(1, 3), available_sides.size())
	for side_idx in range(bump_attempts):
		var side: int = available_sides[side_idx]
		var depth: int = randi_range(2, 4)
		match side:
			SIDE_TOP:
				_paint_top_bump(base_room, min_h_wall_tiles, depth)
			SIDE_BOTTOM:
				_paint_bottom_bump(base_room, min_h_wall_tiles, depth)
			SIDE_LEFT:
				_paint_left_bump(base_room, min_v_wall_tiles, depth)
			_:
				_paint_right_bump(base_room, min_v_wall_tiles, depth)


func _log_floor_frame_usage() -> void:
	if _floor_cells.is_empty():
		print("random_map floor frame usage: no floor tiles")
		return

	var counts: Dictionary = {}
	for value in _floor_cells.values():
		var frame_idx: int = int(value)
		if not counts.has(frame_idx):
			counts[frame_idx] = 0
		counts[frame_idx] = int(counts[frame_idx]) + 1

	var frame_keys: Array = counts.keys()
	frame_keys.sort()
	var message: String = "random_map floor frame usage: total_tiles=%d" % _floor_cells.size()
	for key in frame_keys:
		var frame_idx: int = int(key)
		var tile_count: int = int(counts[frame_idx])
		message += " | f%d=%d" % [frame_idx, tile_count]
	print(message)


func _paint_rect(rect: Rect2i, detail_chance: float) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_paint_floor_cell(Vector2i(x, y), detail_chance)


func _paint_floor_cell(pos: Vector2i, detail_chance: float) -> void:
	var frame_index: int = 0
	if _floor_frame_count > 1 and randf() < detail_chance:
		frame_index = randi_range(1, _floor_frame_count - 1)

	if _floor_cells.has(pos):
		if frame_index > 0:
			_floor_cells[pos] = frame_index
		return

	_floor_cells[pos] = frame_index


func _generate_single_room_complex_map(min_block: int, min_h_wall_tiles: int, min_v_wall_tiles: int) -> bool:
	var map_min_w_cfg: int = max(48, min(min_map_width, max_map_width))
	var map_max_w_cfg: int = max(map_min_w_cfg, max(min_map_width, max_map_width))
	var map_min_h_cfg: int = max(40, min(min_map_height, max_map_height))
	var map_max_h_cfg: int = max(map_min_h_cfg, max(min_map_height, max_map_height))
	var outer_buffer: int = max(min_h_wall_tiles, min_v_wall_tiles) + 3
	var build_attempts: int = 280

	for _attempt_idx in range(build_attempts):
		_floor_cells.clear()
		_rooms.clear()

		var room_w_min: int = max(max(4, min(min_room_width, max_room_width)), min_h_wall_tiles * 2 + 2)
		var room_h_min: int = max(max(4, min(min_room_height, max_room_height)), min_v_wall_tiles * 2 + 2)
		var min_map_w_needed: int = room_w_min + outer_buffer * 2
		var min_map_h_needed: int = room_h_min + outer_buffer * 2

		var low_w: int = max(map_min_w_cfg, min_map_w_needed)
		var high_w: int = max(low_w, map_max_w_cfg)
		var low_h: int = max(map_min_h_cfg, min_map_h_needed)
		var high_h: int = max(low_h, map_max_h_cfg)
		if high_w == low_w:
			high_w += 8
		if high_h == low_h:
			high_h += 8
		_map_size_tiles = Vector2i(randi_range(low_w, high_w), randi_range(low_h, high_h))

		var max_room_w_available: int = _map_size_tiles.x - outer_buffer * 2
		var max_room_h_available: int = _map_size_tiles.y - outer_buffer * 2
		if max_room_w_available < room_w_min or max_room_h_available < room_h_min:
			continue

		var room_w_max_cfg: int = max(room_w_min + 4, max(min_room_width, max_room_width))
		var room_h_max_cfg: int = max(room_h_min + 4, max(min_room_height, max_room_height))
		var room_w_max: int = min(max_room_w_available, room_w_max_cfg)
		var room_h_max: int = min(max_room_h_available, room_h_max_cfg)
		var room_w: int = randi_range(room_w_min, max(room_w_min, room_w_max))
		var room_h: int = randi_range(room_h_min, max(room_h_min, room_h_max))

		var room_x_min: int = outer_buffer
		var room_x_max: int = _map_size_tiles.x - outer_buffer - room_w
		var room_y_min: int = outer_buffer
		var room_y_max: int = _map_size_tiles.y - outer_buffer - room_h
		if room_x_max < room_x_min or room_y_max < room_y_min:
			continue

		var room_x: int = randi_range(room_x_min, room_x_max)
		var room_y: int = randi_range(room_y_min, room_y_max)
		var base_room: Rect2i = Rect2i(room_x, room_y, room_w, room_h)
		_rooms.append(base_room)
		_paint_rect(base_room, floor_detail_chance)

		var feature_count: int = _add_complex_border_features(base_room, min_h_wall_tiles, min_v_wall_tiles)
		if randf() < 0.45:
			feature_count += _add_complex_border_features(base_room, min_h_wall_tiles, min_v_wall_tiles)
		_smooth_floor_shape(min_h_wall_tiles, min_v_wall_tiles)
		_force_expand_short_edges(min_h_wall_tiles, min_v_wall_tiles)
		if feature_count >= 3 and _edge_run_count() >= 8 and _is_map_valid(min_block, min_h_wall_tiles, min_v_wall_tiles):
			return true

	return false


func _build_single_room_fallback(min_block: int, min_h_wall_tiles: int, min_v_wall_tiles: int) -> void:
	_floor_cells.clear()
	_rooms.clear()

	var map_min_w_cfg: int = max(52, min(min_map_width, max_map_width))
	var map_min_h_cfg: int = max(44, min(min_map_height, max_map_height))
	var outer_buffer: int = max(min_h_wall_tiles, min_v_wall_tiles) + 3
	var room_w: int = min_h_wall_tiles * 3 + 6
	var room_h: int = min_v_wall_tiles * 3 + 6

	var map_w: int = max(map_min_w_cfg, room_w + outer_buffer * 2 + 6)
	var map_h: int = max(map_min_h_cfg, room_h + outer_buffer * 2 + 6)
	_map_size_tiles = Vector2i(map_w, map_h)

	var room_x_center: int = int((_map_size_tiles.x - room_w) / 2)
	var room_y_center: int = int((_map_size_tiles.y - room_h) / 2)
	var room_x: int = clampi(room_x_center + randi_range(-2, 2), outer_buffer, _map_size_tiles.x - outer_buffer - room_w)
	var room_y: int = clampi(room_y_center + randi_range(-2, 2), outer_buffer, _map_size_tiles.y - outer_buffer - room_h)
	var base_room: Rect2i = Rect2i(room_x, room_y, room_w, room_h)
	_rooms.append(base_room)
	_paint_rect(base_room, floor_detail_chance)

	var feature_count: int = _add_complex_border_features(base_room, min_h_wall_tiles, min_v_wall_tiles)
	if feature_count < 2:
		feature_count += _add_complex_border_features(base_room, min_h_wall_tiles, min_v_wall_tiles)
	_smooth_floor_shape(min_h_wall_tiles, min_v_wall_tiles)
	_force_expand_short_edges(min_h_wall_tiles, min_v_wall_tiles)
	if not _is_map_valid(min_block, min_h_wall_tiles, min_v_wall_tiles):
		_force_expand_short_edges(min_h_wall_tiles + 2, min_v_wall_tiles + 2)
		_smooth_floor_shape(min_h_wall_tiles, min_v_wall_tiles)


func _paint_cardinal_bumps(base_room: Rect2i, min_h_wall_tiles: int, min_v_wall_tiles: int, top_depth: int, bottom_depth: int, left_depth: int, right_depth: int) -> int:
	var features: int = 0
	if _paint_top_bump(base_room, min_h_wall_tiles, top_depth):
		features += 1
	if _paint_bottom_bump(base_room, min_h_wall_tiles, bottom_depth):
		features += 1
	if _paint_left_bump(base_room, min_v_wall_tiles, left_depth):
		features += 1
	if _paint_right_bump(base_room, min_v_wall_tiles, right_depth):
		features += 1
	return features


func _paint_top_bump(base_room: Rect2i, min_h_wall_tiles: int, depth: int) -> bool:
	var max_w: int = base_room.size.x - 2 * min_h_wall_tiles
	if max_w < min_h_wall_tiles:
		return false
	var width_cap: int = min(max_w, min_h_wall_tiles * 2 + 6)
	var bump_w: int = randi_range(min_h_wall_tiles, max(min_h_wall_tiles, width_cap))
	var x_min: int = base_room.position.x + min_h_wall_tiles
	var x_max: int = base_room.position.x + base_room.size.x - min_h_wall_tiles - bump_w
	if x_max < x_min:
		return false
	var bump_x: int = randi_range(x_min, x_max)
	var bump_y: int = base_room.position.y - depth
	if bump_y < 0:
		return false
	_paint_rect(Rect2i(bump_x, bump_y, bump_w, depth), corridor_detail_chance)
	return true


func _paint_bottom_bump(base_room: Rect2i, min_h_wall_tiles: int, depth: int) -> bool:
	var max_w: int = base_room.size.x - 2 * min_h_wall_tiles
	if max_w < min_h_wall_tiles:
		return false
	var width_cap: int = min(max_w, min_h_wall_tiles * 2 + 6)
	var bump_w: int = randi_range(min_h_wall_tiles, max(min_h_wall_tiles, width_cap))
	var x_min: int = base_room.position.x + min_h_wall_tiles
	var x_max: int = base_room.position.x + base_room.size.x - min_h_wall_tiles - bump_w
	if x_max < x_min:
		return false
	var bump_x: int = randi_range(x_min, x_max)
	var bump_y: int = base_room.position.y + base_room.size.y
	if bump_y + depth >= _map_size_tiles.y:
		return false
	_paint_rect(Rect2i(bump_x, bump_y, bump_w, depth), corridor_detail_chance)
	return true


func _paint_left_bump(base_room: Rect2i, min_v_wall_tiles: int, depth: int) -> bool:
	var max_h: int = base_room.size.y - 2 * min_v_wall_tiles
	if max_h < min_v_wall_tiles:
		return false
	var height_cap: int = min(max_h, min_v_wall_tiles * 2 + 6)
	var bump_h: int = randi_range(min_v_wall_tiles, max(min_v_wall_tiles, height_cap))
	var y_min: int = base_room.position.y + min_v_wall_tiles
	var y_max: int = base_room.position.y + base_room.size.y - min_v_wall_tiles - bump_h
	if y_max < y_min:
		return false
	var bump_y: int = randi_range(y_min, y_max)
	var bump_x: int = base_room.position.x - depth
	if bump_x < 0:
		return false
	_paint_rect(Rect2i(bump_x, bump_y, depth, bump_h), corridor_detail_chance)
	return true


func _paint_right_bump(base_room: Rect2i, min_v_wall_tiles: int, depth: int) -> bool:
	var max_h: int = base_room.size.y - 2 * min_v_wall_tiles
	if max_h < min_v_wall_tiles:
		return false
	var height_cap: int = min(max_h, min_v_wall_tiles * 2 + 6)
	var bump_h: int = randi_range(min_v_wall_tiles, max(min_v_wall_tiles, height_cap))
	var y_min: int = base_room.position.y + min_v_wall_tiles
	var y_max: int = base_room.position.y + base_room.size.y - min_v_wall_tiles - bump_h
	if y_max < y_min:
		return false
	var bump_y: int = randi_range(y_min, y_max)
	var bump_x: int = base_room.position.x + base_room.size.x
	if bump_x + depth >= _map_size_tiles.x:
		return false
	_paint_rect(Rect2i(bump_x, bump_y, depth, bump_h), corridor_detail_chance)
	return true


func _add_complex_border_features(base_room: Rect2i, min_h_wall_tiles: int, min_v_wall_tiles: int) -> int:
	var top_count: int = randi_range(0, 3)
	var bottom_count: int = randi_range(0, 3)
	var left_count: int = randi_range(0, 3)
	var right_count: int = randi_range(0, 3)

	if top_count + bottom_count + left_count + right_count < 2:
		var forced_side: int = randi_range(0, 3)
		match forced_side:
			0:
				top_count += 2
			1:
				bottom_count += 2
			2:
				left_count += 2
			_:
				right_count += 2

	if randf() < 0.65:
		var dominant_side: int = randi_range(0, 3)
		match dominant_side:
			0:
				top_count += randi_range(1, 2)
			1:
				bottom_count += randi_range(1, 2)
			2:
				left_count += randi_range(1, 2)
			_:
				right_count += randi_range(1, 2)

	top_count = min(4, top_count)
	bottom_count = min(4, bottom_count)
	left_count = min(4, left_count)
	right_count = min(4, right_count)

	var features: int = 0
	if top_count > 0:
		features += _add_horizontal_border_bumps(base_room, true, min_h_wall_tiles, min_v_wall_tiles, top_count)
	if bottom_count > 0:
		features += _add_horizontal_border_bumps(base_room, false, min_h_wall_tiles, min_v_wall_tiles, bottom_count)
	if left_count > 0:
		features += _add_vertical_border_bumps(base_room, true, min_h_wall_tiles, min_v_wall_tiles, left_count)
	if right_count > 0:
		features += _add_vertical_border_bumps(base_room, false, min_h_wall_tiles, min_v_wall_tiles, right_count)
	return features


func _add_horizontal_border_bumps(base_room: Rect2i, is_top: bool, min_h_wall_tiles: int, min_v_wall_tiles: int, target_count: int) -> int:
	var side_min_x: int = base_room.position.x + min_h_wall_tiles
	var side_max_x: int = base_room.position.x + base_room.size.x - 1 - min_h_wall_tiles
	if side_max_x - side_min_x + 1 < min_h_wall_tiles * 2:
		return 0

	var depth_cap: int = 0
	if is_top:
		depth_cap = base_room.position.y - 1
	else:
		depth_cap = _map_size_tiles.y - (base_room.position.y + base_room.size.y) - 1
	var depth_min: int = min_v_wall_tiles
	var depth_max: int = min(depth_cap, max(min_v_wall_tiles + 2, int(base_room.size.y * 0.45)))
	if depth_max < depth_min:
		return 0

	var span: int = side_max_x - side_min_x + 1
	var width_min: int = max(min_h_wall_tiles, int(round(float(min_h_wall_tiles) * 1.4)))
	var width_max: int = min(span, max(width_min, int(base_room.size.x * 0.45)))
	if width_max < width_min:
		return 0

	var intervals: Array = []
	var placed: int = 0
	var tries: int = max(1, target_count) * 30
	while tries > 0 and placed < target_count:
		tries -= 1
		var bump_w: int = randi_range(width_min, width_max)
		var bump_x_min: int = side_min_x
		var bump_x_max: int = side_max_x - bump_w + 1
		if bump_x_max < bump_x_min:
			continue
		var bump_x: int = randi_range(bump_x_min, bump_x_max)
		var bump_x_end: int = bump_x + bump_w - 1
		if not _interval_is_clear(intervals, bump_x, bump_x_end, min_h_wall_tiles):
			continue

		var bump_depth: int = randi_range(depth_min, depth_max)
		var bump_y: int = base_room.position.y - bump_depth if is_top else base_room.position.y + base_room.size.y
		var bump_rect: Rect2i = Rect2i(bump_x, bump_y, bump_w, bump_depth)
		_paint_rect(bump_rect, corridor_detail_chance)
		intervals.append([bump_x, bump_x_end])
		placed += 1

	return placed


func _add_vertical_border_bumps(base_room: Rect2i, is_left: bool, min_h_wall_tiles: int, min_v_wall_tiles: int, target_count: int) -> int:
	var side_min_y: int = base_room.position.y + min_v_wall_tiles
	var side_max_y: int = base_room.position.y + base_room.size.y - 1 - min_v_wall_tiles
	if side_max_y - side_min_y + 1 < min_v_wall_tiles * 2:
		return 0

	var depth_cap: int = 0
	if is_left:
		depth_cap = base_room.position.x - 1
	else:
		depth_cap = _map_size_tiles.x - (base_room.position.x + base_room.size.x) - 1
	var depth_min: int = min_h_wall_tiles
	var depth_max: int = min(depth_cap, max(min_h_wall_tiles + 2, int(base_room.size.x * 0.45)))
	if depth_max < depth_min:
		return 0

	var span: int = side_max_y - side_min_y + 1
	var height_min: int = max(min_v_wall_tiles, int(round(float(min_v_wall_tiles) * 1.4)))
	var height_max: int = min(span, max(height_min, int(base_room.size.y * 0.45)))
	if height_max < height_min:
		return 0

	var intervals: Array = []
	var placed: int = 0
	var tries: int = max(1, target_count) * 30
	while tries > 0 and placed < target_count:
		tries -= 1
		var bump_h: int = randi_range(height_min, height_max)
		var bump_y_min: int = side_min_y
		var bump_y_max: int = side_max_y - bump_h + 1
		if bump_y_max < bump_y_min:
			continue
		var bump_y: int = randi_range(bump_y_min, bump_y_max)
		var bump_y_end: int = bump_y + bump_h - 1
		if not _interval_is_clear(intervals, bump_y, bump_y_end, min_v_wall_tiles):
			continue

		var bump_depth: int = randi_range(depth_min, depth_max)
		var bump_x: int = base_room.position.x - bump_depth if is_left else base_room.position.x + base_room.size.x
		var bump_rect: Rect2i = Rect2i(bump_x, bump_y, bump_depth, bump_h)
		_paint_rect(bump_rect, corridor_detail_chance)
		intervals.append([bump_y, bump_y_end])
		placed += 1

	return placed


func _interval_is_clear(intervals: Array, start_i: int, end_i: int, min_gap: int) -> bool:
	for interval in intervals:
		var s: int = int(interval[0])
		var e: int = int(interval[1])
		if start_i <= e + min_gap and end_i >= s - min_gap:
			return false
	return true


func _edge_run_count() -> int:
	var edges: Dictionary = _collect_exposed_wall_edges()
	var total_runs: int = 0

	var top_edges: Dictionary = edges["top"]
	for row_key in top_edges.keys():
		var xs: Array = top_edges[row_key]
		xs.sort()
		total_runs += _group_runs(xs).size()

	var bottom_edges: Dictionary = edges["bottom"]
	for row_key in bottom_edges.keys():
		var xs: Array = bottom_edges[row_key]
		xs.sort()
		total_runs += _group_runs(xs).size()

	var left_edges: Dictionary = edges["left"]
	for col_key in left_edges.keys():
		var ys: Array = left_edges[col_key]
		ys.sort()
		total_runs += _group_runs(ys).size()

	var right_edges: Dictionary = edges["right"]
	for col_key in right_edges.keys():
		var ys: Array = right_edges[col_key]
		ys.sort()
		total_runs += _group_runs(ys).size()

	return total_runs


func _connect_rooms_with_mst() -> void:
	if _rooms.size() < 2:
		return

	var in_tree: Array[bool] = []
	in_tree.resize(_rooms.size())
	in_tree.fill(false)
	in_tree[0] = true
	var in_count: int = 1

	while in_count < _rooms.size():
		var best_from: int = -1
		var best_to: int = -1
		var best_dist: int = 2147483647

		for i in range(_rooms.size()):
			if not in_tree[i]:
				continue
			var a: Vector2i = _room_center(_rooms[i])
			for j in range(_rooms.size()):
				if in_tree[j]:
					continue
				var b: Vector2i = _room_center(_rooms[j])
				var d: int = absi(a.x - b.x) + absi(a.y - b.y)
				if d < best_dist:
					best_dist = d
					best_from = i
					best_to = j

		if best_to == -1:
			break

		_connect_room_pair(_rooms[best_from], _rooms[best_to])
		in_tree[best_to] = true
		in_count += 1


func _connect_rooms_with_mst_centers() -> void:
	_carve_mst_center_links(_build_room_mst_links())


func _build_room_mst_links() -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	if _rooms.size() < 2:
		return links

	var in_tree: Array[bool] = []
	in_tree.resize(_rooms.size())
	in_tree.fill(false)
	in_tree[0] = true
	var in_count: int = 1

	while in_count < _rooms.size():
		var best_from: int = -1
		var best_to: int = -1
		var best_dist: int = 2147483647

		for i in range(_rooms.size()):
			if not in_tree[i]:
				continue
			var a: Vector2i = _room_center(_rooms[i])
			for j in range(_rooms.size()):
				if in_tree[j]:
					continue
				var b: Vector2i = _room_center(_rooms[j])
				var d: int = absi(a.x - b.x) + absi(a.y - b.y)
				if d < best_dist:
					best_dist = d
					best_from = i
					best_to = j

		if best_to == -1:
			break

		links.append(Vector2i(best_from, best_to))
		in_tree[best_to] = true
		in_count += 1

	return links


func _carve_mst_center_links(mst_links: Array[Vector2i]) -> void:
	for link in mst_links:
		var from_idx: int = link.x
		var to_idx: int = link.y
		var from_center: Vector2i = _room_center(_rooms[from_idx])
		var to_center: Vector2i = _room_center(_rooms[to_idx])
		_carve_corridor_stable(from_center, to_center)


func _collect_mst_blocked_sides(mst_links: Array[Vector2i]) -> Dictionary:
	var blocked_by_room: Dictionary = {}
	for link in mst_links:
		var from_idx: int = link.x
		var to_idx: int = link.y
		var from_center: Vector2i = _room_center(_rooms[from_idx])
		var to_center: Vector2i = _room_center(_rooms[to_idx])

		var from_side: int = _corridor_room_side_for_link(from_center, to_center, true)
		var to_side: int = _corridor_room_side_for_link(to_center, from_center, false)
		_set_room_side_blocked(blocked_by_room, from_idx, from_side)
		_set_room_side_blocked(blocked_by_room, to_idx, to_side)

	return blocked_by_room


func _corridor_room_side_for_link(room_center: Vector2i, other_center: Vector2i, is_link_start: bool) -> int:
	if room_center.x == other_center.x:
		return SIDE_BOTTOM if other_center.y > room_center.y else SIDE_TOP
	if room_center.y == other_center.y:
		return SIDE_RIGHT if other_center.x > room_center.x else SIDE_LEFT

	# Stable corridor carving is horizontal-first at the source, vertical at the target.
	if is_link_start:
		return SIDE_RIGHT if other_center.x > room_center.x else SIDE_LEFT
	return SIDE_BOTTOM if other_center.y > room_center.y else SIDE_TOP


func _set_room_side_blocked(blocked_by_room: Dictionary, room_idx: int, side: int) -> void:
	var room_blocked: Dictionary = {}
	if blocked_by_room.has(room_idx):
		room_blocked = blocked_by_room[room_idx]
	room_blocked[side] = true
	blocked_by_room[room_idx] = room_blocked


func _carve_corridor_stable(a: Vector2i, b: Vector2i) -> void:
	var half_w: int = _corridor_half_width()
	if a.x == b.x:
		_paint_vertical_band(a.x, min(a.y, b.y), max(a.y, b.y), half_w)
		return
	if a.y == b.y:
		_paint_horizontal_band(min(a.x, b.x), max(a.x, b.x), a.y, half_w)
		return

	# Deterministic L-shape for stable room-to-room ways.
	var corner: Vector2i = Vector2i(b.x, a.y)
	_paint_horizontal_band(min(a.x, b.x), max(a.x, b.x), a.y, half_w)
	_paint_vertical_band(b.x, min(a.y, b.y), max(a.y, b.y), half_w)
	_paint_corner_joint(corner, half_w)


func _connect_extra_room_links() -> void:
	if _rooms.size() < 3:
		return

	var desired_links: int = max(1, int(round(float(_rooms.size()) * 0.25)))
	var tries: int = _rooms.size() * 16
	var used_pairs: Dictionary = {}
	while tries > 0 and desired_links > 0:
		tries -= 1
		var a_idx: int = randi_range(0, _rooms.size() - 1)
		var b_idx: int = randi_range(0, _rooms.size() - 1)
		if a_idx == b_idx:
			continue

		var pair_key: String = _room_pair_key(a_idx, b_idx)
		if used_pairs.has(pair_key):
			continue
		used_pairs[pair_key] = true

		var a_center: Vector2i = _room_center(_rooms[a_idx])
		var b_center: Vector2i = _room_center(_rooms[b_idx])
		var manhattan: int = absi(a_center.x - b_center.x) + absi(a_center.y - b_center.y)
		var max_reasonable: int = int((_map_size_tiles.x + _map_size_tiles.y) * 0.45)
		if manhattan > max_reasonable and randf() < 0.75:
			continue

		_connect_room_pair(_rooms[a_idx], _rooms[b_idx])
		desired_links -= 1


func _room_pair_key(a_idx: int, b_idx: int) -> String:
	var lo: int = min(a_idx, b_idx)
	var hi: int = max(a_idx, b_idx)
	return str(lo) + ":" + str(hi)


func _connect_room_pair(room_a: Rect2i, room_b: Rect2i) -> void:
	var info_a: Dictionary = _pick_door_toward_room(room_a, room_b)
	var info_b: Dictionary = _pick_door_toward_room(room_b, room_a)
	var door_a: Vector2i = info_a["pos"] as Vector2i
	var door_b: Vector2i = info_b["pos"] as Vector2i
	var normal_a: Vector2i = info_a["normal"] as Vector2i
	var normal_b: Vector2i = info_b["normal"] as Vector2i
	var stub_a: Vector2i = _clamp_to_map(door_a + normal_a)
	var stub_b: Vector2i = _clamp_to_map(door_b + normal_b)

	_carve_corridor(door_a, stub_a)
	_carve_corridor(door_b, stub_b)
	_carve_corridor(stub_a, stub_b)


func _build_fallback_multi_room(min_block: int, min_h_wall_tiles: int, min_v_wall_tiles: int) -> void:
	var map_min_w_cfg: int = max(32, min(min_map_width, max_map_width))
	var map_max_w_cfg: int = max(map_min_w_cfg, max(min_map_width, max_map_width))
	var map_min_h_cfg: int = max(32, min(min_map_height, max_map_height))
	var map_max_h_cfg: int = max(map_min_h_cfg, max(min_map_height, max_map_height))
	var min_target_rooms: int = max(3, min(min_room_count, max_room_count))
	var max_target_rooms: int = max(min_target_rooms, max(min_room_count, max_room_count))
	var room_w_min_cfg: int = max(4, min(min_room_width, max_room_width))
	var room_w_max_cfg_raw: int = max(room_w_min_cfg, max(min_room_width, max_room_width))
	var room_h_min_cfg: int = max(4, min(min_room_height, max_room_height))
	var room_h_max_cfg_raw: int = max(room_h_min_cfg, max(min_room_height, max_room_height))
	var corridor_w: int = max(min_block, corridor_width_tiles)
	var room_w_min: int = max(room_w_min_cfg, min_h_wall_tiles * 2 + 2)
	var room_h_min: int = max(room_h_min_cfg, min_v_wall_tiles * 2 + 2)
	var room_w_max_cfg: int = max(room_w_min + 4, room_w_max_cfg_raw)
	var room_h_max_cfg: int = max(room_h_min + 4, room_h_max_cfg_raw)
	var spacing: int = max(2, room_spacing_tiles + 1)
	var placement_gap: int = max(spacing + 2, corridor_w + 1)
	var attempts: int = 420

	for _fallback_idx in range(attempts):
		_floor_cells.clear()
		_rooms.clear()

		var target_rooms: int = randi_range(min_target_rooms, max_target_rooms)
		var approx_cols: int = max(1, int(ceili(sqrt(float(target_rooms)))))
		var approx_rows: int = max(1, int(ceili(float(target_rooms) / float(approx_cols))))
		var extra_rooms: int = max(0, target_rooms - min_target_rooms)
		var avg_room_w: int = int(round((room_w_min + room_w_max_cfg) * 0.5))
		var avg_room_h: int = int(round((room_h_min + room_h_max_cfg) * 0.5))
		var growth_step_w: int = max(5, int(round(float(avg_room_w + placement_gap) * 0.65)))
		var growth_step_h: int = max(5, int(round(float(avg_room_h + placement_gap) * 0.65)))
		var growth_bonus_w: int = extra_rooms * growth_step_w
		var growth_bonus_h: int = extra_rooms * growth_step_h
		var min_map_w_needed: int = approx_cols * avg_room_w + (approx_cols + 1) * placement_gap + growth_bonus_w
		var min_map_h_needed: int = approx_rows * avg_room_h + (approx_rows + 1) * placement_gap + growth_bonus_h
		var low_w: int = max(map_min_w_cfg, min_map_w_needed)
		var high_w: int = max(low_w + 20, map_max_w_cfg)
		var low_h: int = max(map_min_h_cfg, min_map_h_needed)
		var high_h: int = max(low_h + 20, map_max_h_cfg)
		_map_size_tiles = Vector2i(randi_range(low_w, high_w), randi_range(low_h, high_h))
		var spread_x: int = max(room_w_max_cfg + placement_gap, int(round(float(_map_size_tiles.x) * 0.30)))
		var spread_y: int = max(room_h_max_cfg + placement_gap, int(round(float(_map_size_tiles.y) * 0.30)))

		var placement_attempts: int = target_rooms * 320
		while _rooms.size() < target_rooms and placement_attempts > 0:
			placement_attempts -= 1

			var room_w: int = randi_range(room_w_min, room_w_max_cfg)
			var room_h: int = randi_range(room_h_min, room_h_max_cfg)
			if room_w + 2 >= _map_size_tiles.x or room_h + 2 >= _map_size_tiles.y:
				continue

			var map_center: Vector2i = Vector2i(int(_map_size_tiles.x / 2), int(_map_size_tiles.y / 2))
			var anchor: Vector2i = map_center
			if not _rooms.is_empty():
				if randf() < 0.70:
					var parent: Rect2i = _rooms[randi_range(0, _rooms.size() - 1)]
					anchor = _room_center(parent) + Vector2i(
						randi_range(-spread_x, spread_x),
						randi_range(-spread_y, spread_y)
					)
				else:
					anchor = map_center + Vector2i(
						randi_range(-spread_x, spread_x),
						randi_range(-spread_y, spread_y)
					)

			var room_x: int = clampi(anchor.x - int(room_w / 2) + randi_range(-4, 4), 1, _map_size_tiles.x - room_w - 1)
			var room_y: int = clampi(anchor.y - int(room_h / 2) + randi_range(-4, 4), 1, _map_size_tiles.y - room_h - 1)
			var candidate: Rect2i = Rect2i(room_x, room_y, room_w, room_h)

			var overlaps: bool = false
			for existing: Rect2i in _rooms:
				if candidate.grow(placement_gap).intersects(existing.grow(placement_gap)):
					overlaps = true
					break
			if overlaps:
				continue

			_rooms.append(candidate)

		if _rooms.size() < min_target_rooms:
			continue

		for room: Rect2i in _rooms:
			_paint_rect(room, floor_detail_chance)
		_connect_rooms_with_mst()
		_connect_extra_room_links()
		_smooth_floor_shape(min_h_wall_tiles, min_v_wall_tiles)
		_enforce_min_geometry_rules(min_block, min_h_wall_tiles, min_v_wall_tiles)
		if _is_map_valid(min_block, min_h_wall_tiles, min_v_wall_tiles):
			return

	_floor_cells.clear()
	_rooms.clear()
	_map_size_tiles = Vector2i(max(map_min_w_cfg, room_w_min * 3 + 24), max(map_min_h_cfg, room_h_min * 3 + 24))
	var base_x: int = int(_map_size_tiles.x / 2) - room_w_min
	var base_y: int = int(_map_size_tiles.y / 2) - room_h_min
	var fallback_rooms: Array[Rect2i] = []
	fallback_rooms.append(Rect2i(base_x - room_w_min - 5, base_y + randi_range(-3, 3), room_w_min + 4, room_h_min + 2))
	fallback_rooms.append(Rect2i(base_x + randi_range(-2, 2), base_y - room_h_min - 6, room_w_min + 2, room_h_min + 4))
	fallback_rooms.append(Rect2i(base_x + room_w_min + 6, base_y + randi_range(-3, 3), room_w_min + 5, room_h_min + 2))
	fallback_rooms.append(Rect2i(base_x + randi_range(-2, 2), base_y + room_h_min + 7, room_w_min + 3, room_h_min + 3))
	for room: Rect2i in fallback_rooms:
		var safe_x: int = clampi(room.position.x, 1, _map_size_tiles.x - room.size.x - 1)
		var safe_y: int = clampi(room.position.y, 1, _map_size_tiles.y - room.size.y - 1)
		var safe_room: Rect2i = Rect2i(safe_x, safe_y, room.size.x, room.size.y)
		_rooms.append(safe_room)
		_paint_rect(safe_room, floor_detail_chance)
	_connect_rooms_with_mst()
	_connect_extra_room_links()
	_smooth_floor_shape(min_h_wall_tiles, min_v_wall_tiles)
	_enforce_min_geometry_rules(min_block, min_h_wall_tiles, min_v_wall_tiles)

	if _is_map_valid(min_block, min_h_wall_tiles, min_v_wall_tiles):
		return

	# Last repair pass before returning.
	_enforce_min_geometry_rules(min_block, min_h_wall_tiles, min_v_wall_tiles)


func _pick_door_toward_room(room: Rect2i, target_room: Rect2i) -> Dictionary:
	var rc: Vector2i = _room_center(room)
	var tc: Vector2i = _room_center(target_room)
	var dx: int = tc.x - rc.x
	var dy: int = tc.y - rc.y
	var min_h: int = _min_horizontal_wall_run_tiles()
	var min_v: int = _min_vertical_wall_run_tiles()

	var result: Dictionary = {
		"pos": Vector2i.ZERO,
		"normal": Vector2i.ZERO,
	}

	if absi(dx) >= absi(dy):
		var y_min: int = room.position.y + min_v
		var y_max: int = room.position.y + room.size.y - 1 - min_v
		if y_min > y_max:
			y_min = room.position.y
			y_max = room.position.y + room.size.y - 1
		var preferred_y: int = clampi(tc.y, y_min, y_max)
		var door_y: int = _pick_biased_value(y_min, y_max, preferred_y)

		if dx >= 0:
			result["pos"] = Vector2i(room.position.x + room.size.x - 1, door_y)
			result["normal"] = Vector2i.RIGHT
		else:
			result["pos"] = Vector2i(room.position.x, door_y)
			result["normal"] = Vector2i.LEFT
		return result

	var x_min: int = room.position.x + min_h
	var x_max: int = room.position.x + room.size.x - 1 - min_h
	if x_min > x_max:
		x_min = room.position.x
		x_max = room.position.x + room.size.x - 1
	var preferred_x: int = clampi(tc.x, x_min, x_max)
	var door_x: int = _pick_biased_value(x_min, x_max, preferred_x)

	if dy >= 0:
		result["pos"] = Vector2i(door_x, room.position.y + room.size.y - 1)
		result["normal"] = Vector2i.DOWN
	else:
		result["pos"] = Vector2i(door_x, room.position.y)
		result["normal"] = Vector2i.UP
	return result


func _pick_biased_value(min_value: int, max_value: int, preferred: int) -> int:
	if min_value >= max_value:
		return min_value

	return clampi(preferred, min_value, max_value)


func _clamp_to_map(pos: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(pos.x, 0, _map_size_tiles.x - 1),
		clampi(pos.y, 0, _map_size_tiles.y - 1)
	)


func _corridor_half_width() -> int:
	var corridor_w: int = max(min_floor_block_tiles, corridor_width_tiles)
	return max(1, int(corridor_w / 2))


func _room_center(room: Rect2i) -> Vector2i:
	return Vector2i(
		room.position.x + int(room.size.x / 2),
		room.position.y + int(room.size.y / 2)
	)


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var half_w: int = _corridor_half_width()
	if a.x == b.x:
		_paint_vertical_band(a.x, min(a.y, b.y), max(a.y, b.y), half_w)
		return
	if a.y == b.y:
		_paint_horizontal_band(min(a.x, b.x), max(a.x, b.x), a.y, half_w)
		return

	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	var horizontal_first: bool = dx >= dy

	if horizontal_first:
		var corner: Vector2i = Vector2i(b.x, a.y)
		_paint_horizontal_band(min(a.x, b.x), max(a.x, b.x), a.y, half_w)
		_paint_vertical_band(b.x, min(a.y, b.y), max(a.y, b.y), half_w)
		_paint_corner_joint(corner, half_w)
	else:
		var corner: Vector2i = Vector2i(a.x, b.y)
		_paint_vertical_band(a.x, min(a.y, b.y), max(a.y, b.y), half_w)
		_paint_horizontal_band(min(a.x, b.x), max(a.x, b.x), b.y, half_w)
		_paint_corner_joint(corner, half_w)


func _paint_corner_joint(corner: Vector2i, half_w: int) -> void:
	var min_x: int = clampi(corner.x - half_w, 0, _map_size_tiles.x - 1)
	var max_x: int = clampi(corner.x + half_w, 0, _map_size_tiles.x - 1)
	var min_y: int = clampi(corner.y - half_w, 0, _map_size_tiles.y - 1)
	var max_y: int = clampi(corner.y + half_w, 0, _map_size_tiles.y - 1)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			_paint_floor_cell(Vector2i(x, y), corridor_detail_chance)


func _paint_horizontal_band(x0: int, x1: int, center_y: int, half_w: int) -> void:
	var clamped_x0: int = clampi(x0, 0, _map_size_tiles.x - 1)
	var clamped_x1: int = clampi(x1, 0, _map_size_tiles.x - 1)
	var min_y: int = clampi(center_y - half_w, 0, _map_size_tiles.y - 1)
	var max_y: int = clampi(center_y + half_w, 0, _map_size_tiles.y - 1)
	for y in range(min_y, max_y + 1):
		for x in range(clamped_x0, clamped_x1 + 1):
			_paint_floor_cell(Vector2i(x, y), corridor_detail_chance)


func _paint_vertical_band(center_x: int, y0: int, y1: int, half_w: int) -> void:
	var clamped_y0: int = clampi(y0, 0, _map_size_tiles.y - 1)
	var clamped_y1: int = clampi(y1, 0, _map_size_tiles.y - 1)
	var min_x: int = clampi(center_x - half_w, 0, _map_size_tiles.x - 1)
	var max_x: int = clampi(center_x + half_w, 0, _map_size_tiles.x - 1)
	for y in range(clamped_y0, clamped_y1 + 1):
		for x in range(min_x, max_x + 1):
			_paint_floor_cell(Vector2i(x, y), corridor_detail_chance)


func _draw() -> void:
	if _floor_cells.is_empty():
		return

	_draw_walls_from_floor_edges()
	_draw_corner_decors()
	_draw_floor_tiles()


func _rebuild_public_map_data() -> void:
	floor_rects.clear()
	if _floor_cells.is_empty():
		world_size = Vector2.ZERO
		return

	var rows: Dictionary = {}
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for key in _floor_cells.keys():
		var p: Vector2i = key
		var shifted: Vector2i = Vector2i(p.x + map_origin_tiles.x, p.y + map_origin_tiles.y)
		if not rows.has(shifted.y):
			rows[shifted.y] = []
		(rows[shifted.y] as Array).append(shifted.x)
		max_x = max(max_x, shifted.x)
		max_y = max(max_y, shifted.y)

	for row_key in rows.keys():
		var row_y: int = int(row_key)
		var xs: Array = rows[row_key]
		xs.sort()
		for run in _group_runs(xs):
			var x0: int = int(run[0])
			var x1: int = int(run[1])
			floor_rects.append(Rect2i(x0, row_y, x1 - x0 + 1, 1))

	world_size = Vector2(float(max_x + 1) * TILE_SIZE, float(max_y + 1) * TILE_SIZE)


func _place_breaker() -> void:
	var breaker: Node2D = get_node_or_null("Breaker") as Node2D
	if breaker == null or _rooms.is_empty():
		return

	var spawn_room: Rect2i = _rooms[randi_range(0, _rooms.size() - 1)]
	var spawn_tile: Vector2i = Vector2i(
		spawn_room.position.x + int(spawn_room.size.x / 2),
		spawn_room.position.y + int(spawn_room.size.y / 2)
	)
	breaker.global_position = Vector2(
		(map_origin_tiles.x + spawn_tile.x + 0.5) * TILE_SIZE,
		(map_origin_tiles.y + spawn_tile.y + 0.5) * TILE_SIZE
	)


func _draw_floor_tiles() -> void:
	var base_x: int = map_origin_tiles.x * TILE_SIZE
	var base_y: int = map_origin_tiles.y * TILE_SIZE

	for key in _floor_cells.keys():
		var p: Vector2i = key
		var frame_index: int = _floor_cells[p]
		var src: Rect2 = Rect2(frame_index * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)
		var dst: Rect2 = Rect2(base_x + p.x * TILE_SIZE, base_y + p.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		draw_texture_rect_region(_floor_texture, dst, src)


func _draw_walls_from_floor_edges() -> void:
	var edges: Dictionary = _collect_exposed_wall_edges()
	var top_edges_by_row: Dictionary = edges["top"]
	var bottom_edges_by_row: Dictionary = edges["bottom"]
	var left_edges_by_col: Dictionary = edges["left"]
	var right_edges_by_col: Dictionary = edges["right"]
	var corner_fillers: Dictionary = _collect_corner_frame_fillers()
	var top_fillers: Array = corner_fillers["top"]
	var bottom_fillers: Array = corner_fillers["bottom"]

	for row_key in top_edges_by_row.keys():
		var row_y: int = int(row_key)
		var xs: Array = top_edges_by_row[row_key]
		xs.sort()
		for run in _group_runs(xs):
			_draw_top_run(run[0], run[1], row_y)
	for cap in top_fillers:
		var top_cap: Vector2i = cap
		_draw_top_run(top_cap.x, top_cap.x, top_cap.y)

	var left_runs: Array = _collect_vertical_runs(left_edges_by_col)
	var right_runs: Array = _collect_vertical_runs(right_edges_by_col)
	for run_data in left_runs:
		var run: Vector3i = run_data
		_draw_left_vertical_run(run.x, run.y, run.z)

	for run_data in right_runs:
		var run: Vector3i = run_data
		_draw_right_vertical_run(run.x, run.y, run.z)

	for row_key in bottom_edges_by_row.keys():
		var row_y: int = int(row_key)
		var xs: Array = bottom_edges_by_row[row_key]
		xs.sort()
		for run in _group_runs(xs):
			_draw_bottom_run(run[0], run[1], row_y)
	for cap in bottom_fillers:
		var bottom_cap: Vector2i = cap
		_draw_bottom_run(bottom_cap.x, bottom_cap.x, bottom_cap.y)


func _collect_corner_frame_fillers() -> Dictionary:
	var top_caps: Array = []
	var bottom_caps: Array = []
	if _floor_cells.is_empty():
		return {"top": top_caps, "bottom": bottom_caps}

	var top_seen: Dictionary = {}
	var bottom_seen: Dictionary = {}

	# Close convex outer corner holes:
	# top-left / top-right use top frame, bottom-left / bottom-right use bottom frame.
	for key in _floor_cells.keys():
		var p: Vector2i = key
		var x: int = p.x
		var y: int = p.y

		var open_left: bool = not _has_floor(x - 1, y)
		var open_right: bool = not _has_floor(x + 1, y)
		var open_up: bool = not _has_floor(x, y - 1)
		var open_down: bool = not _has_floor(x, y + 1)

		if open_up and open_left:
			var top_left_cap: Vector2i = Vector2i(x - 1, y)
			if not top_seen.has(top_left_cap):
				top_seen[top_left_cap] = true
				top_caps.append(top_left_cap)
		if open_up and open_right:
			var top_right_cap: Vector2i = Vector2i(x + 1, y)
			if not top_seen.has(top_right_cap):
				top_seen[top_right_cap] = true
				top_caps.append(top_right_cap)
		if open_down and open_left:
			var bottom_left_cap: Vector2i = Vector2i(x - 1, y)
			if not bottom_seen.has(bottom_left_cap):
				bottom_seen[bottom_left_cap] = true
				bottom_caps.append(bottom_left_cap)
		if open_down and open_right:
			var bottom_right_cap: Vector2i = Vector2i(x + 1, y)
			if not bottom_seen.has(bottom_right_cap):
				bottom_seen[bottom_right_cap] = true
				bottom_caps.append(bottom_right_cap)

	return {
		"top": top_caps,
		"bottom": bottom_caps,
	}


func _draw_corner_decors() -> void:
	if not use_corner_decor:
		return
	var top_tex: Texture2D = _wall_top_corner_texture
	var inner_bottom_tex: Texture2D = _wall_inner_bottom_corner_texture
	var outer_bottom_tex: Texture2D = _wall_outer_bottom_corner_texture
	var inner_top_tex: Texture2D = _wall_inner_top_corner_texture
	if top_tex == null or inner_bottom_tex == null or outer_bottom_tex == null or inner_top_tex == null:
		return
	if _floor_cells.is_empty():
		return

	var top_w: int = top_tex.get_width()
	var top_h: int = top_tex.get_height()
	var inner_bottom_w: int = inner_bottom_tex.get_width()
	var inner_bottom_h: int = inner_bottom_tex.get_height()
	var outer_bottom_w: int = outer_bottom_tex.get_width()
	var outer_bottom_h: int = outer_bottom_tex.get_height()
	var inner_top_w: int = inner_top_tex.get_width()
	var inner_top_h: int = inner_top_tex.get_height()
	if top_w <= 0 or top_h <= 0 or inner_bottom_w <= 0 or inner_bottom_h <= 0 or outer_bottom_w <= 0 or outer_bottom_h <= 0 or inner_top_w <= 0 or inner_top_h <= 0:
		return
	var outer_bottom_lift_px: int = -50

	var base_x: int = map_origin_tiles.x * TILE_SIZE
	var base_y: int = map_origin_tiles.y * TILE_SIZE
	var placed_top: Dictionary = {}
	var placed_bottom: Dictionary = {}

	# Pass 1: floor-cell outer corners.
	for key in _floor_cells.keys():
		var p: Vector2i = key
		var x: int = p.x
		var y: int = p.y

		var open_left: bool = not _has_floor(x - 1, y)
		var open_right: bool = not _has_floor(x + 1, y)
		var open_up: bool = not _has_floor(x, y - 1)
		var open_down: bool = not _has_floor(x, y + 1)

		# Outer top -> top-corner texture.
		if open_up and open_left:
			_draw_top_corner_decor(top_tex, placed_top, base_x, base_y, x, y, true)
		if open_up and open_right:
			_draw_top_corner_decor(top_tex, placed_top, base_x, base_y, x + 1, y, false)
		# Outer bottom -> outer-bottom-corner texture.
		if open_down and open_left:
			_draw_bottom_corner_decor(outer_bottom_tex, placed_bottom, base_x, base_y, x, y + 1, true, outer_bottom_lift_px)
		if open_down and open_right:
			_draw_bottom_corner_decor(outer_bottom_tex, placed_bottom, base_x, base_y, x + 1, y + 1, false, outer_bottom_lift_px)

	# Pass 2: inner notch corners (empty tile with L-shaped neighboring floor).
	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for floor_key in _floor_cells.keys():
		var fp: Vector2i = floor_key
		min_x = min(min_x, fp.x)
		min_y = min(min_y, fp.y)
		max_x = max(max_x, fp.x)
		max_y = max(max_y, fp.y)

	for y in range(min_y - 1, max_y + 2):
		for x in range(min_x - 1, max_x + 2):
			if _has_floor(x, y):
				continue

			var left: bool = _has_floor(x - 1, y)
			var right: bool = _has_floor(x + 1, y)
			var up: bool = _has_floor(x, y - 1)
			var down: bool = _has_floor(x, y + 1)

			# Inner bottom -> inner-top-corner texture.
			if left and up and (not right) and (not down):
				_draw_bottom_corner_decor(inner_bottom_tex, placed_top, base_x, base_y, x, y, false)
			elif right and up and (not left) and (not down):
				_draw_bottom_corner_decor(inner_bottom_tex, placed_top, base_x, base_y, x + 1, y, true)
			# Inner top -> inner-bottom-corner texture.
			elif left and down and (not right) and (not up):
				_draw_top_corner_decor(inner_top_tex, placed_bottom, base_x, base_y, x, y + 1, false)
			elif right and down and (not left) and (not up):
				_draw_top_corner_decor(inner_top_tex, placed_bottom, base_x, base_y, x + 1, y + 1, true)


func _draw_top_corner_decor(tex: Texture2D, placed: Dictionary, base_x: int, base_y: int, vertex_x: int, vertex_y: int, is_left_corner: bool, extra_y_px: int = 0) -> void:
	var tex_w: int = tex.get_width()
	var tex_h: int = tex.get_height()
	var px: int = base_x + vertex_x * TILE_SIZE
	if is_left_corner:
		px -= tex_w
	var py: int = base_y + vertex_y * TILE_SIZE - tex_h + extra_y_px
	var key: Vector2i = Vector2i(px, py)
	if placed.has(key):
		return
	placed[key] = true
	draw_texture_rect(tex, Rect2(px, py, tex_w, tex_h), false)


func _draw_bottom_corner_decor(tex: Texture2D, placed: Dictionary, base_x: int, base_y: int, vertex_x: int, vertex_y: int, is_left_corner: bool, extra_y_px: int = 0) -> void:
	var tex_w: int = tex.get_width()
	var tex_h: int = tex.get_height()
	var px: int = base_x + vertex_x * TILE_SIZE
	if is_left_corner:
		px -= tex_w
	var py: int = base_y + vertex_y * TILE_SIZE + extra_y_px
	var key: Vector2i = Vector2i(px, py)
	if placed.has(key):
		return
	placed[key] = true
	draw_texture_rect(tex, Rect2(px, py, tex_w, tex_h), false)


func _draw_top_run(x0: int, x1: int, row_y: int) -> void:
	var base_x: float = map_origin_tiles.x * TILE_SIZE
	var base_y: float = map_origin_tiles.y * TILE_SIZE
	var overlap: float = max(0.0, wall_overlap_px)
	var top_w: float = _wall_top_texture.get_width()
	var top_h: float = _wall_top_texture.get_height()

	var raw_w: float = (x1 - x0 + 1) * TILE_SIZE
	var run_w: float = ceili(raw_w / top_w) * top_w
	var run_x: float = base_x + x0 * TILE_SIZE - (run_w - raw_w) * 0.5
	var run_y: float = base_y + row_y * TILE_SIZE - top_h + overlap

	_draw_strip(_wall_top_texture, Rect2(run_x, run_y, run_w, top_h), false, true)


func _draw_bottom_run(x0: int, x1: int, row_y: int) -> void:
	var base_x: float = map_origin_tiles.x * TILE_SIZE
	var base_y: float = map_origin_tiles.y * TILE_SIZE
	var overlap: float = max(0.0, wall_overlap_px)
	var bottom_w: float = _wall_bottom_texture.get_width()
	var bottom_h: float = _wall_bottom_texture.get_height()

	var raw_w: float = (x1 - x0 + 1) * TILE_SIZE
	var run_w: float = ceili(raw_w / bottom_w) * bottom_w
	var run_x: float = base_x + x0 * TILE_SIZE - (run_w - raw_w) * 0.5
	var run_y: float = base_y + (row_y + 1) * TILE_SIZE - overlap

	_draw_strip(_wall_bottom_texture, Rect2(run_x, run_y, run_w, bottom_h), false, true)


func _draw_left_vertical_run(col_x: int, y0: int, y1: int) -> int:
	var base_x: float = map_origin_tiles.x * TILE_SIZE
	var base_y: float = map_origin_tiles.y * TILE_SIZE
	var overlap: float = max(0.0, wall_overlap_px)
	var side_inset: float = max(0.0, side_wall_inset_px)
	var outward_nudge: float = max(0.0, side_wall_outward_nudge_px)
	var vertical_w: float = _wall_vertical_texture.get_width()
	var vertical_h: float = _wall_vertical_texture.get_height()
	var top_overlap_px: float = clampf(side_wall_top_overlap_ratio, 0.0, 0.5) * vertical_h
	var extra_height_px: float = max(0.0, side_wall_extra_lift_px)

	var wall_x: float = base_x + col_x * TILE_SIZE - vertical_w + overlap + side_inset - outward_nudge
	var wall_start_y: float = base_y + y0 * TILE_SIZE - top_overlap_px
	var wall_end_y: float = base_y + (y1 + 1) * TILE_SIZE + extra_height_px
	var wall_h: float = max(0.0, wall_end_y - wall_start_y)
	if wall_h <= 0.01:
		return 0

	var full_count: int = int(floor(wall_h / vertical_h))
	var remainder_h: float = wall_h - float(full_count) * vertical_h
	for i in range(full_count):
		var y: float = wall_start_y + float(i) * vertical_h
		_draw_strip(_wall_vertical_texture, Rect2(wall_x, y, vertical_w, vertical_h), false, false)

	if remainder_h > 0.01:
		var tail_y: float = wall_start_y + float(full_count) * vertical_h
		_draw_strip(_wall_vertical_texture, Rect2(wall_x, tail_y, vertical_w, remainder_h), false, false)
		return full_count + 1
	return full_count


func _draw_right_vertical_run(col_x: int, y0: int, y1: int) -> int:
	var base_x: float = map_origin_tiles.x * TILE_SIZE
	var base_y: float = map_origin_tiles.y * TILE_SIZE
	var overlap: float = max(0.0, wall_overlap_px)
	var side_inset: float = max(0.0, side_wall_inset_px)
	var outward_nudge: float = max(0.0, side_wall_outward_nudge_px)
	var vertical_w: float = _wall_vertical_texture.get_width()
	var vertical_h: float = _wall_vertical_texture.get_height()
	var top_overlap_px: float = clampf(side_wall_top_overlap_ratio, 0.0, 0.5) * vertical_h
	var extra_height_px: float = max(0.0, side_wall_extra_lift_px)

	var wall_x: float = base_x + (col_x + 1) * TILE_SIZE - overlap - side_inset + outward_nudge
	var wall_start_y: float = base_y + y0 * TILE_SIZE - top_overlap_px
	var wall_end_y: float = base_y + (y1 + 1) * TILE_SIZE + extra_height_px
	var wall_h: float = max(0.0, wall_end_y - wall_start_y)
	if wall_h <= 0.01:
		return 0

	var full_count: int = int(floor(wall_h / vertical_h))
	var remainder_h: float = wall_h - float(full_count) * vertical_h
	for i in range(full_count):
		var y: float = wall_start_y + float(i) * vertical_h
		_draw_strip(_wall_vertical_texture, Rect2(wall_x, y, vertical_w, vertical_h), true, false)

	if remainder_h > 0.01:
		var tail_y: float = wall_start_y + float(full_count) * vertical_h
		_draw_strip(_wall_vertical_texture, Rect2(wall_x, tail_y, vertical_w, remainder_h), true, false)
		return full_count + 1
	return full_count


func _has_floor(x: int, y: int) -> bool:
	return _floor_cells.has(Vector2i(x, y))


func _group_runs(sorted_values: Array) -> Array:
	var runs: Array = []
	if sorted_values.is_empty():
		return runs

	var run_start: int = sorted_values[0]
	var run_end: int = sorted_values[0]
	for i in range(1, sorted_values.size()):
		var value: int = sorted_values[i]
		if value == run_end + 1:
			run_end = value
		else:
			runs.append([run_start, run_end])
			run_start = value
			run_end = value
	runs.append([run_start, run_end])
	return runs


func _collect_exposed_wall_edges() -> Dictionary:
	var top_edges_by_row: Dictionary = {}
	var bottom_edges_by_row: Dictionary = {}
	var left_edges_by_col: Dictionary = {}
	var right_edges_by_col: Dictionary = {}

	for key in _floor_cells.keys():
		var p: Vector2i = key
		var x: int = p.x
		var y: int = p.y

		if not _has_floor(x, y - 1):
			if not top_edges_by_row.has(y):
				top_edges_by_row[y] = []
			(top_edges_by_row[y] as Array).append(x)
		if not _has_floor(x, y + 1):
			if not bottom_edges_by_row.has(y):
				bottom_edges_by_row[y] = []
			(bottom_edges_by_row[y] as Array).append(x)
		if not _has_floor(x - 1, y):
			if not left_edges_by_col.has(x):
				left_edges_by_col[x] = []
			(left_edges_by_col[x] as Array).append(y)
		if not _has_floor(x + 1, y):
			if not right_edges_by_col.has(x):
				right_edges_by_col[x] = []
			(right_edges_by_col[x] as Array).append(y)

	return {
		"top": top_edges_by_row,
		"bottom": bottom_edges_by_row,
		"left": left_edges_by_col,
		"right": right_edges_by_col,
	}


func _is_map_valid(min_floor_len: int, min_horizontal_len: int, min_vertical_len: int) -> bool:
	return _validate_min_floor_runs(min_floor_len) and _validate_min_wall_edge_runs(min_horizontal_len, min_vertical_len)


func _smooth_floor_shape(min_horizontal_len: int, min_vertical_len: int) -> void:
	var passes: int = 3
	for _pass_idx in range(passes):
		var changed: int = 0
		changed += _fill_three_neighbor_voids()
		changed += _fill_stair_step_voids()
		if changed == 0:
			return


func _enforce_min_geometry_rules(min_floor_len: int, min_horizontal_len: int, min_vertical_len: int) -> void:
	var max_passes: int = 6
	for _pass_idx in range(max_passes):
		if _is_map_valid(min_floor_len, min_horizontal_len, min_vertical_len):
			return
		var changed: int = 0
		changed += _enforce_min_exposed_edge_runs(min_horizontal_len, min_vertical_len, 1)
		changed += _fill_short_void_slits(min_horizontal_len, min_vertical_len)
		changed += _fill_three_neighbor_voids()
		changed += _orthogonalize_floor_edges(1)
		changed += _fill_stair_step_voids()
		if changed == 0:
			return


func _enforce_min_exposed_edge_runs(min_horizontal_len: int, min_vertical_len: int, max_passes: int = 2) -> int:
	if _floor_cells.is_empty():
		return 0

	var total_changed: int = 0
	var passes: int = max(1, max_passes)
	for _pass_idx in range(passes):
		var edges: Dictionary = _collect_exposed_wall_edges()
		var top_edges_by_row: Dictionary = edges["top"]
		var bottom_edges_by_row: Dictionary = edges["bottom"]
		var left_edges_by_col: Dictionary = edges["left"]
		var right_edges_by_col: Dictionary = edges["right"]
		var to_fill: Dictionary = {}

		for row_key in top_edges_by_row.keys():
			var row_y: int = int(row_key)
			var xs: Array = top_edges_by_row[row_key]
			xs.sort()
			for run in _group_runs(xs):
				var x0: int = int(run[0])
				var x1: int = int(run[1])
				var run_len: int = x1 - x0 + 1
				if run_len < min_horizontal_len:
					var need: int = min_horizontal_len - run_len
					var left_need: int = int(floor(float(need) * 0.5))
					var right_need: int = need - left_need
					for i in range(1, left_need + 1):
						var p_left: Vector2i = Vector2i(x0 - i, row_y)
						if _in_map(p_left):
							to_fill[p_left] = true
					for i in range(1, right_need + 1):
						var p_right: Vector2i = Vector2i(x1 + i, row_y)
						if _in_map(p_right):
							to_fill[p_right] = true

		for row_key in bottom_edges_by_row.keys():
			var row_y: int = int(row_key)
			var xs: Array = bottom_edges_by_row[row_key]
			xs.sort()
			for run in _group_runs(xs):
				var x0: int = int(run[0])
				var x1: int = int(run[1])
				var run_len: int = x1 - x0 + 1
				if run_len < min_horizontal_len:
					var need: int = min_horizontal_len - run_len
					var left_need: int = int(floor(float(need) * 0.5))
					var right_need: int = need - left_need
					for i in range(1, left_need + 1):
						var p_left: Vector2i = Vector2i(x0 - i, row_y)
						if _in_map(p_left):
							to_fill[p_left] = true
					for i in range(1, right_need + 1):
						var p_right: Vector2i = Vector2i(x1 + i, row_y)
						if _in_map(p_right):
							to_fill[p_right] = true

		for col_key in left_edges_by_col.keys():
			var col_x: int = int(col_key)
			var ys: Array = left_edges_by_col[col_key]
			ys.sort()
			for run in _group_runs(ys):
				var y0: int = int(run[0])
				var y1: int = int(run[1])
				var run_len: int = y1 - y0 + 1
				if run_len < min_vertical_len:
					var need: int = min_vertical_len - run_len
					var up_need: int = int(floor(float(need) * 0.5))
					var down_need: int = need - up_need
					for i in range(1, up_need + 1):
						var p_up: Vector2i = Vector2i(col_x, y0 - i)
						if _in_map(p_up):
							to_fill[p_up] = true
					for i in range(1, down_need + 1):
						var p_down: Vector2i = Vector2i(col_x, y1 + i)
						if _in_map(p_down):
							to_fill[p_down] = true

		for col_key in right_edges_by_col.keys():
			var col_x: int = int(col_key)
			var ys: Array = right_edges_by_col[col_key]
			ys.sort()
			for run in _group_runs(ys):
				var y0: int = int(run[0])
				var y1: int = int(run[1])
				var run_len: int = y1 - y0 + 1
				if run_len < min_vertical_len:
					var need: int = min_vertical_len - run_len
					var up_need: int = int(floor(float(need) * 0.5))
					var down_need: int = need - up_need
					for i in range(1, up_need + 1):
						var p_up: Vector2i = Vector2i(col_x, y0 - i)
						if _in_map(p_up):
							to_fill[p_up] = true
					for i in range(1, down_need + 1):
						var p_down: Vector2i = Vector2i(col_x, y1 + i)
						if _in_map(p_down):
							to_fill[p_down] = true

		var changed_this_pass: int = 0
		for key in to_fill.keys():
			var pos: Vector2i = key
			if not _has_floor(pos.x, pos.y):
				_paint_floor_cell(pos, corridor_detail_chance)
				changed_this_pass += 1
		total_changed += changed_this_pass
		if changed_this_pass == 0:
			break

	return total_changed


func _fill_short_void_slits(min_horizontal_len: int, min_vertical_len: int) -> int:
	if _floor_cells.is_empty():
		return 0

	var to_fill: Dictionary = {}
	var max_x: int = _map_size_tiles.x
	var max_y: int = _map_size_tiles.y

	for x in range(1, max_x - 1):
		var y: int = 1
		while y < max_y - 1:
			if _has_floor(x, y) or not _has_floor(x - 1, y) or not _has_floor(x + 1, y):
				y += 1
				continue
			var start_y: int = y
			while y < max_y - 1 and (not _has_floor(x, y)) and _has_floor(x - 1, y) and _has_floor(x + 1, y):
				y += 1
			var end_y: int = y - 1
			if end_y - start_y + 1 < min_vertical_len:
				for ny in range(start_y, end_y + 1):
					to_fill[Vector2i(x, ny)] = true

	for y in range(1, max_y - 1):
		var x: int = 1
		while x < max_x - 1:
			if _has_floor(x, y) or not _has_floor(x, y - 1) or not _has_floor(x, y + 1):
				x += 1
				continue
			var start_x: int = x
			while x < max_x - 1 and (not _has_floor(x, y)) and _has_floor(x, y - 1) and _has_floor(x, y + 1):
				x += 1
			var end_x: int = x - 1
			if end_x - start_x + 1 < min_horizontal_len:
				for nx in range(start_x, end_x + 1):
					to_fill[Vector2i(nx, y)] = true

	var changed: int = 0
	for key in to_fill.keys():
		var pos: Vector2i = key
		if not _has_floor(pos.x, pos.y):
			_paint_floor_cell(pos, corridor_detail_chance)
			changed += 1
	return changed


func _fill_three_neighbor_voids() -> int:
	if _floor_cells.is_empty():
		return 0

	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for key in _floor_cells.keys():
		var p: Vector2i = key
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	var scan_min_x: int = clampi(min_x - 1, 1, _map_size_tiles.x - 2)
	var scan_max_x: int = clampi(max_x + 1, 1, _map_size_tiles.x - 2)
	var scan_min_y: int = clampi(min_y - 1, 1, _map_size_tiles.y - 2)
	var scan_max_y: int = clampi(max_y + 1, 1, _map_size_tiles.y - 2)

	var to_fill: Dictionary = {}
	for y in range(scan_min_y, scan_max_y + 1):
		for x in range(scan_min_x, scan_max_x + 1):
			if _has_floor(x, y):
				continue

			var left: bool = _has_floor(x - 1, y)
			var right: bool = _has_floor(x + 1, y)
			var up: bool = _has_floor(x, y - 1)
			var down: bool = _has_floor(x, y + 1)
			var n: int = 0
			if left:
				n += 1
			if right:
				n += 1
			if up:
				n += 1
			if down:
				n += 1

			if n >= 3:
				to_fill[Vector2i(x, y)] = true

	var changed: int = 0
	for key in to_fill.keys():
		var pos: Vector2i = key
		if not _has_floor(pos.x, pos.y):
			_paint_floor_cell(pos, corridor_detail_chance)
			changed += 1
	return changed


func _fill_stair_step_voids() -> int:
	if _floor_cells.is_empty():
		return 0

	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for key in _floor_cells.keys():
		var p: Vector2i = key
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	var scan_min_x: int = clampi(min_x - 1, 1, _map_size_tiles.x - 2)
	var scan_max_x: int = clampi(max_x + 1, 1, _map_size_tiles.x - 2)
	var scan_min_y: int = clampi(min_y - 1, 1, _map_size_tiles.y - 2)
	var scan_max_y: int = clampi(max_y + 1, 1, _map_size_tiles.y - 2)

	var to_fill: Dictionary = {}
	for y in range(scan_min_y, scan_max_y + 1):
		for x in range(scan_min_x, scan_max_x + 1):
			if _has_floor(x, y):
				continue

			var left: bool = _has_floor(x - 1, y)
			var right: bool = _has_floor(x + 1, y)
			var up: bool = _has_floor(x, y - 1)
			var down: bool = _has_floor(x, y + 1)

			# Fill one-tile "stair" elbows that create diagonal wall artifacts.
			if left and up and (not right) and (not down) and _has_floor(x - 1, y - 1):
				to_fill[Vector2i(x, y)] = true
				continue
			if right and up and (not left) and (not down) and _has_floor(x + 1, y - 1):
				to_fill[Vector2i(x, y)] = true
				continue
			if left and down and (not right) and (not up) and _has_floor(x - 1, y + 1):
				to_fill[Vector2i(x, y)] = true
				continue
			if right and down and (not left) and (not up) and _has_floor(x + 1, y + 1):
				to_fill[Vector2i(x, y)] = true

	var changed: int = 0
	for key in to_fill.keys():
		var pos: Vector2i = key
		if not _has_floor(pos.x, pos.y):
			_paint_floor_cell(pos, corridor_detail_chance)
			changed += 1
	return changed


func _orthogonalize_floor_edges(max_passes: int = 2) -> int:
	if _floor_cells.is_empty():
		return 0

	var total_changed: int = 0
	var passes: int = max(1, max_passes)
	for _pass_idx in range(passes):
		var min_x: int = 2147483647
		var min_y: int = 2147483647
		var max_x: int = -2147483648
		var max_y: int = -2147483648
		for key in _floor_cells.keys():
			var p: Vector2i = key
			min_x = min(min_x, p.x)
			min_y = min(min_y, p.y)
			max_x = max(max_x, p.x)
			max_y = max(max_y, p.y)

		var scan_min_x: int = clampi(min_x - 1, 0, _map_size_tiles.x - 2)
		var scan_max_x: int = clampi(max_x + 1, 0, _map_size_tiles.x - 2)
		var scan_min_y: int = clampi(min_y - 1, 0, _map_size_tiles.y - 2)
		var scan_max_y: int = clampi(max_y + 1, 0, _map_size_tiles.y - 2)
		var to_fill: Dictionary = {}

		for y in range(scan_min_y, scan_max_y + 1):
			for x in range(scan_min_x, scan_max_x + 1):
				var a: bool = _has_floor(x, y)
				var b: bool = _has_floor(x + 1, y)
				var c: bool = _has_floor(x, y + 1)
				var d: bool = _has_floor(x + 1, y + 1)

				# Checkerboard diagonal: choose one gap tile to square the edge.
				if a and d and (not b) and (not c):
					var fill_b: Vector2i = Vector2i(x + 1, y)
					var fill_c: Vector2i = Vector2i(x, y + 1)
					if _cardinal_floor_support(fill_b) >= _cardinal_floor_support(fill_c):
						if _in_map(fill_b):
							to_fill[fill_b] = true
					else:
						if _in_map(fill_c):
							to_fill[fill_c] = true
				elif b and c and (not a) and (not d):
					var fill_a: Vector2i = Vector2i(x, y)
					var fill_d: Vector2i = Vector2i(x + 1, y + 1)
					if _cardinal_floor_support(fill_a) >= _cardinal_floor_support(fill_d):
						if _in_map(fill_a):
							to_fill[fill_a] = true
					else:
						if _in_map(fill_d):
							to_fill[fill_d] = true

		var changed_this_pass: int = 0
		for key in to_fill.keys():
			var pos: Vector2i = key
			if not _has_floor(pos.x, pos.y):
				_paint_floor_cell(pos, corridor_detail_chance)
				changed_this_pass += 1
		total_changed += changed_this_pass
		if changed_this_pass == 0:
			break

	return total_changed


func _cardinal_floor_support(pos: Vector2i) -> int:
	var support: int = 0
	if _has_floor(pos.x - 1, pos.y):
		support += 1
	if _has_floor(pos.x + 1, pos.y):
		support += 1
	if _has_floor(pos.x, pos.y - 1):
		support += 1
	if _has_floor(pos.x, pos.y + 1):
		support += 1
	return support


func _force_expand_short_edges(min_horizontal_len: int, min_vertical_len: int) -> void:
	var max_passes: int = 24
	for _pass_idx in range(max_passes):
		var edges: Dictionary = _collect_exposed_wall_edges()
		var top_edges_by_row: Dictionary = edges["top"]
		var bottom_edges_by_row: Dictionary = edges["bottom"]
		var left_edges_by_col: Dictionary = edges["left"]
		var right_edges_by_col: Dictionary = edges["right"]
		var to_fill: Dictionary = {}

		for row_key in top_edges_by_row.keys():
			var row_y: int = int(row_key)
			var xs: Array = top_edges_by_row[row_key]
			xs.sort()
			for run in _group_runs(xs):
				var x0: int = int(run[0])
				var x1: int = int(run[1])
				if (x1 - x0 + 1) < min_horizontal_len:
					for x in range(x0, x1 + 1):
						var p: Vector2i = Vector2i(x, row_y - 1)
						if _in_map(p):
							to_fill[p] = true

		for row_key in bottom_edges_by_row.keys():
			var row_y: int = int(row_key)
			var xs: Array = bottom_edges_by_row[row_key]
			xs.sort()
			for run in _group_runs(xs):
				var x0: int = int(run[0])
				var x1: int = int(run[1])
				if (x1 - x0 + 1) < min_horizontal_len:
					for x in range(x0, x1 + 1):
						var p: Vector2i = Vector2i(x, row_y + 1)
						if _in_map(p):
							to_fill[p] = true

		for col_key in left_edges_by_col.keys():
			var col_x: int = int(col_key)
			var ys: Array = left_edges_by_col[col_key]
			ys.sort()
			for run in _group_runs(ys):
				var y0: int = int(run[0])
				var y1: int = int(run[1])
				var run_len: int = y1 - y0 + 1
				if run_len < min_vertical_len:
					for y in range(y0, y1 + 1):
						var p: Vector2i = Vector2i(col_x - 1, y)
						if _in_map(p):
							to_fill[p] = true
				elif _is_excluded_vertical_floor_height(run_len):
					_schedule_vertical_run_extension(col_x, y0, y1, to_fill)

		for col_key in right_edges_by_col.keys():
			var col_x: int = int(col_key)
			var ys: Array = right_edges_by_col[col_key]
			ys.sort()
			for run in _group_runs(ys):
				var y0: int = int(run[0])
				var y1: int = int(run[1])
				var run_len: int = y1 - y0 + 1
				if run_len < min_vertical_len:
					for y in range(y0, y1 + 1):
						var p: Vector2i = Vector2i(col_x + 1, y)
						if _in_map(p):
							to_fill[p] = true
				elif _is_excluded_vertical_floor_height(run_len):
					_schedule_vertical_run_extension(col_x, y0, y1, to_fill)

		if to_fill.is_empty():
			var stair_changed: int = _fill_stair_step_voids()
			if stair_changed == 0:
				return
			continue

		var changed: int = 0
		for key in to_fill.keys():
			var pos: Vector2i = key
			if not _has_floor(pos.x, pos.y):
				_paint_floor_cell(pos, corridor_detail_chance)
				changed += 1
		var stair_changed_after: int = _fill_stair_step_voids()
		if changed == 0 and stair_changed_after == 0:
			return


func _in_map(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < _map_size_tiles.x and pos.y < _map_size_tiles.y


func _schedule_vertical_run_extension(col_x: int, y0: int, y1: int, to_fill: Dictionary) -> void:
	var p_up: Vector2i = Vector2i(col_x, y0 - 1)
	if _in_map(p_up) and not _has_floor(p_up.x, p_up.y):
		to_fill[p_up] = true
		return
	var p_down: Vector2i = Vector2i(col_x, y1 + 1)
	if _in_map(p_down) and not _has_floor(p_down.x, p_down.y):
		to_fill[p_down] = true


func _is_excluded_vertical_floor_height(run_len: int) -> bool:
	for value in excluded_vertical_floor_heights:
		if int(value) == run_len:
			return true
	return false


func _min_horizontal_wall_run_tiles() -> int:
	var image_count: int = max(1, min_wall_images)
	var texture_w: float = max(_wall_top_texture.get_width(), _wall_bottom_texture.get_width())
	var from_images: int = int(ceili(float(image_count) * texture_w / TILE_SIZE))
	return max(min_wall_run_tiles, from_images)


func _min_vertical_wall_run_tiles() -> int:
	# Ensure at least MIN_WALL_FRAMES images fit in the floor edge run.
	# This drives floor geometry validation/enforcement so walls never
	# appear with fewer than MIN_WALL_FRAMES frames in the actual world.
	var image_count: int = max(MIN_WALL_FRAMES, min_wall_images)
	var texture_h: float = _wall_vertical_texture.get_height()
	var from_images: int = int(ceili(float(image_count) * texture_h / TILE_SIZE))
	return max(min_wall_run_tiles, from_images)


func _validate_min_wall_edge_runs(min_horizontal_len: int, min_vertical_len: int) -> bool:
	var edges: Dictionary = _collect_exposed_wall_edges()
	var top_edges_by_row: Dictionary = edges["top"]
	var bottom_edges_by_row: Dictionary = edges["bottom"]
	var left_edges_by_col: Dictionary = edges["left"]
	var right_edges_by_col: Dictionary = edges["right"]

	for row_y in top_edges_by_row.keys():
		var xs: Array = top_edges_by_row[row_y]
		xs.sort()
		for run in _group_runs(xs):
			var x0: int = int(run[0])
			var x1: int = int(run[1])
			if (x1 - x0 + 1) < min_horizontal_len:
				return false

	for row_y in bottom_edges_by_row.keys():
		var xs: Array = bottom_edges_by_row[row_y]
		xs.sort()
		for run in _group_runs(xs):
			var x0: int = int(run[0])
			var x1: int = int(run[1])
			if (x1 - x0 + 1) < min_horizontal_len:
				return false

	for col_x in left_edges_by_col.keys():
		var ys: Array = left_edges_by_col[col_x]
		ys.sort()
		for run in _group_runs(ys):
			var y0: int = int(run[0])
			var y1: int = int(run[1])
			var run_len: int = y1 - y0 + 1
			if run_len < min_vertical_len or _is_excluded_vertical_floor_height(run_len):
				return false

	for col_x in right_edges_by_col.keys():
		var ys: Array = right_edges_by_col[col_x]
		ys.sort()
		for run in _group_runs(ys):
			var y0: int = int(run[0])
			var y1: int = int(run[1])
			var run_len: int = y1 - y0 + 1
			if run_len < min_vertical_len or _is_excluded_vertical_floor_height(run_len):
				return false

	return true


func _validate_min_floor_runs(min_len: int) -> bool:
	var rows: Dictionary = {}
	var cols: Dictionary = {}

	for key in _floor_cells.keys():
		var p: Vector2i = key
		if not rows.has(p.y):
			rows[p.y] = []
		(rows[p.y] as Array).append(p.x)

		if not cols.has(p.x):
			cols[p.x] = []
		(cols[p.x] as Array).append(p.y)

	for row_key in rows.keys():
		var xs: Array = rows[row_key]
		xs.sort()
		for run in _group_runs(xs):
			var x0: int = int(run[0])
			var x1: int = int(run[1])
			if (x1 - x0 + 1) < min_len:
				return false

	for col_key in cols.keys():
		var ys: Array = cols[col_key]
		ys.sort()
		for run in _group_runs(ys):
			var y0: int = int(run[0])
			var y1: int = int(run[1])
			if (y1 - y0 + 1) < min_len:
				return false

	return true


func _draw_strip(tex: Texture2D, dst: Rect2, flip_h: bool, tiled: bool) -> void:
	if flip_h:
		draw_set_transform(Vector2(dst.position.x + dst.size.x, dst.position.y), 0.0, Vector2(-1, 1))
	else:
		draw_set_transform(dst.position, 0.0, Vector2.ONE)
	draw_texture_rect(tex, Rect2(0, 0, dst.size.x, dst.size.y), tiled)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _collect_vertical_runs(edges_by_col: Dictionary) -> Array:
	var runs: Array = []
	var col_keys: Array = edges_by_col.keys()
	col_keys.sort()
	for col_key in col_keys:
		var col_x: int = int(col_key)
		var ys: Array = edges_by_col[col_key]
		ys.sort()
		for run in _group_runs(ys):
			runs.append(Vector3i(col_x, int(run[0]), int(run[1])))
	return runs


func _validate_required_resources() -> bool:
	var missing_core: Array[String] = []
	if _floor_texture == null:
		missing_core.append("res://assets/maps/floors/floors.png")
	if _wall_top_texture == null:
		missing_core.append("res://assets/maps/walls/top.png")
	if _wall_bottom_texture == null:
		missing_core.append("res://assets/maps/walls/bottom.png")
	if _wall_vertical_texture == null:
		missing_core.append("res://assets/maps/walls/vertical.png")

	if not missing_core.is_empty():
		_report_missing_resources("core map", missing_core)
		return false

	if use_corner_decor:
		var missing_corner: Array[String] = []
		if _wall_top_corner_texture == null:
			missing_corner.append("res://assets/maps/walls/outer-top-corner.png")
		if _wall_inner_bottom_corner_texture == null:
			missing_corner.append("res://assets/maps/walls/inner-top-corner.png")
		if _wall_outer_bottom_corner_texture == null:
			missing_corner.append("res://assets/maps/walls/outer-bottom-corner.png")
		if _wall_inner_top_corner_texture == null:
			missing_corner.append("res://assets/maps/walls/inner-bottom-corner.png")
		if not missing_corner.is_empty():
			_report_missing_resources("corner decor", missing_corner)
			use_corner_decor = false

	return true


func _report_missing_resources(group_name: String, paths: Array[String]) -> void:
	var message: String = "random_map missing " + group_name + " resources:"
	for path in paths:
		message += "\n- " + path
	message += "\nPlease add these files and tell me to retry."
	push_error(message)
	print(message)


func _center_camera() -> void:
	if _camera == null or _floor_cells.is_empty():
		return

	var zoom_value: float = max(0.01, camera_zoom_scale)
	_camera.zoom = Vector2(zoom_value, zoom_value)

	var breaker: Node2D = get_node_or_null("Breaker") as Node2D
	if breaker != null:
		if _camera.get_parent() != breaker:
			var old_parent: Node = _camera.get_parent()
			if old_parent != null:
				old_parent.remove_child(_camera)
			breaker.add_child(_camera)
		_camera.position = Vector2.ZERO
		return

	if _camera.get_parent() != self:
		var parent_node: Node = _camera.get_parent()
		if parent_node != null:
			parent_node.remove_child(_camera)
		add_child(_camera)

	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for key in _floor_cells.keys():
		var p: Vector2i = key
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	var base_x: float = map_origin_tiles.x * TILE_SIZE
	var base_y: float = map_origin_tiles.y * TILE_SIZE
	var left_px: float = base_x + min_x * TILE_SIZE
	var top_px: float = base_y + min_y * TILE_SIZE
	var right_px: float = base_x + (max_x + 1) * TILE_SIZE
	var bottom_px: float = base_y + (max_y + 1) * TILE_SIZE

	var max_left_pad: float = _wall_vertical_texture.get_width()
	var max_right_pad: float = _wall_vertical_texture.get_width()
	var max_top_pad: float = _wall_top_texture.get_height()
	var max_bottom_pad: float = _wall_bottom_texture.get_height()

	var bounds_left: float = left_px - max_left_pad
	var bounds_top: float = top_px - max_top_pad
	var bounds_right: float = right_px + max_right_pad
	var bounds_bottom: float = bottom_px + max_bottom_pad

	_camera.position = Vector2((bounds_left + bounds_right) * 0.5, (bounds_top + bounds_bottom) * 0.5)
