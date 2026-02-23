extends AnimatedSprite2D
## Goblin Animation
## Uses sprite sheets: move-down (idle), attack, death

const SPRITES_PATH := "res://assets/sprites/enemies/goblin/"

const MOVE_DOWN_SHEET := SPRITES_PATH + "move-down.png"
const ATTACK_SHEET := SPRITES_PATH + "attack.png"
const DEATH_SHEET := SPRITES_PATH + "death.png"

# Move-down/Idle: 5 frames, 257x253 each
var idle_frames := [
	Rect2i(0, 0, 257, 253),
	Rect2i(257, 0, 257, 253),
	Rect2i(514, 0, 257, 253),
	Rect2i(771, 0, 257, 253),
	Rect2i(1028, 0, 257, 253),
]

# Attack: 3 frames, 257x256 each
var attack_frames := [
	Rect2i(0, 0, 257, 256),
	Rect2i(257, 0, 257, 256),
	Rect2i(514, 0, 257, 256),
]

# Death: 3 frames, 257x257 each
var death_frames := [
	Rect2i(0, 0, 257, 257),
	Rect2i(257, 0, 257, 257),
	Rect2i(514, 0, 257, 257),
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
