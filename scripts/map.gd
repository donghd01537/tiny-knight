extends Node2D

const TILE_SIZE   := 32
const WALL_SCALE  := 0.6   # all wall sprites drawn at 60 % of their source size

const NUM_ROOMS   := 9
const MIN_ROOM_W  := 25
const MAX_ROOM_W  := 35
const MIN_ROOM_H  := 25
const MAX_ROOM_H  := 35
const ROOM_MARGIN := 5
const CORR_W      := 5
const WORLD_W     := 300
const WORLD_H     := 300

# Public — read by minimap.gd
var rooms: Array[Rect2i] = []      # bounding boxes (used for connectivity)
var corridors: Array[Rect2i] = []  # corridor segments
var floor_rects: Array[Rect2i] = [] # all actual floor rects (shapes + corridors)
var world_size := Vector2.ZERO

# Dungeon graph — read by other systems (doors, enemies, etc.)
var start_room_idx  := 0
var end_room_idx    := 0
var dead_end_idxs: Array[int] = []

var _room_shapes: Array = []        # Array of Array[Rect2i], one entry per room
var _texture: Texture2D
var _tex_top: Texture2D
var _tex_bottom: Texture2D
var _tex_vertical: Texture2D
var _tex_corner: Texture2D
var _tex_corner_tl: Texture2D
var _tile_frames: Dictionary = {}   # Vector2i → int (frame index)
var _strips_top:     Array = []
var _strips_bottom:  Array = []
var _strips_sides:   Array = []
var _strips_corners: Array = []   # drawn last, on top of everything


func _ready() -> void:
	add_to_group("map")
	_texture      = load("res://assets/maps/floors/floors.png")
	_tex_top      = load("res://assets/maps/walls/top.png")
	_tex_bottom   = load("res://assets/maps/walls/bottom.png")
	_tex_vertical = load("res://assets/maps/walls/vertical.png")
	_tex_corner    = load("res://assets/maps/walls/corner.png")
	_tex_corner_tl = load("res://assets/maps/walls/corner_TL.png")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_build_map()
	_place_breaker()
	_setup_camera()
	queue_redraw()


func _build_map() -> void:
	_room_shapes.clear()
	_tile_frames.clear()
	rooms     = _generate_rooms()   # also fills _room_shapes
	corridors = _connect_rooms(rooms)

	floor_rects.clear()
	for shape: Array in _room_shapes:
		floor_rects.append_array(shape)
	floor_rects.append_array(corridors)

	var max_x := 0
	var max_y := 0
	for rect: Rect2i in floor_rects:
		max_x = max(max_x, rect.position.x + rect.size.x + 2)
		max_y = max(max_y, rect.position.y + rect.size.y + 2)
	world_size = Vector2(max_x * TILE_SIZE, max_y * TILE_SIZE)

	for rect: Rect2i in floor_rects:
		_fill_rect(rect)
	_build_walls()


# ── Room generation ───────────────────────────────────────────────────────────

func _generate_rooms() -> Array[Rect2i]:
	var placed: Array[Rect2i] = []
	var attempts := 0
	while placed.size() < NUM_ROOMS and attempts < 2000:
		var w := randi_range(MIN_ROOM_W, MAX_ROOM_W)
		var h := randi_range(MIN_ROOM_H, MAX_ROOM_H)
		var x := randi_range(2, WORLD_W - w - 2)
		var y := randi_range(2, WORLD_H - h - 2)
		var candidate := Rect2i(x, y, w, h)
		var overlaps := false
		for p in placed:
			if candidate.grow(ROOM_MARGIN).intersects(p.grow(ROOM_MARGIN)):
				overlaps = true
				break
		if not overlaps:
			placed.append(candidate)
			_room_shapes.append(_make_room_shape(candidate))
		attempts += 1
	return placed


# ── Room shapes ───────────────────────────────────────────────────────────────
# All shapes are subsets of the bounding box so overlap detection stays valid.

