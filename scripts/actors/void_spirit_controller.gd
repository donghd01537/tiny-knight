extends CharacterBody2D
## Void Spirit Auto-Battle Controller
## Ranged caster — engages enemies from distance using book weapon
## Normal attack spawns up_effect at target (damage handled by effect)
## Skills are child Skill nodes — controller activates them generically

@export var move_speed := 180.0
@export var attack_range := 120.0

var target: Node2D = null
var is_attacking := false
var is_dead := false
var home_position := Vector2.ZERO
var _was_moving := false
var _attack_delay := 0.0
const ATTACK_DELAY := 0.1
const SEPARATION_RADIUS := 80.0
const SEPARATION_WEIGHT := 2.0

const UpEffectScene := preload("res://scenes/effects/UpEffect.tscn")

@onready var anim = $VoidSpiritAnimation
@onready var combatant: Combatant = $Combatant

var _weapon_path: String
var _has_up_effect := false


func _ready() -> void:
	add_to_group("heroes")
	home_position = global_position

	if anim:
		anim.animation_finished.connect(_on_animation_finished)
		_weapon_path = "res://assets/sprites/weapons/%s/" % anim.weapon_name
		_has_up_effect = ResourceLoader.exists(_weapon_path + "up_effect.png")

	if combatant:
		combatant.attack_range = WeaponData.get_attack_range(anim.weapon_name, attack_range)
		combatant.died.connect(_on_died)


func _activate_ready_skills() -> void:
	for child in get_children():
		if child is Skill and child.can_activate():
			child.activate(self)
			if child.is_active:
				break  # One skill at a time — only stop if activation succeeded


func _any_skill_blocking() -> bool:
	for child in get_children():
		if child is Skill and child.is_blocking:
			return true
	return false


func _physics_process(_delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _any_skill_blocking():
		velocity = Vector2.ZERO
		anim.play_idle()
		move_and_slide()
		return

	_activate_ready_skills()
	find_nearest_enemy()

	if target:
		if combatant.is_in_range(target):
			if _was_moving:
				_was_moving = false
				_attack_delay = ATTACK_DELAY
				velocity = Vector2.ZERO
				anim.play_idle()
			if _attack_delay > 0.0:
				_attack_delay -= _delta
			elif combatant.can_attack:
				do_attack()
			else:
				velocity = Vector2.ZERO
				anim.play_idle()
		else:
			if combatant.can_attack:
				_was_moving = true
				move_toward_target()
			else:
				velocity = Vector2.ZERO
				anim.play_idle()
	else:
		var dist_to_home := global_position.distance_to(home_position)
		if dist_to_home > 10.0:
			var direction := (home_position - global_position).normalized()
			velocity = direction * move_speed
			anim.play_move(direction.x < 0)
		else:
			global_position = home_position
			velocity = Vector2.ZERO
			anim.play_idle()

	move_and_slide()
	constrain_to_screen()


func move_toward_target() -> void:
	if not target:
		return
	var to_target := (target.global_position - global_position).normalized()
	var direction := (to_target + _get_separation_force(to_target) * SEPARATION_WEIGHT).normalized()
	velocity = direction * move_speed
	anim.play_move(direction.x < 0)


func _get_separation_force(to_target: Vector2) -> Vector2:
	var separation := Vector2.ZERO
	for hero in get_tree().get_nodes_in_group("heroes"):
		if hero == self:
			continue
		var diff := global_position - (hero as Node2D).global_position
		var dist := diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.0:
			var strength := (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
			var away := diff.normalized()
			if (-away).dot(to_target) > 0.2:
				var perp := Vector2(-to_target.y, to_target.x)
				if away.dot(perp) < 0:
					perp = -perp
				separation += perp * strength * 2.0
			else:
				separation += away * strength
	return separation


func find_nearest_enemy() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := INF
	var screen_size := get_viewport_rect().size

	for enemy in enemies:
		if not enemy is Node2D:
			continue
		var enemy_combatant := enemy.get_node_or_null("Combatant") as Combatant
		if enemy_combatant and enemy_combatant.is_dead:
			continue
		var enemy_pos: Vector2 = (enemy as Node2D).global_position
		if enemy_pos.x < 0 or enemy_pos.x > screen_size.x or enemy_pos.y < 0 or enemy_pos.y > screen_size.y:
			continue
		var dist := global_position.distance_to(enemy_pos)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	target = nearest


func do_attack() -> void:
	if is_attacking or not combatant.can_attack:
		return
	var target_combatant := target.get_node_or_null("Combatant") as Combatant
	if not target_combatant or target_combatant.is_dead:
		return

	is_attacking = true
	velocity = Vector2.ZERO
	anim.flip_h = target.global_position.x < global_position.x
	anim.play_attack()

	if _has_up_effect:
		# Ranged: UpEffect handles the visual and damage
		var effect := UpEffectScene.instantiate()
		get_parent().add_child(effect)
		effect.initialize(target, combatant.atk, _weapon_path + "up_effect.png", "")
		combatant.can_attack = false
		combatant.attack_timer = combatant.attack_cooldown
	else:
		# Melee fallback
		combatant.do_attack(target_combatant)


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"attack":
		is_attacking = false
		anim.play_idle()
	elif anim_name == &"die":
		queue_free()


func _on_died() -> void:
	is_dead = true
	is_attacking = false
	velocity = Vector2.ZERO
	anim.play_death()


func constrain_to_screen() -> void:
	global_position.x = clamp(global_position.x, 90.0, 630.0)
	global_position.y = clamp(global_position.y, 190.0, 1130.0)
