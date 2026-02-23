extends Node2D
## Bounce Effect — reusable skill effect that grows like a beam from caster to target
## Beam extends from origin → target (progress bar style), deals damage, bounces to next
## Configure via initialize() with texture, damage, bounces, fps

signal finished

var _texture: Texture2D
var _frames: Array = []
var _frame := 0
var _total_frames := 0
var _timer := 0.0
var _fps := 12.0
var _playing := false
var _frame_width := 0  ## Width of a single animation frame

var _base_damage := 5
var _damage_per_bounce := 1
var _max_bounces := 4
var _current_bounce := 0
var _hit_enemies: Array = []
var _current_target: Node2D = null
var _hit_texture_path: String = ""
var _max_bounce_range := 250.0  ## Max distance for bounce targets

const HitEffectScene := preload("res://scenes/effects/HitEffect.tscn")

# Beam growth state
var _flying := false
var _fill_speed := 800.0  ## Pixels per second the beam extends
var _fly_origin := Vector2.ZERO
var _fly_target_pos := Vector2.ZERO
var _fly_distance := 0.0
var _fly_progress := 0.0  ## 0.0 to 1.0
var _frame_height := 0

@onready var sprite: Sprite2D = $Sprite


func initialize(texture_path: String, base_damage: int, damage_per_bounce: int, max_bounces: int, fps: float = 12.0, hit_texture_path: String = "", frame_width: int = 256) -> void:
	_base_damage = base_damage
	_damage_per_bounce = damage_per_bounce
	_max_bounces = max_bounces
	_fps = fps
	_hit_texture_path = hit_texture_path
	_texture = load(texture_path) as Texture2D
	if _texture:
		_frame_height = int(_texture.get_height())
		_frame_width = frame_width
		var img_w := int(_texture.get_width())
		_total_frames = img_w / _frame_width if _frame_width > 0 else 0
		for i in _total_frames:
			_frames.append(Rect2i(i * _frame_width, 0, _frame_width, _frame_height))


func start(first_target: Node2D) -> void:
	_current_bounce = 0
	_hit_enemies.clear()
	visible = true
	z_index = 100
	_fly_to_target(first_target)


func _fly_to_target(target: Node2D) -> void:
	if not is_instance_valid(target):
		_finish()
		return

	_current_target = target
	_hit_enemies.append(target)
	_fly_origin = global_position
	_fly_target_pos = target.global_position
	_fly_distance = _fly_origin.distance_to(_fly_target_pos)
	_fly_progress = 0.0
	_frame = 0
	_timer = 0.0
	_flying = true
	_playing = false

	# Rotate sprite to face target
	var dir := (_fly_target_pos - _fly_origin).normalized()
	sprite.rotation = dir.angle()

	_apply_beam_frame(0, 0.01)


func _arrive_at_target() -> void:
	_flying = false

	# Move node to target for bounce origin
	if is_instance_valid(_current_target):
		global_position = _current_target.global_position

	_on_strike_done()


func _on_strike_done() -> void:
	# Deal damage
	if is_instance_valid(_current_target):
		var combatant := _current_target.get_node_or_null("Combatant") as Combatant
		if combatant and not combatant.is_dead:
			var damage := _base_damage + _current_bounce * _damage_per_bounce
			combatant.take_damage(damage)
			_spawn_hit_effect(_current_target.global_position)

	_current_bounce += 1

	# Try to bounce to next enemy
	if _current_bounce < _max_bounces:
		var next := _find_nearest_enemy()
		if next:
			_fly_to_target(next)
			return

	_finish()


func _spawn_hit_effect(pos: Vector2) -> void:
	if _hit_texture_path.is_empty():
		return
	var hit := HitEffectScene.instantiate()
	get_parent().add_child(hit)
	hit.global_position = pos
	hit.initialize(_hit_texture_path)


func _find_nearest_enemy() -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := INF

	for enemy in enemies:
		if not enemy is Node2D:
			continue
		if enemy in _hit_enemies:
			continue
		var enemy_combatant := enemy.get_node_or_null("Combatant") as Combatant
		if not enemy_combatant or enemy_combatant.is_dead:
			continue

		var dist := global_position.distance_to(enemy.global_position)
		if dist > _max_bounce_range:
			continue
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest


func _finish() -> void:
	_playing = false
	_flying = false
	finished.emit()
	queue_free()


## Apply one animation frame, tiled across beam length (progress bar)
## progress = 0.0→1.0 where 1.0 = full distance to enemy
func _apply_beam_frame(frame_idx: int, progress: float) -> void:
	if not _texture or _frame_width <= 0 or _frame_height <= 0:
		return
	if frame_idx >= _frames.size():
		frame_idx = 0
	var region: Rect2i = _frames[frame_idx]

	# Set one animation frame as atlas texture
	var atlas := AtlasTexture.new()
	atlas.atlas = _texture
	atlas.region = Rect2(region.position.x, region.position.y, _frame_width, _frame_height)
	atlas.filter_clip = true
	sprite.texture = atlas

	# Beam length in pixels = distance * progress
	var beam_length := maxf(1.0, _fly_distance * clampf(progress, 0.01, 1.0))

	# Tile the frame across the beam length using region
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, beam_length, _frame_height)
	sprite.centered = false
	sprite.scale = Vector2.ONE
	sprite.offset = Vector2(0, -_frame_height * 0.5)


func _process(delta: float) -> void:
	if _flying:
		# Update target position if target is moving
		if is_instance_valid(_current_target):
			_fly_target_pos = _current_target.global_position
			_fly_distance = _fly_origin.distance_to(_fly_target_pos)

		# Grow progress: 0% to 100% of distance at _fill_speed px/sec
		if _fly_distance > 0.0:
			_fly_progress += (_fill_speed * delta) / _fly_distance
		else:
			_fly_progress = 1.0
		_fly_progress = clampf(_fly_progress, 0.0, 1.0)

		# Rotate toward target
		var dir := (_fly_target_pos - _fly_origin).normalized()
		sprite.rotation = dir.angle()

		# Animate through frames
		_timer += delta
		if _timer >= 1.0 / _fps and _total_frames > 1:
			_timer -= 1.0 / _fps
			_frame = (_frame + 1) % _total_frames

		# Apply current frame clipped to progress
		_apply_beam_frame(_frame, _fly_progress)

		# Beam fully extended = arrived
		if _fly_progress >= 1.0:
			_arrive_at_target()
		return

	# Strike animation phase
	if not _playing or _total_frames == 0:
		return

	_timer += delta
	if _timer >= 1.0 / _fps:
		_timer -= 1.0 / _fps
		_frame += 1
		if _frame >= _total_frames:
			_playing = false
			_on_strike_done()
			return
		_apply_beam_frame(_frame, 1.0)
