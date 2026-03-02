class_name Skill
extends Node
## Base class for all skills.
## Attach as a child of any character node.
## The controller activates skills generically — no per-skill knowledge needed.

signal skill_ended

@export var cooldown: float = 10.0

var is_active: bool = false
var is_blocking: bool = false  ## True while the controller should halt movement
var _cooldown_timer: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func can_activate() -> bool:
	return not is_active and _cooldown_timer <= 0.0


func cooldown_fraction() -> float:
	if cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_timer / cooldown, 0.0, 1.0)


## Called by the controller to start the skill.
func activate(owner_node: Node2D) -> void:
	pass


## Called internally when the skill expires.
func _end() -> void:
	is_active = false
	_cooldown_timer = cooldown
	skill_ended.emit()
