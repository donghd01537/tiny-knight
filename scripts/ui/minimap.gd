extends Control

const PANEL_W: float = 320.0
const PANEL_H: float = 180.0
const MARGIN: float = 14.0
const TILE_SIZE: float = 32.0
const INNER_PAD: float = 16.0
const FOLLOW_PX_PER_TILE: float = 2.4

const COL_BG: Color = Color(0.05, 0.05, 0.05, 0.60)
const COL_INNER_BG: Color = Color(0.03, 0.03, 0.03, 0.60)
const COL_FLOOR: Color = Color(0.70, 0.62, 0.48, 0.60)
const COL_EDGE: Color = Color(0.16, 0.14, 0.11, 1.0)
const COL_PLAYER: Color = Color(1.0, 0.9, 0.2, 1.0)
const DOT_RADIUS: float = 4.0

var _map: Node = null
var _player: Node2D = null

var _cached_floor_rect_count: int = -1
var _cached_floor_signature: int = -1

var _map_rects: Array[Rect2i] = []
var _floor_tiles: Dictionary = {} # Vector2i -> bool
var _map_origin_tiles: Vector2 = Vector2.ZERO
var _map_min_tile: Vector2 = Vector2.ZERO
var _map_max_tile: Vector2 = Vector2.ONE # exclusive


func _ready() -> void:
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -(PANEL_W + MARGIN)
	offset_top = MARGIN
	offset_right = -MARGIN
	offset_bottom = PANEL_H + MARGIN
	call_deferred("_find_nodes")


func _find_nodes() -> void:
	var maps: Array = get_tree().get_nodes_in_group("map")
	if maps.size() > 0:
		_map = maps[0]
		_refresh_map_cache(true)

	var heroes: Array = get_tree().get_nodes_in_group("player_hero")
	if heroes.size() > 0:
		_player = heroes[0]


func _process(_delta: float) -> void:
	_refresh_map_cache(false)
	queue_redraw()


func _refresh_map_cache(force: bool) -> void:
	if _map == null:
		return

	var rects_any: Array = _map.floor_rects
	var rect_count: int = rects_any.size()
	var sig: int = _calc_floor_signature(rects_any)
	if not force and rect_count == _cached_floor_rect_count and sig == _cached_floor_signature:
		return

	_map_rects.clear()
	_floor_tiles.clear()
	if rect_count == 0:
		_cached_floor_rect_count = 0
		_cached_floor_signature = 0
		_map_origin_tiles = Vector2.ZERO
		_map_min_tile = Vector2.ZERO
		_map_max_tile = Vector2.ONE
		return

	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for item in rects_any:
		var rect: Rect2i = item
		_map_rects.append(rect)
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			for x in range(rect.position.x, rect.position.x + rect.size.x):
				_floor_tiles[Vector2i(x, y)] = true
		min_x = min(min_x, rect.position.x)
		min_y = min(min_y, rect.position.y)
		max_x = max(max_x, rect.position.x + rect.size.x)
		max_y = max(max_y, rect.position.y + rect.size.y)

	_map_min_tile = Vector2(min_x, min_y)
	_map_max_tile = Vector2(max_x, max_y)
	_map_origin_tiles = _read_map_origin_tiles()
	_cached_floor_rect_count = rect_count
	_cached_floor_signature = sig


func _read_map_origin_tiles() -> Vector2:
	if _map == null:
		return Vector2.ZERO
	var value: Variant = _map.get("map_origin_tiles")
	match typeof(value):
		TYPE_VECTOR2I:
			return Vector2(value.x, value.y)
		TYPE_VECTOR2:
			return value
		_:
			return Vector2.ZERO


func _calc_floor_signature(rects: Array) -> int:
	var sig: int = rects.size() * 2654435761
	for item in rects:
		var rect: Rect2i = item
		sig = int(sig ^ (rect.position.x * 73856093))
		sig = int(sig ^ (rect.position.y * 19349663))
		sig = int(sig ^ (rect.size.x * 83492791))
		sig = int(sig ^ (rect.size.y * 15485863))
	return sig


