extends Node2D
## Up Effect — Energy beam that plays at predicted enemy position
## Targets where enemy will be in ~0.2s, plays animation, deals damage on arrival

const PREDICT_TIME := 0.2  # Predict enemy position this many seconds ahead

var target: Node2D = null
var damage := 0
var has_hit := false
var _target_pos := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite

var _frames: Array = []
var _texture: Texture2D
var _frame := 0
var _timer := 0.0
var _fps := 12.0
var _total_frames := 0
var _playing := false


func _frames_from_texture(tex: Texture2D) -> Array:
	var frames: Array = []
	if not tex:
		return frames
	var img_w := int(tex.get_width())
	var img_h := int(tex.get_height())
	if img_h <= 0:
		return frames
	var frame_size := img_h
	var count := img_w / frame_size
	for i in count:
		frames.append(Rect2i(i * frame_size, 0, frame_size, frame_size))
	return frames


func initialize(target_node: Node2D, damage_amount: int, texture_path: String, _json_path: String) -> void:
	target = target_node
	damage = damage_amount

	_texture = load(texture_path) as Texture2D
	_frames = _frames_from_texture(_texture)
	_total_frames = _frames.size()

	# Predict where enemy will be
	_target_pos = target_node.global_position
	if target_node is CharacterBody2D:
		_target_pos += target_node.velocity * PREDICT_TIME

	global_position = _target_pos
	_playing = true
	_frame = 0
	_timer = 0.0

	if _total_frames > 0:
		_apply_frame(0)


func _apply_frame(frame_idx: int) -> void:
	if not _texture or frame_idx >= _frames.size():
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = _texture
	atlas.region = _frames[frame_idx]
	atlas.filter_clip = true
	sprite.texture = atlas
	sprite.centered = true


func _process(delta: float) -> void:
	if not _playing or _total_frames == 0:
		return

	_timer += delta
	if _timer >= 1.0 / _fps:
		_timer -= 1.0 / _fps
		_frame += 1
		if _frame >= _total_frames:
			_playing = false
			_deal_damage()
			queue_free()
			return
		_apply_frame(_frame)


func _deal_damage() -> void:
	if has_hit:
		return
	has_hit = true

	if is_instance_valid(target):
		var target_combatant := target.get_node_or_null("Combatant") as Combatant
		if target_combatant and not target_combatant.is_dead:
			target_combatant.take_damage(damage)
