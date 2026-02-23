extends CharacterBody2D
class_name GoblinEnemy
## Goblin Enemy Controller
## Auto-finds hero and attacks when in range

@export var move_speed := 80.0
@export var invert_flip := false  # Set true if sprite faces opposite direction

var target: Node2D = null
var is_attacking := false
var is_dead := false

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var combatant: Combatant = $Combatant


func _ready() -> void:
	add_to_group("enemies")

	# Connect signals
	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
	if combatant:
		combatant.died.connect(_on_died)

	# Find hero target
	call_deferred("find_target")


func find_target() -> void:
	var heroes := get_tree().get_nodes_in_group("heroes")
	var nearest: Node2D = null
	var nearest_dist := INF

	for hero in heroes:
		if not hero is Node2D:
			continue
		var hero_combatant := hero.get_node_or_null("Combatant") as Combatant
		if hero_combatant and hero_combatant.is_dead:
			continue
		var dist := global_position.distance_to(hero.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = hero

	target = nearest


func _physics_process(_delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Re-evaluate target each frame (pick nearest alive hero/tower)
	find_target()

	if not target:
		sprite.play_idle()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Check attack range
	if combatant.is_in_range(target):
		do_attack()
	else:
		move_toward_target()

	move_and_slide()


func move_toward_target() -> void:
	if not target:
		return

	var direction := (target.global_position - global_position).normalized()
	velocity = direction * move_speed
	sprite.play_idle()  # Use idle/move-down animation while moving


func do_attack() -> void:
	if is_attacking or not combatant.can_attack:
		return

	is_attacking = true
	velocity = Vector2.ZERO

	# Flip sprite to face target
	var target_on_right := target.global_position.x > global_position.x
	if invert_flip:
		sprite.flip_h = not target_on_right
	else:
		sprite.flip_h = target_on_right

	sprite.play_attack()

	# Deal damage when attack animation plays
	var target_combatant := target.get_node_or_null("Combatant") as Combatant
	if target_combatant:
		combatant.do_attack(target_combatant)


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		sprite.play_idle()
	elif sprite.animation == "death":
		# Remove goblin after death animation
		queue_free()


func _on_died() -> void:
	is_dead = true
	is_attacking = false
	velocity = Vector2.ZERO
	sprite.play_death()
