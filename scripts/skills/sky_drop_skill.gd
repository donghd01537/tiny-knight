class_name SkyDropSkill
extends Skill
## Sky Drop — breaker leaps and crashes on the nearest enemy.
## Frames 0-1 play at the character's position (wind-up).
## Frames 2-3 play at the enemy's position (impact + damage).
## Asset path: assets/sprites/characters/{character_name}/skills/sky_drop.png

const SKILL_RANGE := 180.0
const ANIM_FPS := 8.0
const ANIM_SCALE := Vector2(1.8, 1.8)
const PHASE_SWITCH_FRAME := 2

var _owner_node: Node2D = null
var _hidden_nodes: Array = []  # All Node2D children hidden during cast
var _target: Node2D = null
var _combatant: Combatant = null
var _drop_position: Vector2 = Vector2.ZERO  # Saved landing spot

var _sprite: Sprite2D = null
var _tex: Texture2D = null
var _frames: Array = []
var _frame: int = 0
var _anim_timer: float = 0.0
var _damage_dealt: bool = false
var _waiting_to_show: bool = false


func activate(owner_node: Node2D) -> void:
	if is_active:
		return

	_target = _find_nearest_enemy(owner_node, SKILL_RANGE)
	if not _target:
		return

	is_active = true
	is_blocking = true
	_owner_node = owner_node
	_combatant = owner_node.get_node_or_null("Combatant") as Combatant
	_damage_dealt = false
	_waiting_to_show = false
	_drop_position = owner_node.global_position

	# Hide all visual Node2D children (character, weapon, rage sprites, etc.)
	_hidden_nodes.clear()
	for child in owner_node.get_children():
		if child is Node2D and child.visible:
			child.visible = false
			_hidden_nodes.append(child)

	# Load texture from character-specific skill folder
	if not _tex:
		var char_name: String = "breaker"
		# Try to get character_name from the animation node
		for child in owner_node.get_children():
			if child.get_script() and child.get("character_name") != null:
				char_name = child.character_name
				break
		_tex = load("res://assets/sprites/characters/%s/skills/sky_drop.png" % char_name) as Texture2D

	if _tex:
		_frames.clear()
		var h := _tex.get_height()
		var count := _tex.get_width() / h
		for i in count:
			_frames.append(Rect2i(i * h, 0, h, h))

	# Spawn sprite at scene root so position is in world space
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.scale = ANIM_SCALE
	_sprite.z_index = 10
	owner_node.get_parent().add_child(_sprite)
	_sprite.global_position = owner_node.global_position

	_frame = 0
	_anim_timer = 0.0
	_apply_frame()


func _process(delta: float) -> void:
	super._process(delta)

	# After landing: keep blocking until attack cooldown completes
	if _waiting_to_show:
		var ready := true
		if _combatant and is_instance_valid(_combatant):
			ready = _combatant.can_attack
		if ready:
			_waiting_to_show = false
			is_blocking = false
			_owner_node = null
			_hidden_nodes.clear()
		return

	if not is_active:
		return

	_anim_timer += delta
	if _anim_timer < 1.0 / ANIM_FPS:
		return
	_anim_timer -= 1.0 / ANIM_FPS
	_frame += 1

	if _frame >= _frames.size():
		_finish()
		return

	# Switch to enemy position at phase boundary
	if _frame == PHASE_SWITCH_FRAME:
		if _target and is_instance_valid(_target):
			_drop_position = _target.global_position + Vector2(-40, 0)
		_sprite.global_position = _drop_position
		_owner_node.global_position = _drop_position

	# Deal damage on first impact frame
	if _frame == PHASE_SWITCH_FRAME and not _damage_dealt:
		_damage_dealt = true
		if _target and is_instance_valid(_target):
			var target_combatant := _target.get_node_or_null("Combatant") as Combatant
			if target_combatant and not target_combatant.is_dead and _combatant:
				target_combatant.take_damage(_combatant.atk, Combatant.HIT_SKILL)

	_apply_frame()


func _apply_frame() -> void:
	if not _sprite or _frames.is_empty():
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _tex
	atlas.region = _frames[_frame]
	_sprite.texture = atlas


func _restore_visuals() -> void:
	for node in _hidden_nodes:
		if is_instance_valid(node):
			node.visible = true


func _find_nearest_enemy(owner_node: Node2D, range_limit: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := range_limit

	for enemy in owner_node.get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D:
			continue
		if not is_instance_valid(enemy):
			continue
		var ec := (enemy as Node).get_node_or_null("Combatant") as Combatant
		if ec and ec.is_dead:
			continue
		var dist := owner_node.global_position.distance_to((enemy as Node2D).global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest


func _finish() -> void:
	if _sprite:
		_sprite.queue_free()
		_sprite = null

	# Reveal character at landing position immediately
	if _owner_node and is_instance_valid(_owner_node):
		_owner_node.global_position = _drop_position
		_restore_visuals()

	# Keep blocking until attack cooldown completes
	_waiting_to_show = true
	_target = null
	_end()
