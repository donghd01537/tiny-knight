extends Area2D
## Fly Effect — Homing projectile that fires from attacker to enemy
## Similar to fireball but uses weapon-specific sprite

@export var speed := 400.0
@export var homing_strength := 8.0
@export var max_lifetime := 5.0

var target: Node2D = null
var damage := 0
var velocity := Vector2.ZERO
var lifetime := 0.0
var has_hit := false

@onready var sprite: Sprite2D = $Sprite

var _frames: Array = []
var _texture: Texture2D
var _frame := 0
var _timer := 0.0
var _fps := 10.0
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

	if target:
		var direction := (target.global_position - global_position).normalized()
		velocity = direction * speed

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


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	lifetime += delta
	if lifetime > max_lifetime:
		queue_free()
		return
	if has_hit:
		return
	if not is_instance_valid(target):
		queue_free()
		return

	var target_combatant := target.get_node_or_null("Combatant") as Combatant
	if target_combatant and target_combatant.is_dead:
		queue_free()
		return

	# Homing toward target
	var target_direction := (target.global_position - global_position).normalized()
	velocity = velocity.lerp(target_direction * speed, homing_strength * delta)
	rotation = velocity.angle()
	global_position += velocity * delta

	# Animate frames
	if _playing and _total_frames > 0:
		_timer += delta
		if _timer >= 1.0 / _fps:
			_timer -= 1.0 / _fps
			_frame = (_frame + 1) % _total_frames
			_apply_frame(_frame)


func _on_body_entered(body: Node2D) -> void:
	if has_hit:
		return
	if body == target:
		has_hit = true
		var target_combatant := target.get_node_or_null("Combatant") as Combatant
		if target_combatant:
			target_combatant.take_damage(damage)
		queue_free()