func _make_room_shape(base: Rect2i) -> Array[Rect2i]:
	match randi() % 5:
		0, 1: return [base]           # 40 % plain rectangle
		2:    return _l_shape(base)   # 20 % L-shape
		3:    return _plus_shape(base) # 20 % plus / cross
		_:    return _t_shape(base)   # 20 % T-shape
	return [base]


# L-shape: two axis-aligned strips — one full-width, one partial
func _l_shape(base: Rect2i) -> Array[Rect2i]:
	var cx := base.position.x + base.size.x * randi_range(4, 6) / 10
	var cy := base.position.y + base.size.y * randi_range(4, 6) / 10
	match randi() % 4:
		0:  # full top + bottom-left arm
			return [
				Rect2i(base.position.x, base.position.y, base.size.x,           cy - base.position.y),
				Rect2i(base.position.x, cy,               cx - base.position.x,  base.end.y - cy),
			]
		1:  # full top + bottom-right arm
			return [
				Rect2i(base.position.x, base.position.y, base.size.x,      cy - base.position.y),
				Rect2i(cx,              cy,               base.end.x - cx,  base.end.y - cy),
			]
		2:  # top-left arm + full bottom
			return [
				Rect2i(base.position.x, base.position.y, cx - base.position.x,  cy - base.position.y),
				Rect2i(base.position.x, cy,               base.size.x,           base.end.y - cy),
			]
		_:  # top-right arm + full bottom
			return [
				Rect2i(cx,              base.position.y,  base.end.x - cx,  cy - base.position.y),
				Rect2i(base.position.x, cy,               base.size.x,      base.end.y - cy),
			]


# Plus / cross: a horizontal bar and a vertical bar crossing at the centre
func _plus_shape(base: Rect2i) -> Array[Rect2i]:
	var bw: int = max(8, base.size.x / 3)
	var bh: int = max(8, base.size.y / 3)
	return [
		Rect2i(base.position.x,                      base.position.y + (base.size.y - bh) / 2, base.size.x, bh),
		Rect2i(base.position.x + (base.size.x - bw) / 2, base.position.y,                      bw, base.size.y),
	]


# T-shape: a wide bar along one edge + a narrower stem through the middle
func _t_shape(base: Rect2i) -> Array[Rect2i]:
	var half_w: int = max(8, base.size.x / 2)
	var half_h: int = max(8, base.size.y / 2)
	match randi() % 4:
		0:  # bar on top, stem downward
			return [
				Rect2i(base.position.x,                              base.position.y,  base.size.x, half_h),
				Rect2i(base.position.x + (base.size.x - half_w) / 2, base.position.y,  half_w,      base.size.y),
			]
		1:  # bar on bottom, stem upward
			return [
				Rect2i(base.position.x,                              base.end.y - half_h, base.size.x, half_h),
				Rect2i(base.position.x + (base.size.x - half_w) / 2, base.position.y,     half_w,      base.size.y),
			]
		2:  # bar on left, stem rightward
			return [
				Rect2i(base.position.x,  base.position.y,                              half_w, base.size.y),
				Rect2i(base.position.x,  base.position.y + (base.size.y - half_h) / 2, base.size.x, half_h),
			]
		_:  # bar on right, stem leftward
			return [
				Rect2i(base.end.x - half_w, base.position.y,                              half_w, base.size.y),
				Rect2i(base.position.x,      base.position.y + (base.size.y - half_h) / 2, base.size.x, half_h),
			]


# ── Connectivity — pure Prim's MST, no extra loops ───────────────────────────
# After building the tree we classify every room by its degree:
#   degree 1 → dead end   (exactly one neighbour)
#   degree 2 → corridor   (pass-through)
#   degree 3+ → junction
# start_room_idx = 0 (first placed room).
# end_room_idx   = dead-end leaf farthest from start (BFS hop-count).
# dead_end_idxs  = all leaves including start & end.

