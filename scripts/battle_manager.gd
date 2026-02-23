extends Node2D
## Battle Manager
## Spawns enemies until hero dies, then ends the demo

signal game_over

@export var spawn_interval_start: float = 2.0
@export var spawn_interval_min: float = 0.6
@export var spawn_speedup_rate: float = 0.01  ## Seconds faster per spawn
var spawn_interval: float = 2.0
@export var spawn_y_min: float = 200.0
@export var spawn_y_max: float = 990.0
@export var spawn_x_min: float = 100.0
@export var spawn_x_max: float = 628.0

var goblin_scene := preload("res://scenes/actors/Goblin.tscn")
var wolf_scene := preload("res://scenes/actors/Wolf.tscn")
var devil_scene := preload("res://scenes/actors/Devil.tscn")
var summon_effect_scene := preload("res://scenes/effects/SummonEffect.tscn")

var spawn_timer: float = 0.0
var hero: Node2D = null
var is_game_over: bool = false
var enemies_killed: int = 0

@onready var game_over_label: Label = $GameOverLabel


func _ready() -> void:
	# Setup game over label
	if game_over_label:
		game_over_label.visible = false

	# Find hero and apply equipment from GameData
	call_deferred("_deferred_init")


func _deferred_init() -> void:
	setup_hero()
	_apply_equipment()


func _apply_equipment() -> void:
	if hero:
		var anim = hero.get_node_or_null("BreakerAnimation")
		if anim and GameData.weapon_name != "":
			anim.change_weapon(GameData.weapon_name)


func setup_hero() -> void:
	var heroes := get_tree().get_nodes_in_group("heroes")
	for h in heroes:
		var is_hero := h.get_node_or_null("BreakerAnimation")
		if is_hero:
			if not hero:
				hero = h  # Primary hero for game-over tracking
			var hero_combatant := h.get_node_or_null("Combatant") as Combatant
			if hero_combatant:
				hero_combatant.died.connect(_on_hero_died)
		else:
			# Tower or other structure
			var struct_combatant := h.get_node_or_null("Combatant") as Combatant
			if struct_combatant:
				struct_combatant.died.connect(_on_tower_died)


func _process(delta: float) -> void:
	if is_game_over:
		return

	spawn_timer += delta
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		for i in 2:
			spawn_random_enemy()
		spawn_interval = maxf(spawn_interval_min, spawn_interval - spawn_speedup_rate)


func spawn_random_enemy() -> void:
	# Random position within playable area
	var top_30 := spawn_y_min + (spawn_y_max - spawn_y_min) * 0.3
	var spawn_pos := Vector2(
		randf_range(spawn_x_min, spawn_x_max),
		randf_range(spawn_y_min, top_30)
	)

	# Play summon effect first, then spawn enemy
	var summon := summon_effect_scene.instantiate()
	summon.position = spawn_pos
	add_child(summon)

	# Random enemy type (40% goblin, 35% wolf, 25% devil)
	var roll := randf()
	summon.summon_finished.connect(_on_summon_finished.bind(spawn_pos, roll))


func _on_summon_finished(spawn_pos: Vector2, roll: float) -> void:
	var enemy: Node2D
	if roll < 0.4:
		enemy = goblin_scene.instantiate()
	elif roll < 0.75:
		enemy = wolf_scene.instantiate()
	else:
		enemy = devil_scene.instantiate()

	enemy.position = spawn_pos
	add_child(enemy)

	var enemy_combatant := enemy.get_node_or_null("Combatant") as Combatant
	if enemy_combatant:
		enemy_combatant.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	enemies_killed += 1


func _on_tower_died() -> void:
	pass  # Tower destroyed — battle continues


func _on_hero_died() -> void:
	is_game_over = true
	game_over.emit()

	# Show game over
	if game_over_label:
		game_over_label.text = "GAME OVER\n\nEnemies Killed: %d\n\nPress R to Return Home" % enemies_killed
		game_over_label.visible = true


func _input(event: InputEvent) -> void:
	if is_game_over and event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().change_scene_to_file("res://scenes/ui/Home.tscn")