func _player_tile_pos() -> Vector2:
	if _player == null:
		return (_map_min_tile + _map_max_tile) * 0.5

	var world_pos: Vector2 = _player.global_position
	if _map is Node2D:
		var map_node: Node2D = _map as Node2D
		var local_pos: Vector2 = map_node.to_local(world_pos)
		# floor_rects are already shifted by map_origin_tiles, so tile coords
		# here must match: pixel / TILE_SIZE gives the shifted tile index directly.
		return local_pos / TILE_SIZE

	return world_pos / TILE_SIZE


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, PANEL_W, PANEL_H), COL_BG)

	var inner: Rect2 = Rect2(INNER_PAD, INNER_PAD, PANEL_W - INNER_PAD * 2.0, PANEL_H - INNER_PAD * 2.0)
	draw_rect(inner, COL_INNER_BG)

	if _map_rects.is_empty():
		return

	var scale: float = max(0.5, FOLLOW_PX_PER_TILE)
	var view_tiles: Vector2 = Vector2(inner.size.x / scale, inner.size.y / scale)
	var map_span: Vector2 = _map_max_tile - _map_min_tile
	var half_view: Vector2 = view_tiles * 0.5
	var center_tile: Vector2 = _player_tile_pos()
	var view_min: Vector2 = center_tile - half_view

	if map_span.x > view_tiles.x:
		view_min.x = clampf(view_min.x, _map_min_tile.x, _map_max_tile.x - view_tiles.x)
	else:
		view_min.x = _map_min_tile.x - (view_tiles.x - map_span.x) * 0.5

	if map_span.y > view_tiles.y:
		view_min.y = clampf(view_min.y, _map_min_tile.y, _map_max_tile.y - view_tiles.y)
	else:
		view_min.y = _map_min_tile.y - (view_tiles.y - map_span.y) * 0.5

	for rect in _map_rects:
		var rx0: float = max(float(rect.position.x), view_min.x)
		var ry0: float = max(float(rect.position.y), view_min.y)
		var rx1: float = min(float(rect.position.x + rect.size.x), view_min.x + view_tiles.x)
		var ry1: float = min(float(rect.position.y + rect.size.y), view_min.y + view_tiles.y)
		if rx1 <= rx0 or ry1 <= ry0:
			continue

		var px0: float = inner.position.x + (rx0 - view_min.x) * scale
		var py0: float = inner.position.y + (ry0 - view_min.y) * scale
		var px1: float = inner.position.x + (rx1 - view_min.x) * scale
		var py1: float = inner.position.y + (ry1 - view_min.y) * scale

		# Use floating point coordinates directly to avoid rounded-pixel drift
		# which causes invisible half-pixel gaps (subpixel anti-aliasing artifacts)
		draw_rect(Rect2(px0, py0, px1 - px0, py1 - py0), COL_FLOOR)
	# Edge lines removed: they drew a noisy grid over the map tiles.

	var player_tile: Vector2 = _player_tile_pos()
	var player_px: float = inner.position.x + (player_tile.x - view_min.x) * scale
	var player_py: float = inner.position.y + (player_tile.y - view_min.y) * scale
	player_px = clampf(player_px, inner.position.x + DOT_RADIUS, inner.position.x + inner.size.x - DOT_RADIUS)
	player_py = clampf(player_py, inner.position.y + DOT_RADIUS, inner.position.y + inner.size.y - DOT_RADIUS)
	draw_circle(Vector2(player_px, player_py), DOT_RADIUS, COL_PLAYER)


func _draw_floor_edges(inner: Rect2, view_min: Vector2, view_tiles: Vector2, scale: float) -> void:
	if _floor_tiles.is_empty():
		return

	var min_tx: int = int(floor(view_min.x)) - 1
	var min_ty: int = int(floor(view_min.y)) - 1
	var max_tx: int = int(ceil(view_min.x + view_tiles.x)) + 1
	var max_ty: int = int(ceil(view_min.y + view_tiles.y)) + 1
	var thickness: float = max(1.0, scale * 0.15)

	for ty in range(min_ty, max_ty + 1):
		for tx in range(min_tx, max_tx + 1):
			var tile: Vector2i = Vector2i(tx, ty)
			if not _floor_tiles.has(tile):
				continue

			var x0: float = inner.position.x + (float(tx) - view_min.x) * scale
			var y0: float = inner.position.y + (float(ty) - view_min.y) * scale
			var x1: float = inner.position.x + (float(tx + 1) - view_min.x) * scale
			var y1: float = inner.position.y + (float(ty + 1) - view_min.y) * scale

			if not _floor_tiles.has(tile + Vector2i.UP):
				draw_line(Vector2(x0, y0), Vector2(x1, y0), COL_EDGE, thickness)
			if not _floor_tiles.has(tile + Vector2i.DOWN):
				draw_line(Vector2(x0, y1), Vector2(x1, y1), COL_EDGE, thickness)
			if not _floor_tiles.has(tile + Vector2i.LEFT):
				draw_line(Vector2(x0, y0), Vector2(x0, y1), COL_EDGE, thickness)
			if not _floor_tiles.has(tile + Vector2i.RIGHT):
				draw_line(Vector2(x1, y0), Vector2(x1, y1), COL_EDGE, thickness)
