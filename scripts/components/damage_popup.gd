extends Node2D
class_name DamagePopup
## Floating damage number

var damage_amount: int = 0
var float_speed: float = 100.0
var fade_speed: float = 2.0
var lifetime: float = 0.8

@onready var label: Label


func _ready() -> void:
	# Create label
	label = Label.new()
	label.text = str(damage_amount)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.RED)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-20, -40)
	add_child(label)


func _process(delta: float) -> void:
	# Float up
	position.y -= float_speed * delta

	# Fade out
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
	else:
		modulate.a = lifetime / 0.8


static func create(parent: Node2D, amount: int) -> void:
	var popup := DamagePopup.new()
	popup.damage_amount = amount
	popup.position = Vector2(0, -30)
	parent.add_child(popup)
