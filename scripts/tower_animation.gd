extends AnimatedSprite2D
## Tower Animation
## Uses sprite sheet: frame_tower.png (4 frames, square)

const TOWER_SHEET := "res://assets/sprites/towers/frame_tower.png"

var _frame_rects: Array = []


func _ready() -> void:
	_parse_frames()
	setup_animations()
	play("idle")


func _parse_frames() -> void:
	var tex := load(TOWER_SHEET) as Texture2D
	if not tex:
		return
	var img_w := int(tex.get_width())
	var img_h := int(tex.get_height())
	var frame_size := img_h
	var count := img_w / frame_size
	for i in count:
		_frame_rects.append(Rect2i(i * frame_size, 0, frame_size, frame_size))


func setup_animations() -> void:
	sprite_frames = SpriteFrames.new()

	var tex := load(TOWER_SHEET) as Texture2D

	# Idle: all 4 frames looping
	create_animation("idle", _frame_rects, tex, true, 4.0)

	# Death: last frame only, non-looping (tower crumbles)
	if _frame_rects.size() > 0:
		create_animation("death", [_frame_rects[-1]], tex, false, 6.0)

	centered = true


func create_animation(
	anim_name: String,
	frame_rects: Array,
	texture: Texture2D,
	loop: bool,
	fps: float
) -> void:
	if not texture:
		return

	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)

	for rect in frame_rects:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = rect
		atlas.filter_clip = true
		sprite_frames.add_frame(anim_name, atlas)


func play_idle() -> void:
	if animation != "death":
		play("idle")


func play_death() -> void:
	play("death")