func _connect_rooms(room_list: Array[Rect2i]) -> Array[Rect2i]:
	if room_list.size() < 2:
		return []

	var corr_list: Array[Rect2i] = []
	var adj: Dictionary = {}
	for i in room_list.size():
		adj[i] = []

	# Prim's MST
	var in_tree: Array[bool] = []
	in_tree.resize(room_list.size())
	in_tree.fill(false)
	in_tree[0] = true
	var in_count := 1

	while in_count < room_list.size():
		var best_dist := INF
		var best_from := -1
		var best_to   := -1
		for i in room_list.size():
			if not in_tree[i]: continue
			for j in room_list.size():
				if in_tree[j]: continue
				var d := _shape_center(i).distance_to(_shape_center(j))
				if d < best_dist:
					best_dist = d; best_from = i; best_to = j
		if best_to == -1: break
		corr_list.append_array(_l_corridor_pt(_shape_center(best_from), _shape_center(best_to)))
		(adj[best_from] as Array).append(best_to)
		(adj[best_to]   as Array).append(best_from)
		in_tree[best_to] = true
		in_count += 1

	dead_end_idxs.clear()
	for i in room_list.size():
		if (adj[i] as Array).size() == 1:
			dead_end_idxs.append(i)

	start_room_idx = 0
	end_room_idx = _bfs_farthest_leaf(adj, room_list.size(), start_room_idx, dead_end_idxs)

	return corr_list


## BFS from `start`. Returns the leaf in `leaves` with the greatest hop distance.
func _bfs_farthest_leaf(adj: Dictionary, n: int, start: int, leaves: Array[int]) -> int:
	var dist: Array[int] = []
	dist.resize(n)
	dist.fill(-1)
	dist[start] = 0

	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb: int in (adj[cur] as Array):
			if dist[nb] == -1:
				dist[nb] = dist[cur] + 1
				queue.append(nb)

	var best_idx := start
	var best_d   := -1
	for leaf: int in leaves:
		if leaf == start:
			continue
		if dist[leaf] > best_d:
			best_d   = dist[leaf]
			best_idx = leaf
	return best_idx


func _center(room: Rect2i) -> Vector2:
	return Vector2(room.position.x + room.size.x * 0.5,
				   room.position.y + room.size.y * 0.5)


## Returns the center of the largest rect in the room's actual shape.
## Avoids connecting corridors to void areas inside L/T/plus shaped rooms.
func _shape_center(room_idx: int) -> Vector2:
	var shape: Array = _room_shapes[room_idx]
	var largest: Rect2i = shape[0]
	for r: Rect2i in shape:
		if r.get_area() > largest.get_area():
			largest = r
	return Vector2(largest.position.x + largest.size.x * 0.5,
				   largest.position.y + largest.size.y * 0.5)


func _l_corridor_pt(ac: Vector2, bc: Vector2) -> Array[Rect2i]:
	var ai := Vector2i(int(ac.x), int(ac.y))
	var bi := Vector2i(int(bc.x), int(bc.y))
	var half := CORR_W / 2
	var dy: int = absi(bi.y - ai.y)
	var dx: int = absi(bi.x - ai.x)
	# If vertical difference is too small, go straight horizontally to avoid tiny wall stubs
	if dy < CORR_W * 2:
		var mid_y := (ai.y + bi.y) / 2
		return [Rect2i(min(ai.x, bi.x), mid_y - half, dx + CORR_W, CORR_W)]
	# If horizontal difference is too small, go straight vertically
	if dx < CORR_W * 2:
		var mid_x := (ai.x + bi.x) / 2
		return [Rect2i(mid_x - half, min(ai.y, bi.y), CORR_W, dy + CORR_W)]
	if randf() < 0.5:
		return [
			Rect2i(min(ai.x, bi.x), ai.y - half, dx + CORR_W, CORR_W),
			Rect2i(bi.x - half, min(ai.y, bi.y), CORR_W, dy + CORR_W),
		]
	return [
		Rect2i(ai.x - half, min(ai.y, bi.y), CORR_W, dy + CORR_W),
		Rect2i(min(ai.x, bi.x), bi.y - half, dx + CORR_W, CORR_W),
	]


