class_name ThrowSkill
extends Skill
## Axe Throw — throws the axe bouncing up to 4 enemies, then returns to character.
## Sprite travels in world space. Character stays idle (is_blocking) throughout.
## Asset path: assets/sprites/weapons/axe/throw.png

const SKILL_RANGE  := 250.0   # Initial target search range
const BOUNCE_RANGE := 180.0   # Range to find next bounce target
const MAX_BOUNCES  := 4
const THROW_SPEED  := 450.0   # px/s
const ANIM_FPS     := 12.0
const ANIM_SCALE   := Vector2(1, 1)
const ROTATION_SPEED := TAU * 2.5  # radians/s — spinning while flying

enum State { TO_ENEMY, TO_CHARACTER }

var _owner_node: Node2D = null
var _combatant: Combatant = null

var _sprite: Sprite2D = null
var _tex: Texture2D = null
var _frames: Array = []
var _frame: int = 0
var _anim_timer: float = 0.0

var _state: int = State.TO_ENEMY
var _current_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO
var _current_target: Node2D = null
var _bounce_count: int = 0
var _hit_enemies: Array = []


func activate(owner_node: Node2D) -> void:
	if is_active:
		return

	var weapon_range := WeaponData.get_attack_range(WeaponData.get_owner_weapon(owner_node), SKILL_RANGE)
	var first_target := _find_nearest_enemy(owner_node, owner_node.global_position, weapon_range, [])
	if not first_target:
		return

	is_active = true
	is_blocking = true
	_owner_node = owner_node
	_combatant = owner_node.get_node_or_null("Combatant") as Combatant
	_bounce_count = 0
	_hit_enemies.clear()

	# Load texture (4 frames, 64x64 each)
	if not _tex:
		_tex = load("res://assets/sprites/weapons/axe/throw.png") as Texture2D
	if _tex:
		_frames.clear()
		var h := _tex.get_height()
		var count := _tex.get_width() / h
		for i in count:
			_frames.append(Rect2i(i * h, 0, h, h))

	# Spawn sprite in world space
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.scale = ANIM_SCALE
	_sprite.z_index = 10
	owner_node.get_parent().add_child(_sprite)

	_current_pos = owner_node.global_position
	_sprite.global_position = _current_pos
	_frame = 0
	_anim_timer = 0.0
	_apply_frame()

	_current_target = first_target
	_target_pos = first_target.global_position
	_state = State.TO_ENEMY


func _process(delta: float) -> void:
	super._process(delta)

	if not is_active:
		return

	# Animate frames
	_anim_timer += delta
	if _anim_timer >= 1.0 / ANIM_FPS:
		_anim_timer -= 1.0 / ANIM_FPS
		_frame = (_frame + 1) % _frames.size()
		_apply_frame()

	# Spin sprite
	if _sprite:
		_sprite.rotation += ROTATION_SPEED * delta

	# Track character position while returning (in case they moved)
	if _state == State.TO_CHARACTER and _owner_node and is_instance_valid(_owner_node):
		_target_pos = _owner_node.global_position

	# Move sprite toward target
	var to_target := _target_pos - _current_pos
	var dist := to_target.length()
	var step := THROW_SPEED * delta

	if step >= dist:
		_current_pos = _target_pos
		if _sprite:
			_sprite.global_position = _current_pos
		_on_arrived()
	else:
		_current_pos += to_target.normalized() * step
		if _sprite:
			_sprite.global_position = _current_pos


func _on_arrived() -> void:
	if _state == State.TO_ENEMY:
		# Deal damage to current target
		if _current_target and is_instance_valid(_current_target):
			var tc := _current_target.get_node_or_null("Combatant") as Combatant
			if tc and not tc.is_dead and _combatant:
				tc.take_damage(_combatant.atk, Combatant.HIT_SKILL)
			_hit_enemies.append(_current_target)

		_bounce_count += 1

		# Try to bounce to next enemy
		if _bounce_count < MAX_BOUNCES:
			var next := _find_nearest_enemy(_owner_node, _current_pos, BOUNCE_RANGE, _hit_enemies)
			if next:
				_current_target = next
				_target_pos = next.global_position
				return  # Continue bouncing

		# No more bounces — return to character
		_state = State.TO_CHARACTER
		if _owner_node and is_instance_valid(_owner_node):
			_target_pos = _owner_node.global_position
		else:
			_finish()

	elif _state == State.TO_CHARACTER:
		_finish()


func _apply_frame() -> void:
	if not _sprite or _frames.is_empty():
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _tex
	atlas.region = _frames[_frame]
	_sprite.texture = atlas


func _find_nearest_enemy(from_node: Node2D, from_pos: Vector2, range_limit: float, exclude: Array) -> Node2D:
	if not from_node or not is_instance_valid(from_node):
		return null
	var nearest: Node2D = null
	var nearest_dist := range_limit
	for enemy in from_node.get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or not is_instance_valid(enemy):
			continue
		if enemy in exclude:
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
	if _sprite:
		_sprite.queue_free()
		_sprite = null
	is_blocking = false
	_owner_node = null
	_hit_enemies.clear()
	_current_target = null
	_end()
