extends CanvasLayer
## Player HUD
## - Joystick: hidden by default, appears at touch position anywhere on screen
## - Attack / Throw / Tornado: activate immediately on touch-down
## - SkyDrop: drag-to-aim targeting (touch-down to start, drag to choose spot, release to drop)

## Must match SkyDropSkill.SKILL_RANGE
const SKY_DROP_RANGE := 230.0

var _player: Node = null
var _joystick_touch_idx := -1
var _sky_drop_touch_idx := -1
var _sky_drop_drag_start := Vector2.ZERO  ## Screen pos where the SkyDrop finger first landed
var _sky_drop_target_pos := Vector2.ZERO

@onready var _joystick                    = $Joystick
@onready var _skill_pad: Control          = $SkillPad
@onready var _attack_btn: TextureButton   = $SkillPad/AttackBtn
@onready var _sky_drop_btn: TextureButton = $SkillPad/SkyDropBtn
@onready var _throw_btn: TextureButton    = $SkillPad/ThrowBtn
@onready var _tornado_btn: TextureButton  = $SkillPad/TornadoBtn
@onready var _targeter: Control           = $SkyDropTargeter
@onready var _tornado_cd:  TextureProgressBar = $SkillPad/TornadoBtn/Cooldown
@onready var _sky_drop_cd: TextureProgressBar = $SkillPad/SkyDropBtn/Cooldown
@onready var _throw_cd:    TextureProgressBar = $SkillPad/ThrowBtn/Cooldown
@onready var _tornado_ring:   TextureRect = $SkillPad/TornadoBtn/OutlineRing
@onready var _sky_drop_ring:  TextureRect = $SkillPad/SkyDropBtn/OutlineRing
@onready var _throw_ring:     TextureRect = $SkillPad/ThrowBtn/OutlineRing

## Tracks whether each skill was ready last frame — used to fire the pop animation.
var _tornado_was_ready  := true
var _sky_drop_was_ready := true
var _throw_was_ready    := true


func _ready() -> void:
	call_deferred("_find_player")
	var fill_tex := _make_filled_circle(76)
	var ring_tex := _make_ring_circle(76, 3)
	for cd: TextureProgressBar in [_tornado_cd, _sky_drop_cd, _throw_cd]:
		cd.texture_progress = fill_tex
	for ring: TextureRect in [_tornado_ring, _sky_drop_ring, _throw_ring]:
		ring.texture = ring_tex


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player_hero")
	if players.size() > 0:
		_player = players[0]


