extends Control
## Virtual Joystick — display only.
## Hidden by default. PlayerHUD owns all touch events and calls begin/update_drag/release.

const RADIUS := 64.0  ## Max drag distance from center (px)

var direction := Vector2.ZERO

@onready var _knob: Control = $Knob


func _ready() -> void:
	visible = false
	call_deferred("_reset_knob")


## Show joystick centred on screen_pos and reset knob to center.
func begin(screen_pos: Vector2) -> void:
	position = screen_pos - size * 0.5
	visible = true
	_reset_knob()


## Update knob position and direction from current drag screen position.
func update_drag(screen_pos: Vector2) -> void:
	var offset := screen_pos - (position + size * 0.5)
	var clamped := offset.limit_length(RADIUS)
	direction = clamped / RADIUS
	if _knob:
		_knob.position = size * 0.5 + clamped - _knob.size * 0.5


## Hide joystick and clear direction.
func release() -> void:
	visible = false
	direction = Vector2.ZERO
	_reset_knob()


func _reset_knob() -> void:
	if _knob:
		_knob.position = size * 0.5 - _knob.size * 0.5
