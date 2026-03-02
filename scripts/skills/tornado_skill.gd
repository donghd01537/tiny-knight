class_name TornadoSkill
extends Skill
## Tornado — Breaker spins in place, dealing pulse AOE damage to all nearby enemies.
## Self-centered; no target needed — always activates immediately.
## Asset: assets/sprites/characters/breaker/skills/tornado.png

const HIT_RADIUS     := 90.0   ## AOE radius for each damage pulse
const DURATION       := 3.0    ## Total spin duration (seconds)
const PULSE_INTERVAL := 0.6    ## Seconds between damage pulses
const ANIM_FPS       := 8.0
const ANIM_SCALE     := Vector2(1.5, 1.5)

var _owner_node: Node2D = null
var _combatant: Combatant = null
var _hidden_nodes: Array = []

var _sprite: Sprite2D = null
var _tex: Texture2D = null
var _frames: Array = []
var _frame: int = 0
var _anim_timer: float = 0.0

var _elapsed: float = 0.0
var _pulse_timer: float = 0.0


func activate(owner_node: Node2D) -> void:
	if is_active:
		return

	is_active = true
	is_blocking = true
	_owner_node = owner_node
	_combatant = owner_node.get_node_or_null("Combatant") as Combatant
	_elapsed = 0.0
	_pulse_timer = 0.0

	# Hide character visuals while spinning
	_hidden_nodes.clear()
	for child in owner_node.get_children():
		if child is Node2D and child.visible:
			child.visible = false
			_hidden_nodes.append(child)

	if not _tex:
		_tex = load("res://assets/sprites/characters/breaker/skills/tornado.png") as Texture2D
	if _tex:
		_frames.clear()
		var h := _tex.get_height()
		var count := _tex.get_width() / h
		for i in count:
			_frames.append(Rect2i(i * h, 0, h, h))

	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.scale = ANIM_SCALE
	_sprite.z_index = 10
	owner_node.get_parent().add_child(_sprite)
	_sprite.global_position = owner_node.global_position

	_frame = 0
	_anim_timer = 0.0
	_apply_frame()

	# First pulse on activation
	_deal_damage()


func _process(delta: float) -> void:
	super._process(delta)

	if not is_active:
		return

	_elapsed += delta
	_pulse_timer += delta

	# Track character position and facing
	if _sprite and _owner_node and is_instance_valid(_owner_node):
		_sprite.global_position = _owner_node.global_position
		if abs(_owner_node.velocity.x) > 10.0:
			_sprite.flip_h = _owner_node.velocity.x < 0

	# Loop animation
	_anim_timer += delta
	if _anim_timer >= 1.0 / ANIM_FPS:
		_anim_timer -= 1.0 / ANIM_FPS
		_frame = (_frame + 1) % _frames.size()
		_apply_frame()

	# Damage pulses
	if _pulse_timer >= PULSE_INTERVAL:
		_pulse_timer -= PULSE_INTERVAL
		_deal_damage()

	if _elapsed >= DURATION:
		_finish()


func _deal_damage() -> void:
	if not _combatant or not _owner_node or not is_instance_valid(_owner_node):
		return
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D or not is_instance_valid(enemy):
			continue
		var dist := _owner_node.global_position.distance_to((enemy as Node2D).global_position)
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


func _finish() -> void:
	if _sprite:
		_sprite.queue_free()
		_sprite = null

	for node in _hidden_nodes:
		if is_instance_valid(node):
			node.visible = true
	_hidden_nodes.clear()

	is_blocking = false
	_owner_node = null
	_end()