# ── Tile fill & draw ──────────────────────────────────────────────────────────
# Frame rules:
#   index 0   → base floor (default everywhere)
#   index 1-3 → detail tiles, always stamped in 2×2 / 3×3 / 4×4 clusters
#               scattered randomly across the whole rect (center included)

func _fill_rect(rect: Rect2i) -> void:
	# Pass 1: flood with frame 0, skipping tiles already owned by another rect
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if not _tile_frames.has(pos):
				_tile_frames[pos] = 0

	# Pass 2: stamp random clusters of detail tiles (frame 1-3)
	var num_clusters: int = max(1, (rect.size.x * rect.size.y) / 80)
	for _i in num_clusters:
		var cs := randi_range(2, 4)          # cluster side: 2, 3, or 4 tiles
		var cx := randi_range(rect.position.x, rect.end.x - cs)
		var cy := randi_range(rect.position.y, rect.end.y - cs)
		for dy in cs:
			for dx in cs:
				_tile_frames[Vector2i(cx + dx, cy + dy)] = randi_range(1, 3)


func _build_walls() -> void:
	_strips_top.clear()
	_strips_bottom.clear()
	_strips_sides.clear()
	_strips_corners.clear()

	# Scan every floor tile; collect exposed edges grouped into runs.
	# A wall only appears where floor meets void — never across open floor.
	var top_by_row:    Dictionary = {}  # row_y → Array[int] x-coords
	var bottom_by_row: Dictionary = {}
	var left_by_col:   Dictionary = {}  # col_x → Array[int] y-coords
	var right_by_col:  Dictionary = {}

	for key in _tile_frames:
		var pos: Vector2i = key
		var x := pos.x
		var y := pos.y
		if not _tile_frames.has(Vector2i(x, y - 1)):
			if not top_by_row.has(y):    top_by_row[y]    = []
			(top_by_row[y]    as Array).append(x)
		if not _tile_frames.has(Vector2i(x, y + 1)):
			if not bottom_by_row.has(y): bottom_by_row[y] = []
			(bottom_by_row[y] as Array).append(x)
		if not _tile_frames.has(Vector2i(x - 1, y)):
			if not left_by_col.has(x):   left_by_col[x]   = []
			(left_by_col[x]   as Array).append(y)
		if not _tile_frames.has(Vector2i(x + 1, y)):
			if not right_by_col.has(x):  right_by_col[x]  = []
			(right_by_col[x]  as Array).append(y)

	for row_y in top_by_row:
		var xs: Array = top_by_row[row_y];  xs.sort()
		for run in _group_runs(xs):
			_draw_top_wall(run[0], run[1], row_y)
	for row_y in bottom_by_row:
		var xs: Array = bottom_by_row[row_y];  xs.sort()
		for run in _group_runs(xs):
			_draw_bottom_wall(run[0], run[1], row_y)
	for col_x in left_by_col:
		var ys: Array = left_by_col[col_x];  ys.sort()
		for run in _group_runs(ys):
			_draw_left_wall(col_x, run[0], run[1])
	for col_x in right_by_col:
		var ys: Array = right_by_col[col_x];  ys.sort()
		for run in _group_runs(ys):
			_draw_right_wall(col_x, run[0], run[1])

	# Corner scan — bottom-left only (no flip).
	# Requires at least 3 tiles of wall in each direction.
	var cw: float = _tex_corner.get_width()
	var ch: float = _tex_corner.get_height()
	var min_h_tiles: int = max(5, ceili(cw / TILE_SIZE))
	var min_v_tiles: int = max(5, ceili(ch / TILE_SIZE))
	var tr_w: float = _tex_corner_tl.get_width()
	var tr_h: float = _tex_corner_tl.get_height()
	var min_h_tr: int = max(5, ceili(tr_w / TILE_SIZE))
	var min_v_tr: int = max(5, ceili(tr_h / TILE_SIZE))
	for key in _tile_frames:
		var pos: Vector2i = key
		var x := pos.x;  var y := pos.y
		var fx := float(x * TILE_SIZE);  var fy := float(y * TILE_SIZE)
		var lw := not _tile_frames.has(Vector2i(x - 1, y))
		var rw := not _tile_frames.has(Vector2i(x + 1, y))
		var bw := not _tile_frames.has(Vector2i(x, y + 1))
		var aw := not _tile_frames.has(Vector2i(x, y - 1))
		# Convex bottom-left: outer corner (void left AND void below)
		if lw and bw:
			var v_ok := true
			for dy in min_v_tiles:
				if not _tile_frames.has(Vector2i(x, y - dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x - 1, y - dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tiles:
				if not _tile_frames.has(Vector2i(x + dx, y)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner, Rect2(fx - cw * 0.5 + 13, fy + TILE_SIZE - ch * 0.5 + 1, cw, ch), false])
		# Concave bottom-left: left wall ends here; wider section below extends left
		if lw and _tile_frames.has(Vector2i(x, y + 1)) and _tile_frames.has(Vector2i(x - 1, y + 1)):
			var v_ok := true
			for dy in min_v_tiles:
				if not _tile_frames.has(Vector2i(x, y - dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x - 1, y - dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tiles:
				if not _tile_frames.has(Vector2i(x + dx, y + 1)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner, Rect2(fx - cw * 0.5 + 13 - 60 - 35, fy + TILE_SIZE - ch * 0.5 + 1 - 60 - 37, cw, ch), true])
		# Convex bottom-right: outer corner (void right AND void below)
		if rw and bw:
			var v_ok := true
			for dy in min_v_tiles:
				if not _tile_frames.has(Vector2i(x, y - dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x + 1, y - dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tiles:
				if not _tile_frames.has(Vector2i(x - dx, y)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner, Rect2(fx + TILE_SIZE - cw * 0.5 - 13, fy + TILE_SIZE - ch * 0.5 + 1, cw, ch), true])
		# Concave bottom-right: right wall ends here; wider section below extends right
		if rw and _tile_frames.has(Vector2i(x, y + 1)) and _tile_frames.has(Vector2i(x + 1, y + 1)):
			var v_ok := true
			for dy in min_v_tiles:
				if not _tile_frames.has(Vector2i(x, y - dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x + 1, y - dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tiles:
				if not _tile_frames.has(Vector2i(x - dx, y + 1)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner, Rect2(fx + TILE_SIZE - cw * 0.5 - 13 + 60 - 35 + 70, fy + TILE_SIZE - ch * 0.5 + 1 - 60 - 36, cw, ch), false])
		# Convex top-left: outer corner (void left AND void above)
		if lw and aw:
			var v_ok := true
			for dy in min_v_tr:
				if not _tile_frames.has(Vector2i(x, y + dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x - 1, y + dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tr:
				if not _tile_frames.has(Vector2i(x + dx, y)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner_tl, Rect2(fx - tr_w * 0.5 + 13, fy - tr_h * 0.5 + 1, tr_w, tr_h), false])
		# Convex top-right: outer corner (void right AND void above)
		if rw and aw:
			var v_ok := true
			for dy in min_v_tr:
				if not _tile_frames.has(Vector2i(x, y + dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x + 1, y + dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tr:
				if not _tile_frames.has(Vector2i(x - dx, y)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner_tl, Rect2(fx + TILE_SIZE - tr_w * 0.5 - 13, fy - tr_h * 0.5 + 1, tr_w, tr_h), true])
		# Concave top-left: mirrors concave BL offsets, flip_h=false
		if lw and _tile_frames.has(Vector2i(x, y - 1)) and _tile_frames.has(Vector2i(x - 1, y - 1)):
			var v_ok := true
			for dy in min_v_tr:
				if not _tile_frames.has(Vector2i(x, y + dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x - 1, y + dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tr:
				if not _tile_frames.has(Vector2i(x + dx, y)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner_tl, Rect2(fx - tr_w * 0.5 + 13 - 60 - 35, fy - tr_h * 0.5 + 1, tr_w, tr_h), true])
		# Concave top-right: mirrors concave BR offsets, flip_h=true
		if rw and _tile_frames.has(Vector2i(x, y - 1)) and _tile_frames.has(Vector2i(x + 1, y - 1)):
			var v_ok := true
			for dy in min_v_tr:
				if not _tile_frames.has(Vector2i(x, y + dy)): v_ok = false; break
				if dy > 0 and _tile_frames.has(Vector2i(x + 1, y + dy)): v_ok = false; break
			var h_ok := true
			for dx in min_h_tr:
				if not _tile_frames.has(Vector2i(x - dx, y)): h_ok = false; break
			if v_ok and h_ok:
				_strips_corners.append([_tex_corner_tl, Rect2(fx + TILE_SIZE - tr_w * 0.5 - 13 + 60 - 35 + 70, fy - tr_h * 0.5 + 1, tr_w, tr_h), false])


## Groups a sorted int array into consecutive runs → [[start, end], …]
func _group_runs(arr: Array) -> Array:
	var runs: Array = []
	if arr.is_empty():
		return runs
	var s: int = arr[0]
	var e: int = arr[0]
	for i in range(1, arr.size()):
		if arr[i] == e + 1:
			e = arr[i]
		else:
			runs.append([s, e])
			s = arr[i];  e = arr[i]
	runs.append([s, e])
	return runs


func _draw_top_wall(x0: int, x1: int, row_y: int) -> void:
	var th_s: float = _tex_top.get_height()
	var tw_s: float = _tex_top.get_width()
	var rx:   float = x0 * TILE_SIZE
	var ry:   float = row_y * TILE_SIZE
	var rw:   float = (x1 - x0 + 1) * TILE_SIZE
	var hw:   float = ceili((rw * 0.5) / tw_s) * tw_s
	_strips_top.append([_tex_top, Rect2(rx,           ry - th_s, hw, th_s), false, true])
	_strips_top.append([_tex_top, Rect2(rx + rw - hw, ry - th_s, hw, th_s), true,  true])


func _draw_bottom_wall(x0: int, x1: int, row_y: int) -> void:
	var bh_s: float = _tex_bottom.get_height()
	var bw_s: float = _tex_bottom.get_width()
	var rx:   float = x0 * TILE_SIZE
	var by:   float = (row_y + 1) * TILE_SIZE
	var rw:   float = (x1 - x0 + 1) * TILE_SIZE
	var hw:   float = ceili((rw * 0.5) / bw_s) * bw_s
	_strips_bottom.append([_tex_bottom, Rect2(rx,           by, hw, bh_s), false, true])
	_strips_bottom.append([_tex_bottom, Rect2(rx + rw - hw, by, hw, bh_s), true,  true])


func _draw_left_wall(col_x: int, y0: int, y1: int) -> void:
	var vw_s: float = _tex_vertical.get_width()
	var vh_s: float = _tex_vertical.get_height()
	var rx:   float = col_x * TILE_SIZE
	var vy_start: float = y0 * TILE_SIZE
	var vy_end:   float = (y1 + 1) * TILE_SIZE
	var total_h:  float = vy_end - vy_start
	var n: int = int(total_h / vh_s)
	var rem: float = total_h - n * vh_s
	for i in n:
		_strips_sides.append([_tex_vertical, Rect2(rx - vw_s, vy_start + i * vh_s, vw_s, vh_s), false, false])
	if rem > 0.01:
		_strips_sides.append([_tex_vertical, Rect2(rx - vw_s, vy_start + n * vh_s, vw_s, rem), false, false])


func _draw_right_wall(col_x: int, y0: int, y1: int) -> void:
	var vw_s: float = _tex_vertical.get_width()
	var vh_s: float = _tex_vertical.get_height()
	var rx:   float = col_x * TILE_SIZE
	var vy_start: float = y0 * TILE_SIZE
	var vy_end:   float = (y1 + 1) * TILE_SIZE
	var total_h:  float = vy_end - vy_start
	var n: int = int(total_h / vh_s)
	var rem: float = total_h - n * vh_s
	for i in n:
		_strips_sides.append([_tex_vertical, Rect2(rx + TILE_SIZE, vy_start + i * vh_s, vw_s, vh_s), true, false])
	if rem > 0.01:
		_strips_sides.append([_tex_vertical, Rect2(rx + TILE_SIZE, vy_start + n * vh_s, vw_s, rem), true, false])


func _draw() -> void:
	# ── Floors first (walls draw on top — walls define the map) ───────────
	for pos: Vector2i in _tile_frames:
		var src := Rect2((_tile_frames[pos] as int) * TILE_SIZE, 0, TILE_SIZE, TILE_SIZE)
		var dst := Rect2(pos.x * TILE_SIZE, pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
		draw_texture_rect_region(_texture, dst, src)

	# ── Walls on top — tops → bottoms → sides → corners (corners always in front)
	for strip in _strips_top:
		_draw_strip(strip)
	for strip in _strips_bottom:
		_draw_strip(strip)
	for strip in _strips_sides:
		_draw_strip(strip)
	for strip in _strips_corners:
		_draw_corner(strip)


func _draw_strip(strip: Array) -> void:
	var tex:    Texture2D = strip[0]
	var dst:    Rect2     = strip[1]
	var flip_h: bool      = strip[2]
	var tiled:  bool      = strip[3]
	if flip_h:
		draw_set_transform(Vector2(dst.position.x + dst.size.x, dst.position.y), 0.0, Vector2(-1.0, 1.0))
	else:
		draw_set_transform(dst.position, 0.0, Vector2.ONE)
	draw_texture_rect(tex, Rect2(0, 0, dst.size.x, dst.size.y), tiled)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_corner(strip: Array) -> void:
	var tex:    Texture2D = strip[0]
	var dst:    Rect2     = strip[1]
	var flip_h: bool      = strip[2]
	if flip_h:
		draw_set_transform(Vector2(dst.position.x + dst.size.x, dst.position.y), 0.0, Vector2(-1.0, 1.0))
	else:
		draw_set_transform(dst.position, 0.0, Vector2.ONE)
	draw_texture_rect(tex, Rect2(0, 0, dst.size.x, dst.size.y), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ── Scene setup ───────────────────────────────────────────────────────────────

func _place_breaker() -> void:
	if _room_shapes.is_empty():
		return
	var breaker := get_node_or_null("Breaker")
	if not breaker:
		return
	# Spawn at centre of the first sub-rect of the start room
	# so Breaker always lands on tiles, even for L/T/plus shapes.
	var start_shape: Array = _room_shapes[start_room_idx]
	var start_rect: Rect2i = start_shape[0]
	breaker.position = Vector2(
		(start_rect.position.x + start_rect.size.x * 0.5) * TILE_SIZE,
		(start_rect.position.y + start_rect.size.y * 0.5) * TILE_SIZE
	)


func _setup_camera() -> void:
	var cam := Camera2D.new()
	var breaker := get_node_or_null("Breaker")
	if breaker:
		breaker.add_child(cam)
	else:
		cam.position = world_size * 0.5
		add_child(cam)
