class_name SkyDropSkill
extends Skill
## Sky Drop — Breaker leaps to a manually chosen position and crashes there.
## Set `manual_position` before calling activate().
## Frames 0-1 play at the character's position (wind-up).
## Frames 2-3 play at the drop position (impact + splash damage).

const SKILL_RANGE := 230.0   ## Max cast distance (enforced by HUD targeting UI)
const HIT_RADIUS  := 50.0    ## Splash damage radius at landing
const ANIM_FPS    := 8.0
const ANIM_SCALE  := Vector2(1.8, 1.8)
const PHASE_SWITCH_FRAME := 2

## Set by the HUD before activate() is called.
var manual_position: Vector2 = Vector2.ZERO

var _owner_node: Node2D = null
var _hidden_nodes: Array = []
var _combatant: Combatant = null
var _drop_position: Vector2 = Vector2.ZERO

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

	is_active = true
	is_blocking = true
	_owner_node = owner_node
	_combatant = owner_node.get_node_or_null("Combatant") as Combatant
	_damage_dealt = false
	_waiting_to_show = false
	_drop_position = owner_node.global_position

	# Hide all visual Node2D children
	_hidden_nodes.clear()
	for child in owner_node.get_children():
		if child is Node2D and child.visible:
			child.visible = false
			_hidden_nodes.append(child)

	# Load texture from character-specific skill folder
	if not _tex:
		var char_name: String = "breaker"
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

	# Spawn sprite at scene root (world space)
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

	# Phase switch: teleport character and sprite to manual drop position
	if _frame == PHASE_SWITCH_FRAME:
		_drop_position = manual_position
		_sprite.global_position = _drop_position
		_owner_node.global_position = _drop_position

	# Splash damage at landing
	if _frame == PHASE_SWITCH_FRAME and not _damage_dealt:
		_damage_dealt = true
		_deal_splash_damage()

	_apply_frame()


func _deal_splash_damage() -> void:
	if not _combatant:
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or not is_instance_valid(enemy):
			continue
		var dist := _drop_position.distance_to((enemy as Node2D).global_position)
		if dist > HIT_RADIUS:
			continue
		var ec := (enemy as Node).get_node_or_null("Combatant") as Combatant
		if ec and not ec.is_dead:
			ec.take_damage(_combatant.atk, Combatant.HIT_SKILL)


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


func _finish() -> void:
	if _sprite:
		_sprite.queue_free()
		_sprite = null

	if _owner_node and is_instance_valid(_owner_node):
		_owner_node.global_position = _drop_position
		_restore_visuals()

	_waiting_to_show = true
	_end()