func _process(_delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		return

	# Drive movement
	_player.joystick_direction = _joystick.direction

	# Button disabled states (visual feedback)
	if _attack_btn:
		_attack_btn.disabled = not _player.can_do_attack()

	var sky_drop  := _player.get_node_or_null("SkyDropSkill") as Skill
	var throw_skl := _player.get_node_or_null("ThrowSkill")   as Skill

	if _sky_drop_btn and sky_drop:
		_sky_drop_btn.disabled = not sky_drop.can_activate()
	if _throw_btn and throw_skl:
		_throw_btn.disabled = not throw_skl.can_activate()

	var tornado_skl := _player.get_node_or_null("TornadoSkill") as Skill
	if _tornado_btn:
		_tornado_btn.disabled = not (tornado_skl and tornado_skl.can_activate())

	# Cooldown overlays — return value tracks "was ready" for pop detection
	_tornado_was_ready  = _update_cooldown_bar(_tornado_cd,  _tornado_btn,  tornado_skl, _tornado_was_ready)
	_sky_drop_was_ready = _update_cooldown_bar(_sky_drop_cd, _sky_drop_btn, sky_drop,    _sky_drop_was_ready)
	_throw_was_ready    = _update_cooldown_bar(_throw_cd,    _throw_btn,    throw_skl,   _throw_was_ready)

	# Keep targeter ring centred on player while dragging
	if _sky_drop_touch_idx != -1:
		_targeter.update_positions(_player.global_position, _sky_drop_target_pos)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch

		if touch.pressed:
			if not _player or not is_instance_valid(_player):
				return

			# SkyDrop — begin targeting drag (activate on RELEASE, not press)
			if _sky_drop_btn and not _sky_drop_btn.disabled and _sky_drop_touch_idx == -1:
				if _sky_drop_btn.get_global_rect().has_point(touch.position):
					_sky_drop_touch_idx = touch.index
					_sky_drop_drag_start = touch.position
					_sky_drop_target_pos = _player.global_position
					_targeter.show_at(_player.global_position, _sky_drop_target_pos, SKY_DROP_RANGE)
					_press_btn_visual(_sky_drop_btn)
					get_viewport().set_input_as_handled()
					return

			# Attack — immediate
			if _attack_btn and not _attack_btn.disabled:
				if _attack_btn.get_global_rect().has_point(touch.position):
					_player.do_attack()
					_bounce_btn(_attack_btn)
					get_viewport().set_input_as_handled()
					return

			# Throw — immediate
			if _throw_btn and not _throw_btn.disabled:
				if _throw_btn.get_global_rect().has_point(touch.position):
					_player.activate_skill("ThrowSkill")
					_bounce_btn(_throw_btn)
					get_viewport().set_input_as_handled()
					return

			# Tornado — immediate
			if _tornado_btn and not _tornado_btn.disabled:
				if _tornado_btn.get_global_rect().has_point(touch.position):
					_player.activate_skill("TornadoSkill")
					_bounce_btn(_tornado_btn)
					get_viewport().set_input_as_handled()
					return

			# Any unclaimed touch outside the skill pad → joystick appears at touch position
			if _joystick_touch_idx == -1 and not _skill_pad.get_global_rect().has_point(touch.position):
				_joystick_touch_idx = touch.index
				_joystick.begin(touch.position)

		else:
			# SkyDrop finger released — execute drop at chosen position
			if _sky_drop_touch_idx != -1 and touch.index == _sky_drop_touch_idx:
				_sky_drop_touch_idx = -1
				_targeter.visible = false
				_release_btn_visual(_sky_drop_btn)
				if _player and is_instance_valid(_player):
					var skill := _player.get_node_or_null("SkyDropSkill") as SkyDropSkill
					if skill and skill.can_activate():
						skill.manual_position = _sky_drop_target_pos
						skill.activate(_player)
				get_viewport().set_input_as_handled()
				return

			# Joystick finger released
			if _joystick_touch_idx != -1 and touch.index == _joystick_touch_idx:
				_joystick_touch_idx = -1
				_joystick.release()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag

		# SkyDrop drag
		if _sky_drop_touch_idx != -1 and drag.index == _sky_drop_touch_idx:
			if _player and is_instance_valid(_player):
				var pp: Vector2 = _player.global_position
				var delta: Vector2 = (drag.position - _sky_drop_drag_start) * 1.5
				_sky_drop_target_pos = pp + delta.limit_length(SKY_DROP_RANGE)
				_targeter.update_positions(pp, _sky_drop_target_pos)
			get_viewport().set_input_as_handled()
			return

		# Joystick drag
		if _joystick_touch_idx != -1 and drag.index == _joystick_touch_idx:
			_joystick.update_drag(drag.position)


## Drives one cooldown bar. Returns true when the skill is fully ready.
## Three explicit states:
##   is_active            → value = 1.0  full dark (skill casting)
##   cooldown_fraction > 0 → value = frac  draining arc
##   both false           → hidden  + pop fires on transition
func _update_cooldown_bar(bar: TextureProgressBar, btn: TextureButton,
		skill: Skill, was_ready: bool) -> bool:
	if not bar:
		return was_ready
	if not skill:
		bar.visible = false
		return true

	var is_casting := skill.is_active
	var frac       := skill.cooldown_fraction()

	var is_ready  := not is_casting and frac <= 0.001
	var pop_fires := not was_ready and is_ready

	if is_casting:
		bar.value   = 1.0
		bar.visible = true
	elif frac > 0.001:
		bar.value   = frac
		bar.visible = true
	elif not pop_fires:
		bar.visible = false

	if pop_fires:
		if btn:
			_pop_btn(btn, bar)
		else:
			bar.visible = false
	return is_ready


## Quick bounce: squish down then spring back — for instant-activate buttons.
func _bounce_btn(btn: Control) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(0.88, 0.88), 0.06)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Hold-press: squish and stay — for buttons held until release (SkyDrop).
func _press_btn_visual(btn: Control) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(0.88, 0.88), 0.06)


## Spring back after hold-release.
func _release_btn_visual(btn: Control) -> void:
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Scale-pop when a skill becomes ready again.
## Hides cd_bar at the same moment so overlay and pop are coupled.
func _pop_btn(btn: Control, cd_bar: TextureProgressBar = null) -> void:
	if cd_bar:
		cd_bar.visible = false
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Solid white circle — used as the cooldown sweep texture.
func _make_filled_circle(diameter: int) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(diameter * 0.5, diameter * 0.5)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= r:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


## Hollow ring — used as the permanent outline around each skill button.
func _make_ring_circle(diameter: int, thickness: int) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var center := Vector2(diameter * 0.5, diameter * 0.5)
	var outer_r := diameter * 0.5
	var inner_r := outer_r - thickness
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= outer_r and d >= inner_r:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)
