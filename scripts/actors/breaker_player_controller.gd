extends CharacterBody2D
## Breaker Player Controller
## Touch-only. Movement via virtual joystick. Attack + skills via skill bar buttons.

@export var move_speed := 200.0
@export var use_constrain_bounds := true

const TRANSITION_DELAY := 0.2  ## Seconds between stopping move/attack and starting the other

var is_dead := false
var is_attacking := false
var joystick_direction := Vector2.ZERO  ## Written each frame by PlayerHUD

var _post_attack_delay := 0.0  ## Blocks movement after attack ends
var _post_move_delay   := 0.0  ## Blocks attack while moving + 0.2s after stop

@onready var anim = $BreakerAnimation
@onready var combatant: Combatant = $Combatant


func _ready() -> void:
	add_to_group("heroes")
	add_to_group("player_hero")
	# Don't push other CharacterBody2D nodes (enemies, allies).
	# Keep mask=1 so walls (StaticBody2D on layer 1) still block movement.
	collision_layer = 0

	if anim:
		anim.animation_finished.connect(_on_animation_finished)

	if combatant:
		combatant.attack_range = WeaponData.get_attack_range(anim.weapon_name, 80.0)
		combatant.died.connect(_on_died)


func _any_skill_blocking() -> bool:
	for child in get_children():
		if child is Skill and child.is_blocking:
			return true
	return false


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _post_attack_delay > 0.0:
		_post_attack_delay -= delta
	if _post_move_delay > 0.0:
		_post_move_delay -= delta

	var joystick_active := joystick_direction.length() > 0.1

	# While moving, keep delay pinned; on stop it counts down naturally
	if joystick_active:
		_post_move_delay = TRANSITION_DELAY

	if joystick_active and _post_attack_delay <= 0.0:
		velocity = joystick_direction * move_speed
		anim.play_move(joystick_direction.x < 0)
	else:
		velocity = Vector2.ZERO
		anim.play_idle()

	move_and_slide()
	constrain_to_screen()

	# Auto attack — fires whenever an enemy is in range, no button press needed
	if not _any_skill_blocking() and _find_nearest_enemy() != null:
		do_attack()


## Attack always swings. Faces + damages nearest enemy only if one is within range.
func do_attack() -> void:
	if is_dead or is_attacking or not combatant.can_attack or _post_move_delay > 0.0:
		return

	is_attacking = true
	velocity = Vector2.ZERO

	# Always consume the attack cooldown
	combatant.can_attack = false
	combatant.attack_timer = combatant.attack_cooldown

	# Face and damage nearest enemy if one is in range
	var target := _find_nearest_enemy()
	if target:
		anim.flip_h = target.global_position.x < global_position.x
		var tc := target.get_node_or_null("Combatant") as Combatant
		if tc and not tc.is_dead:
			tc.take_damage(combatant.atk)

	anim.play_attack()


## Activates a skill. If no enemy is in range the skill shows a cast-range ring.
func activate_skill(skill_node_name: String) -> void:
	if is_dead or _any_skill_blocking():
		return
	var skill := get_node_or_null(skill_node_name) as Skill
	if not skill or not skill.can_activate():
		return

	skill.activate(self)

	# Skill didn't start — no target in range. Show the range ring (parented to self so it follows).
	if not skill.is_active:
		RangeIndicator.show_at(self, global_position, _get_skill_range(skill_node_name))


## Returns the display range for the out-of-range indicator.
func _get_skill_range(skill_node_name: String) -> float:
	match skill_node_name:
		"SkyDropSkill":
			return 180.0
		"ThrowSkill":
			return 250.0
		"TornadoSkill":
			return TornadoSkill.HIT_RADIUS
	return 100.0


## Used by HUD to grey-out the attack button.
func can_do_attack() -> bool:
	return not is_dead and not is_attacking and combatant != null and combatant.can_attack


func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := combatant.attack_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy is Node2D:
			continue
		var ec := (enemy as Node).get_node_or_null("Combatant") as Combatant
		if ec and ec.is_dead:
			continue
		var dist := global_position.distance_to((enemy as Node2D).global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"attack":
		is_attacking = false
		_post_attack_delay = TRANSITION_DELAY
		anim.play_idle()
	elif anim_name == &"die":
		queue_free()


func _on_died() -> void:
	is_dead = true
	is_attacking = false
	velocity = Vector2.ZERO
	anim.play_death()


func constrain_to_screen() -> void:
	if not use_constrain_bounds:
		return
	global_position.x = clamp(global_position.x, 90.0, 638.0)
	global_position.y = clamp(global_position.y, 190.0, 1130.0)
