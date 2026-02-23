extends Node2D
## HP Bar — displays health using hp_bar.png (background) and hp_bar_filled.png (fill)
## Attach as child of an actor that has a Combatant sibling node

const BG_TEXTURE_PATH := "res://assets/common/bars/hp_bar.png"
const FILL_TEXTURE_PATH := "res://assets/common/bars/hp_bar_filled.png"

var _combatant: Combatant = null
var _bg_sprite: Sprite2D
var _fill_sprite: Sprite2D
var _fill_region_start := Vector2.ZERO
var _fill_region_size := Vector2.ZERO


func _ready() -> void:
	# Find sibling Combatant
	_combatant = get_parent().get_node_or_null("Combatant") as Combatant

	var bg_tex := load(BG_TEXTURE_PATH) as Texture2D
	var fill_tex := load(FILL_TEXTURE_PATH) as Texture2D
	if not bg_tex or not fill_tex:
		return

	# Fill sprite (positioned to align with the bar area)
	_fill_sprite = Sprite2D.new()
	_fill_sprite.texture = fill_tex
	_fill_sprite.centered = false
	_fill_sprite.z_index = 0
	add_child(_fill_sprite)

	# Background/frame sprite should render above fill.
	_bg_sprite = Sprite2D.new()
	_bg_sprite.texture = bg_tex
	_bg_sprite.centered = false
	_bg_sprite.z_index = 1
	add_child(_bg_sprite)

	# Derive fill bounds from the texture alpha so bar alignment stays correct.
	var fill_img := fill_tex.get_image()
	if fill_img:
		var used_rect := fill_img.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			_fill_region_start = Vector2(used_rect.position.x, used_rect.position.y)
			_fill_region_size = Vector2(used_rect.size.x, used_rect.size.y)
		else:
			_fill_region_size = Vector2(fill_tex.get_width(), fill_tex.get_height())
	else:
		_fill_region_size = Vector2(fill_tex.get_width(), fill_tex.get_height())

	_fill_sprite.position = _fill_region_start

	if _combatant:
		_combatant.took_damage.connect(_on_took_damage)
		_update_bar()


func _on_took_damage(_amount: int) -> void:
	_update_bar()


func _update_bar() -> void:
	if not _combatant or not _fill_sprite:
		return
	var ratio := float(_combatant.current_hp) / float(_combatant.max_hp)
	ratio = clampf(ratio, 0.0, 1.0)

	# Clip only the non-transparent fill strip.
	_fill_sprite.region_enabled = true
	_fill_sprite.region_rect = Rect2(
		_fill_region_start.x,
		_fill_region_start.y,
		_fill_region_size.x * ratio,
		_fill_region_size.y
	)
