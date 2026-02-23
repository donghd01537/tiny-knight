class_name Combatant
extends Node
## Combat component for handling HP, ATK, and combat interactions

const _HIT_EFFECT_SCENE := preload("res://scenes/effects/HitEffect.tscn")

signal died
signal took_damage(amount: int)
signal attacked(target: Combatant)

@export var max_hp: int = 10
@export var atk: int = 1
@export var attack_range: float = 100.0
@export var attack_cooldown: float = 1.5

var current_hp: int
var is_dead: bool = false
var can_attack: bool = true
var attack_timer: float = 0.0


func _ready() -> void:
	current_hp = max_hp


func _process(delta: float) -> void:
	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0:
			can_attack = true


const HIT_NORMAL  := "res://assets/sprites/effects/hit/hit.png"
const HIT_SKILL   := "res://assets/sprites/effects/hit/lightning.png"

func take_damage(amount: int, effect_path: String = HIT_NORMAL) -> void:
	if is_dead:
		return

	current_hp -= amount
	took_damage.emit(amount)

	# Show damage popup and hit effect
	var parent := get_parent() as Node2D
	if parent:
		DamagePopup.create(parent, amount)
		var effect := _HIT_EFFECT_SCENE.instantiate()
		effect.z_index = 20
		parent.add_child(effect)
		effect.initialize(effect_path, 12.0)

	if current_hp <= 0:
		current_hp = 0
		is_dead = true
		died.emit()


func do_attack(target: Combatant) -> void:
	if is_dead or not can_attack:
		return

	can_attack = false
	attack_timer = attack_cooldown
	target.take_damage(atk)
	attacked.emit(target)
	print("%s attacks %s for %d damage!" % [get_parent().name, target.get_parent().name, atk])


func is_in_range(target: Node2D) -> bool:
	var parent := get_parent() as Node2D
	if not parent or not target:
		return false
	return parent.global_position.distance_to(target.global_position) <= attack_range
