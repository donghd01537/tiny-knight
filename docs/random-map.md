# Random Map Instructions

## 1) Scope
- Scene: `res://scenes/world/random_map.tscn`
- Script: `res://scripts/random_map.gd`
- This is a standalone map scene. It does not depend on `scripts/map.gd` generation logic.

## 2) Required scene nodes
- Root `Node2D` with `random_map.gd`.
- Child `Breaker` (player actor).
- Child `Camera2D`.
- Child `PlayerHUD` (optional but present in current scene).
- Child `MiniMapHUD/MiniMap` with `res://scripts/ui/minimap.gd`.

## 3) Required assets
Core assets (must exist, or generation stops):
- `res://assets/maps/floors/floors.png`
- `res://assets/maps/walls/top.png`
- `res://assets/maps/walls/bottom.png`
- `res://assets/maps/walls/vertical.png`

Corner decor assets (optional, only used when `use_corner_decor = true`):
- `res://assets/maps/walls/outer-top-corner.png`
- `res://assets/maps/walls/inner-top-corner.png`
- `res://assets/maps/walls/outer-bottom-corner.png`
- `res://assets/maps/walls/inner-bottom-corner.png`

If corner files are missing:
- Script prints missing paths.
- `use_corner_decor` is auto-disabled.
- Core map still renders.

## 4) How generation works (current logic)
1. Build room list (`min_room_count..max_room_count`) with non-overlap spacing.
2. Build MST room links from room centers (`_build_room_mst_links`).
3. Paint each room floor.
4. Add random room-side bumps, but skip sides used by room connections.
5. Carve stable center-to-center corridors (deterministic L-shape).
6. Draw walls from exposed floor edges.
7. Draw corner decor (if enabled and assets exist).
8. Draw floor tiles.

Important current rule:
- Room shape bumps are applied to room borders only.
- Sides that connect to other rooms are blocked from bumping to keep ways clean.

## 5) Wall drawing order and layering
In `_draw()`:
1. `_draw_walls_from_floor_edges()`
2. `_draw_corner_decors()`
3. `_draw_floor_tiles()`

Inside `_draw_walls_from_floor_edges()` order is:
1. Top runs
2. Left and right vertical runs
3. Bottom runs

This gives front/back priority like:
- Bottom > Vertical > Top

## 6) Runtime controls
- Press `ui_accept` (Enter by default) to regenerate map.
- On regenerate, script also:
  - logs floor frame usage,
  - rebuilds minimap data (`floor_rects`, `world_size`),
  - repositions breaker to a random room center,
  - recenters camera.

## 7) Main tuning exports (Inspector)
World and room sizing:
- `min_map_width`, `max_map_width`
- `min_map_height`, `max_map_height`
- `min_room_count`, `max_room_count`
- `min_room_width`, `max_room_width`
- `min_room_height`, `max_room_height`
- `room_size_scale`
- `room_spacing_tiles`

Corridor and wall constraints:
- `corridor_width_tiles`
- `min_floor_block_tiles`
- `min_connection_segment_tiles`
- `min_wall_run_tiles`
- `min_wall_images`
- `preferred_wall_run_tiles`
- `excluded_vertical_floor_heights` (example default excludes 11)

Rendering placement and visuals:
- `map_origin_tiles`
- `floor_detail_chance`
- `corridor_detail_chance`
- `camera_zoom_scale`
- `wall_overlap_px`
- `side_wall_inset_px`
- `side_wall_outward_nudge_px`
- `side_wall_top_overlap_ratio`
- `side_wall_extra_lift_px`
- `side_wall_trim_frames`
- `use_corner_decor`

## 8) Minimap contract
`minimap.gd` reads map data from the node in group `map`:
- `floor_rects: Array[Rect2i]`
- `world_size: Vector2`
- `map_origin_tiles`

`random_map.gd` publishes this through `_rebuild_public_map_data()`.

## 9) Recommended baseline values
If you need a stable default start point:
- `min_room_count = 5`
- `max_room_count = 7`
- `room_size_scale = 1.5`
- `corridor_width_tiles = 4`
- `min_connection_segment_tiles = 6`
- `min_wall_run_tiles = 7`
- `min_wall_images = 5`
- `camera_zoom_scale = 1.0`
- `side_wall_extra_lift_px = 8.0`

## 10) Troubleshooting
`Cannot call method on null` (texture errors):
- Check exact asset paths above.
- Core missing assets must be fixed first.

Corners look wrong or too noisy:
- Temporarily set `use_corner_decor = false`.
- Recheck corner png dimensions and alignment.

Corridors or room connections look unstable:
- Increase `min_connection_segment_tiles`.
- Increase `room_spacing_tiles`.
- Keep `room_size_scale` moderate to reduce extreme overlaps.

Walls look too short:
- Increase `min_wall_images`.
- Increase `min_wall_run_tiles`.
- Tune `side_wall_extra_lift_px`.
