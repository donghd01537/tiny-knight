extends Node2D
## Layered Animation Controller
## 2-layer system: Character + Weapon
## Idle/Move: character layer
## Die: character layer (shared poof effect)
## Attack: character + weapon layers synchronized
## Computes frames from texture dimensions (horizontal strip, square frames)

## ============================================================================
## CONFIGURATION
## ============================================================================
@export var character_name: String = "breaker"
@export var weapon_name: String = ""
@export var weapon_offset: Vector2 = Vector2(0, 10)

## ============================================================================
## NODES
## ============================================================================
@onready var weapon_layer: Sprite2D = $WeaponLayer
@onready var character_layer: Sprite2D = $CharacterLayer

## ============================================================================
## ANIMATION STATE
## ============================================================================
signal animation_finished(anim_name: StringName)

var _flip := false
var _current_anim: StringName = &""
var _playing := false
var _looping := false
var _frame := 0
var _timer := 0.0
var _fps := 4.0
var _total_frames := 0

var _anim_data: Dictionary = {}
var _anim_textures: Dictionary = {}

## ============================================================================
## SETUP
## ============================================================================

func _ready() -> void:
	weapon_layer.z_index = 1
	character_layer.z_index = 2

	_load_all_animations()
	play_idle()


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


func _load_all_animations() -> void:
	var char_path := "res://assets/sprites/characters/%s/" % character_name
	var weapon_path := "res://assets/sprites/weapons/%s/" % weapon_name

	# Idle: character only
	var char_idle_tex := load(char_path + "idle.png") as Texture2D
	_anim_data[&"idle"] = { "character": _frames_from_texture(char_idle_tex) }
	_anim_textures[&"idle"] = { "character": char_idle_tex }

	# Move: character only
	var char_move_tex := load(char_path + "move.png") as Texture2D
	_anim_data[&"move"] = { "character": _frames_from_texture(char_move_tex) }
	_anim_textures[&"move"] = { "character": char_move_tex }

	# Die: shared poof effect on character layer
	var die_tex := load("res://assets/sprites/armors/die.png") as Texture2D
	_anim_data[&"die"] = { "character": _frames_from_texture(die_tex) }
	_anim_textures[&"die"] = { "character": die_tex }

	# Attack: character + weapon (weapon optional)
	var char_atk_tex := load(char_path + "attack.png") as Texture2D
	var char_atk_frames := _frames_from_texture(char_atk_tex)
	_anim_data[&"attack"] = { "character": char_atk_frames }
	_anim_textures[&"attack"] = { "character": char_atk_tex }

	if weapon_name != "":
		var weapon_atk_tex := load(weapon_path + "attack.png") as Texture2D
		if weapon_atk_tex:
			var weapon_atk_frames := _frames_from_texture(weapon_atk_tex)
			var atk_count := mini(char_atk_frames.size(), weapon_atk_frames.size())
			_anim_data[&"attack"]["character"] = char_atk_frames.slice(0, atk_count)
			_anim_data[&"attack"]["weapon"] = weapon_atk_frames.slice(0, atk_count)
			_anim_textures[&"attack"]["weapon"] = weapon_atk_tex


## ============================================================================
## FRAME APPLICATION
## ============================================================================

func _set_layer_frame(layer: Sprite2D, tex: Texture2D, rect: Rect2i) -> void:
	if not tex:
		layer.visible = false
		return
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = rect
	atlas.filter_clip = true
	layer.texture = atlas
	layer.centered = true


func _set_layers_visible(show_char: bool, show_weapon: bool) -> void:
	character_layer.visible = show_char
	weapon_layer.visible = show_weapon


func _apply_frame(anim_name: StringName, frame_idx: int) -> void:
	var data: Dictionary = _anim_data[anim_name]
	var textures: Dictionary = _anim_textures[anim_name]

	if data.has("character"):
		_set_layer_frame(character_layer, textures["character"], data["character"][frame_idx])
	if data.has("weapon"):
		_set_layer_frame(weapon_layer, textures["weapon"], data["weapon"][frame_idx])


## ============================================================================
## ANIMATION CONTROL
## ============================================================================

func _start_anim(anim_name: StringName, fps: float, loop: bool) -> void:
	var data: Dictionary = _anim_data.get(anim_name, {})
	var count := 0
	for layer_key in data:
		count = data[layer_key].size()
		break

	if count == 0:
		push_warning("No frames for animation: " + anim_name)
		return

	_current_anim = anim_name
	_playing = true
	_looping = loop
	_fps = fps
	_frame = 0
	_timer = 0.0
	_total_frames = count

	var has_weapon := data.has("weapon")
	_set_layers_visible(true, has_weapon)

	weapon_layer.z_index = 3 if anim_name == &"attack" else 1

	_apply_flip()
	_apply_frame(anim_name, 0)


func play_idle() -> void:
	if _current_anim == &"attack" and _playing:
		return
	if _current_anim == &"idle" and _playing:
		return
	_start_anim(&"idle", 4.0, true)


func play_move(flip: bool) -> void:
	if _current_anim == &"attack" and _playing:
		return
	set_flip(flip)
	if _current_anim != &"move" or not _playing:
		_start_anim(&"move", 10.0, true)
	else:
		_apply_flip()


func play_move_left() -> void:
	play_move(true)


func play_move_right() -> void:
	play_move(false)


func play_move_up() -> void:
	play_move(false)


func play_move_down() -> void:
	play_move(false)


func play_attack() -> void:
	_start_anim(&"attack", 15.0, false)


func play_death() -> void:
	_playing = false
	_start_anim(&"die", 6.0, false)


func set_flip(flip: bool) -> void:
	_flip = flip
	_apply_flip()


func _apply_flip() -> void:
	var sx := -1.0 if _flip else 1.0
	character_layer.scale.x = sx
	weapon_layer.scale.x = sx
	weapon_layer.position = Vector2(weapon_offset.x * sx, weapon_offset.y)


## ============================================================================
## FRAME PROGRESSION
## ============================================================================

func _process(delta: float) -> void:
	if not _playing:
		return

	_timer += delta
	var frame_duration := 1.0 / _fps

	if _timer >= frame_duration:
		_timer -= frame_duration
		_frame += 1

		if _frame >= _total_frames:
			if _looping:
				_frame = 0
			else:
				_playing = false
				var finished_anim := _current_anim
				if finished_anim == &"attack":
					_set_layers_visible(false, false)
				animation_finished.emit(finished_anim)
				return

		_apply_frame(_current_anim, _frame)


## ============================================================================
## PROPERTIES
## ============================================================================

var flip_h: bool:
	get:
		return _flip
	set(value):
		set_flip(value)

var animation: StringName:
	get:
		return _current_anim


## ============================================================================
## EQUIPMENT CHANGE
## ============================================================================

func change_weapon(new_weapon_name: String) -> void:
	weapon_name = new_weapon_name
	_load_all_animations()
	play_idle()
