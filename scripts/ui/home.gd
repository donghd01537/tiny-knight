extends Node2D
## Home Screen
## Bottom menu bar with 5 items: characters, equipments, main, shop, event
## Shop and event are locked (lock.png overlay in bottom-right)

var _selected_index := 2  # Default: main (center)
var _menu_bgs: Array = []
var _labels: Array = []

var _menu_tex: Texture2D
var _menu_active_tex: Texture2D
var _lock_tex: Texture2D

var _item_names := ["characters", "equipments", "main", "shop", "event"]
var _item_icons := [
	"res://assets/icons/characters.png",
	"res://assets/icons/equipments.png",
	"res://assets/icons/main.png",
	"res://assets/icons/shop.png",
	"res://assets/icons/event.png",
]
var _item_locked := [false, false, false, true, true]

var _equipment_select_scene := preload("res://scenes/ui/EquipmentSelect.tscn")


func _ready() -> void:
	_menu_tex = load("res://assets/menu/menu.png")
	_menu_active_tex = load("res://assets/menu/menu_active.png")
	_lock_tex = load("res://assets/icons/lock.png")
	_build_ui()


func _build_ui() -> void:
	var vp_w := 728.0
	var vp_h := 1280.0

	# Use a CanvasLayer so all UI (Controls) render properly
	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)

	# Full-screen root control
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(vp_w, vp_h)
	ui_layer.add_child(root)

	# Background image
	var bg_tex: Texture2D = load("res://assets/backgrounds/main_bg.png")
	var bg := TextureRect.new()
	bg.texture = bg_tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.position = Vector2.ZERO
	bg.size = Vector2(vp_w, vp_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Menu bar layout
	var tile_size := 120.0
	var item_count := _item_names.size()
	var total_w := tile_size * item_count
	var gap := (vp_w - total_w) / float(item_count + 1)
	var menu_y := 800.0
	print("HOME: Building menu at y=", menu_y, " items=", item_count)

	for i in item_count:
		var item_x := gap + i * (tile_size + gap)

		# Tile background
		var tile_bg := TextureRect.new()
		if i == _selected_index:
			tile_bg.texture = _menu_active_tex
		else:
			tile_bg.texture = _menu_tex
		tile_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile_bg.stretch_mode = TextureRect.STRETCH_SCALE
		tile_bg.position = Vector2(item_x, menu_y)
		tile_bg.size = Vector2(tile_size, tile_size)
		tile_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tile_bg)
		_menu_bgs.append(tile_bg)

		# Icon centered on tile
		var icon_tex: Texture2D = load(_item_icons[i])
		var icon_size := 80.0
		var icon_offset := (tile_size - icon_size) / 2.0
		var icon_rect := TextureRect.new()
		icon_rect.texture = icon_tex
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.position = Vector2(item_x + icon_offset, menu_y + icon_offset)
		icon_rect.size = Vector2(icon_size, icon_size)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(icon_rect)

		# Lock overlay
		if _item_locked[i]:
			var lock_size := 40.0
			var lock_rect := TextureRect.new()
			lock_rect.texture = _lock_tex
			lock_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lock_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			lock_rect.position = Vector2(
				item_x + tile_size - lock_size - 4.0,
				menu_y + tile_size - lock_size - 4.0
			)
			lock_rect.size = Vector2(lock_size, lock_size)
			lock_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(lock_rect)

		# Clickable button overlay
		var btn := TextureButton.new()
		btn.ignore_texture_size = true
		btn.position = Vector2(item_x, menu_y)
		btn.size = Vector2(tile_size, tile_size)
		btn.pressed.connect(_on_menu_pressed.bind(i))
		root.add_child(btn)

		# Label below tile
		var label := Label.new()
		label.text = _item_names[i].capitalize()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(item_x, menu_y + tile_size + 4.0)
		label.size = Vector2(tile_size, 24.0)
		label.add_theme_font_size_override("font_size", 16)
		if i == _selected_index:
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		root.add_child(label)
		_labels.append(label)

	# Start Battle button (using primary.png) — above menu
	var primary_tex: Texture2D = load("res://assets/common/buttons/primary.png")
	var btn_w := 400.0
	var btn_h := btn_w * (float(primary_tex.get_height()) / float(primary_tex.get_width()))
	var btn_x := (vp_w - btn_w) / 2.0
	var btn_y := menu_y - btn_h - 40.0

	var btn_bg := TextureRect.new()
	btn_bg.texture = primary_tex
	btn_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	btn_bg.stretch_mode = TextureRect.STRETCH_SCALE
	btn_bg.position = Vector2(btn_x, btn_y)
	btn_bg.size = Vector2(btn_w, btn_h)
	btn_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(btn_bg)

	var start_btn := Button.new()
	start_btn.text = "START BATTLE"
	start_btn.flat = true
	start_btn.position = Vector2(btn_x, btn_y + 10.0)
	start_btn.size = Vector2(btn_w, btn_h - 10.0)
	start_btn.add_theme_font_size_override("font_size", 28)
	start_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	start_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.7))
	start_btn.pressed.connect(_on_start_battle)
	root.add_child(start_btn)


func _on_start_battle() -> void:
	get_tree().change_scene_to_file("res://scenes/world/Battle.tscn")


func _on_menu_pressed(index: int) -> void:
	if _item_locked[index]:
		return
	_selected_index = index
	for i in _menu_bgs.size():
		if i == _selected_index:
			_menu_bgs[i].texture = _menu_active_tex
		else:
			_menu_bgs[i].texture = _menu_tex
	for i in _labels.size():
		if i == _selected_index:
			_labels[i].add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		else:
			_labels[i].add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))

	match _item_names[index]:
		"equipments":
			_show_equipment_select()
		"main":
			_on_start_battle()


func _show_equipment_select() -> void:
	var equip_ui := _equipment_select_scene.instantiate()
	add_child(equip_ui)
	equip_ui.battle_started.connect(_on_equipment_confirmed)


func _on_equipment_confirmed(armor_name: String, weapon_name: String) -> void:
	GameData.armor_name = armor_name
	GameData.weapon_name = weapon_name
