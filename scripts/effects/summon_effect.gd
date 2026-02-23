extends Node2D
## Summon Effect — Plays summoning circle animation, then spawns enemy

signal summon_finished

var _texture: Texture2D
var _frames: Array = []
var _frame := 0
var _total_frames := 0
var _timer := 0.0
var _fps := 10.0
var _playing := false

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	_texture = load("res://assets/sprites/enemies/summon.png") as Texture2D
	_frames = _frames_from_texture(_texture)
	_total_frames = _frames.size()

	if _total_frames > 0:
		_playing = true
		_frame = 0
		_timer = 0.0
		_apply_frame(0)


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
			summon_finished.emit()
			queue_free()
			return
		_apply_frame(_frame)
