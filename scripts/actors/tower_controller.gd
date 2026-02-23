extends StaticBody2D
## Tower Controller
## Defensive structure that enemies can attack
## Adds to "heroes" group so enemies target it

var is_dead := false

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var combatant: Combatant = $Combatant


func _ready() -> void:
	add_to_group("heroes")

	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)
	if combatant:
		combatant.died.connect(_on_died)


func _on_died() -> void:
	is_dead = true
	sprite.play_death()


func _on_animation_finished() -> void:
	if sprite.animation == "death":
		queue_free()
