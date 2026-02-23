class_name RageSkill
extends Skill
## Rage — looping aura effect on character, +1 ATK for 5 seconds.

const EFFECT_PNG := "res://assets/sprites/skills/rage/effect.png"
const DURATION := 5.0
const ATK_BONUS := 1
const ANIM_FPS := 8.0

var _combatant: Combatant = null
var _sprite: Sprite2D = null
var _duration_timer: float = 0.0
var _anim_timer: float = 0.0
var _frame: int = 0
var _frames: Array = []
var _tex: Texture2D = null


func activate(owner_node: Node2D) -> void:
	if is_active:
		return
	is_active = true

	_combatant = owner_node.get_node_or_null("Combatant") as Combatant
	if _combatant:
		_combatant.atk += ATK_BONUS

	_duration_timer = DURATION

	# Build animation frames from horizontal strip
	if not _tex:
		_tex = load(EFFECT_PNG) as Texture2D
	if _tex:
		_frames.clear()
		var h := _tex.get_height()
		var count := _tex.get_width() / h
		for i in count:
			_frames.append(Rect2i(i * h, 0, h, h))

	# Create overlay sprite parented to owner
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.scale = Vector2(2, 3)
	_sprite.z_index = 10
	owner_node.add_child(_sprite)
	_frame = 0
	_anim_timer = 0.0
	_apply_frame()


func _process(delta: float) -> void:
	super._process(delta)

	if not is_active:
		return

	# Animate
	_anim_timer += delta
	if _anim_timer >= 1.0 / ANIM_FPS:
		_anim_timer -= 1.0 / ANIM_FPS
		_frame = (_frame + 1) % _frames.size()
		_apply_frame()

	# Expire
	_duration_timer -= delta
	if _duration_timer <= 0.0:
		_expire()


func _apply_frame() -> void:
	if not _sprite or _frames.is_empty():
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _tex
	atlas.region = _frames[_frame]
	_sprite.texture = atlas


func _expire() -> void:
	if _combatant:
		_combatant.atk -= ATK_BONUS

	if _sprite:
		_sprite.queue_free()
		_sprite = null

	_end()
