class_name ChainLightningSkill
extends Skill
## Chain Lightning — beam grows from character (0%) to target (100%) like a progress bar.
## lightning.png is scaled to span the actual distance, then revealed left→right via region_rect.
## Each bounce leaves the segment visible. Damage increases per bounce. Does NOT return.

const SKILL_RANGE       := 250.0
const BOUNCE_RANGE      := 180.0
const MAX_BOUNCES       := 3
const DAMAGE_PER_BOUNCE := 0.5   # multiplier added each bounce (×1.0, ×1.5, ×2.0…)
const FILL_SPEED        := 900.0  # px/s — how fast the beam extends
const ANIM_FPS          := 12.0
const FRAME_WIDTH       := 256    # width of one animation frame in the sprite sheet

const LIGHTNING_TEXTURE := "res://assets/sprites/skills/lightning.png"

var _owner_node: Node2D = null
var _combatant: Combatant = null

var _tex: Texture2D = null
var _active_sprite: Sprite2D = null   # currently growing beam segment
var _done_sprites: Array = []         # completed segments (stay visible until skill ends)

var _frame: int = 0
var _frame_count: int = 0
var _anim_timer: float = 0.0

var _src_pos: Vector2 = Vector2.ZERO
var _dst_pos: Vector2 = Vector2.ZERO
var _progress: float = 0.0            # 0.0 → 1.0 for current segment

var _current_target: Node2D = null
var _bounce_count: int = 0
var _hit_enemies: Array = []
var _damage_mult: float = 1.0


func activate(owner_node: Node2D) -> void:
	if is_active:
		return

	_owner_node = owner_node
	var weapon_range := WeaponData.get_attack_range(WeaponData.get_owner_weapon(owner_node), SKILL_RANGE)
	var first_target := _find_nearest_enemy(owner_node.global_position, weapon_range)
	if not first_target:
		_owner_node = null
		return

	is_active = true
	is_blocking = true
	_combatant = owner_node.get_node_or_null("Combatant") as Combatant
	_bounce_count = 0
	_hit_enemies.clear()
	_damage_mult = 1.0
	_done_sprites.clear()

	if not _tex:
		_tex = load(LIGHTNING_TEXTURE) as Texture2D
	if _tex:
		_frame_count = max(1, int(_tex.get_width()) / FRAME_WIDTH)
	_frame = 0
	_anim_timer = 0.0

	_start_segment(owner_node.global_position, first_target)


func _start_segment(from_pos: Vector2, target: Node2D) -> void:
	_current_target = target
	_src_pos = from_pos
	_dst_pos = target.global_position
	_progress = 0.0

	_active_sprite = Sprite2D.new()
	_active_sprite.texture = _tex
	_active_sprite.centered = false          # pivot at left edge (character side)
	_active_sprite.region_enabled = true
	_active_sprite.z_index = 10
	if _tex:
		# Center vertically on the beam line
		_active_sprite.offset = Vector2(0.0, -_tex.get_height() * 0.5)
	_owner_node.get_parent().add_child(_active_sprite)
	_apply_sprite(_progress)


func _process(delta: float) -> void:
	super._process(delta)
	if not is_active:
		return

	# Track moving target
	if _current_target and is_instance_valid(_current_target):
		_dst_pos = _current_target.global_position

	# Cycle animation frames
	if _frame_count > 1:
		_anim_timer += delta
		if _anim_timer >= 1.0 / ANIM_FPS:
			_anim_timer -= 1.0 / ANIM_FPS
			_frame = (_frame + 1) % _frame_count

	# Advance progress (beam tip moves at FILL_SPEED px/s)
	var dist := _src_pos.distance_to(_dst_pos)
	if dist > 0.0:
		_progress = minf(_progress + FILL_SPEED * delta / dist, 1.0)
	else:
		_progress = 1.0

	_apply_sprite(_progress)

	if _progress >= 1.0:
		_on_arrived()


## Scale ONE frame to span [src → dst], reveal left→right based on progress
func _apply_sprite(p: float) -> void:
	if not _active_sprite or not _tex:
		return
	var dist := _src_pos.distance_to(_dst_pos)
	if dist < 1.0:
		return
	var frame_x := float(_frame * FRAME_WIDTH)
	var tex_h   := float(_tex.get_height())

	_active_sprite.global_position = _src_pos
	_active_sprite.rotation = (_dst_pos - _src_pos).angle()
	_active_sprite.scale = Vector2(dist / FRAME_WIDTH, 1.0)                     # one frame spans full distance
	_active_sprite.region_rect = Rect2(frame_x, 0.0, p * FRAME_WIDTH, tex_h)   # reveal within current frame


func _on_arrived() -> void:
	# Lock finished segment at full frame width, keep it visible
	if _active_sprite and _tex:
		var frame_x := float(_frame * FRAME_WIDTH)
		_active_sprite.region_rect = Rect2(frame_x, 0, FRAME_WIDTH, _tex.get_height())
		_done_sprites.append(_active_sprite)
		_active_sprite = null

	# Deal damage
	if _current_target and is_instance_valid(_current_target):
		var tc := _current_target.get_node_or_null("Combatant") as Combatant
		if tc and not tc.is_dead and _combatant:
			var dmg := int(_combatant.atk * _damage_mult)
			tc.take_damage(dmg, Combatant.HIT_SKILL)
		_hit_enemies.append(_current_target)

	_bounce_count += 1
	_damage_mult += DAMAGE_PER_BOUNCE

	if _bounce_count < MAX_BOUNCES:
		var next := _find_nearest_enemy(_dst_pos, BOUNCE_RANGE)
		if next:
			_start_segment(_dst_pos, next)
			return

	_finish()


func _find_nearest_enemy(from_pos: Vector2, range_limit: float) -> Node2D:
	if not _owner_node or not is_instance_valid(_owner_node):
		return null
	var nearest: Node2D = null
	var nearest_dist := range_limit
	for enemy in _owner_node.get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or not is_instance_valid(enemy):
			continue
		if enemy in _hit_enemies:
			continue
		var ec := (enemy as Node).get_node_or_null("Combatant") as Combatant
		if ec and ec.is_dead:
			continue
		var dist := from_pos.distance_to((enemy as Node2D).global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


func _finish() -> void:
	if _active_sprite:
		_active_sprite.queue_free()
		_active_sprite = null
	for s in _done_sprites:
		if is_instance_valid(s):
			s.queue_free()
	_done_sprites.clear()
	is_blocking = false
	_owner_node = null
	_hit_enemies.clear()
	_current_target = null
	_end()
