extends AnimatedSprite2D
## Devil Animation

const SPRITES_PATH := "res://assets/sprites/enemies/devil/"

const MOVE_DOWN_SHEET := SPRITES_PATH + "move-down.png"
const ATTACK_SHEET := SPRITES_PATH + "attack.png"
const DEATH_SHEET := SPRITES_PATH + "death.png"

# Move-down/Idle: 5 frames, 193x193 each
var idle_frames := [
	Rect2i(0, 0, 193, 193),
	Rect2i(193, 0, 193, 193),
	Rect2i(386, 0, 193, 193),
	Rect2i(579, 0, 193, 193),
	Rect2i(772, 0, 193, 193),
]

# Attack: 4 frames, 193x193 each
var attack_frames := [
	Rect2i(0, 0, 193, 193),
	Rect2i(193, 0, 193, 193),
	Rect2i(386, 0, 193, 193),
	Rect2i(579, 0, 193, 193),
]

# Death: 3 frames, 259x257 each
var death_frames := [
	Rect2i(0, 0, 259, 257),
	Rect2i(259, 0, 259, 257),
	Rect2i(518, 0, 259, 257),
]


func _ready() -> void:
	setup_animations()
	play("idle")


func setup_animations() -> void:
	sprite_frames = SpriteFrames.new()

	var idle_tex := load(MOVE_DOWN_SHEET) as Texture2D
	var attack_tex := load(ATTACK_SHEET) as Texture2D
	var death_tex := load(DEATH_SHEET) as Texture2D

	create_animation("idle", idle_frames, idle_tex, true, 8.0)
	create_animation("attack", attack_frames, attack_tex, false, 10.0)
	create_animation("death", death_frames, death_tex, false, 6.0)

	centered = true


func create_animation(
	anim_name: String,
	frame_rects: Array,
	texture: Texture2D,
	loop: bool,
	fps: float
) -> void:
	if not texture:
		push_error("Failed to load texture for animation: " + anim_name)
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


func play_attack() -> void:
	if animation != "death":
		play("attack")


func play_death() -> void:
	play("death")
