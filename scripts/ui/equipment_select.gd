extends CanvasLayer
## Equipment Selection Screen
## Shows before battle starts. Player selects armor & weapon, then starts battle.
## Tab icons (armor/weapon) switch which inventory is shown in the grid.
## Default: "royal" armor, "book" weapon. Cannot unequip.

signal battle_started(armor_name: String, weapon_name: String)

const ARMORS := ["royal", "neromancer"]
const WEAPONS := ["axe", "book", "blade"]
const PREVIEW_FPS := 4.0

enum Tab { ARMOR, WEAPON }

var selected_armor: String = "royal"
var selected_weapon: String = "axe"
var _current_tab: int = Tab.ARMOR

var _root: Control

# Equipment slots
var _equipped_armor_icon: TextureRect
var _equipped_weapon_icon: TextureRect

# Tab buttons
var _armor_tab_btn: TextureButton
var _weapon_tab_btn: TextureButton
var _armor_tab_highlight: ColorRect
var _weapon_tab_highlight: ColorRect

# Inventory grid items (rebuilt on tab switch)
var _grid_container: Control
var _selection_highlights: Dictionary = {}

# Character preview
var _preview_armor_layer: TextureRect
var _preview_char_layer: TextureRect
var _preview_armor_tex: Texture2D
var _preview_char_tex: Texture2D
var _preview_frame := 0
var _preview_total_frames := 0
var _preview_timer := 0.0
var _preview_frame_size := 0

# Layout values (stored for grid rebuild)
var _grid_x := 0.0
var _grid_y := 0.0
var _cell_size := 0.0
var _box_size := 0.0
var _box_tex: Texture2D
var _cols := 4
var _rows := 4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _process(delta: float) -> void:
	if _preview_total_frames <= 0:
		return
	_preview_timer += delta
	if _preview_timer >= 1.0 / PREVIEW_FPS:
		_preview_timer -= 1.0 / PREVIEW_FPS
		_preview_frame = (_preview_frame + 1) % _preview_total_frames
		_apply_preview_frame()


func _build_ui() -> void:
	var vp_w := 728.0
	var vp_h := 1280.0

	# Full-screen root control
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.75)
	_root.add_child(overlay)

	# Inventory background (centered)
	var inv_tex := load("res://assets/inventory/inventory.png") as Texture2D
	var tex_w := float(inv_tex.get_width())
	var tex_h := float(inv_tex.get_height())
	var target_w := vp_w * 0.68
	var scale_f := target_w / tex_w
	var panel_w := tex_w * scale_f
	var panel_h := tex_h * scale_f
	var panel_x := (vp_w - panel_w) / 2.0
	var panel_y := (vp_h - panel_h) / 2.0 - 200.0

	var inv_bg := TextureRect.new()
	inv_bg.texture = inv_tex
	inv_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	inv_bg.stretch_mode = TextureRect.STRETCH_SCALE
	inv_bg.position = Vector2(panel_x, panel_y)
	inv_bg.size = Vector2(panel_w, panel_h)
	inv_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(inv_bg)

	# --- Equipment section ---
	var slot_size := panel_w * 0.17
	var eq_y := panel_y + panel_h * 0.07 + 20.0

	# Left equipment slot (armor)
	var eq_armor_x := panel_x + panel_w * 0.11
	_equipped_armor_icon = TextureRect.new()
	_equipped_armor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_equipped_armor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_equipped_armor_icon.position = Vector2(eq_armor_x, eq_y)
	_equipped_armor_icon.size = Vector2(slot_size, slot_size)
	_equipped_armor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_equipped_armor_icon)

	# Right equipment slot (weapon)
	var eq_weapon_x := panel_x + panel_w - panel_w * 0.11 - slot_size
	_equipped_weapon_icon = TextureRect.new()
	_equipped_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_equipped_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_equipped_weapon_icon.position = Vector2(eq_weapon_x, eq_y)
	_equipped_weapon_icon.size = Vector2(slot_size, slot_size)
	_equipped_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_equipped_weapon_icon)

	_update_equipped_icons()

	# --- Character idle preview (centered between equipment slots) ---
	var preview_size := slot_size * 1.6
	var preview_x := panel_x + (panel_w - preview_size) / 2.0
	var preview_y := eq_y + (slot_size - preview_size) / 2.0 + 10.0

	_preview_armor_layer = TextureRect.new()
	_preview_armor_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_armor_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_armor_layer.position = Vector2(preview_x, preview_y)
	_preview_armor_layer.size = Vector2(preview_size, preview_size)
	_preview_armor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_armor_layer.z_index = 0
	_root.add_child(_preview_armor_layer)

	_preview_char_layer = TextureRect.new()
	_preview_char_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_char_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_char_layer.position = Vector2(preview_x, preview_y)
	_preview_char_layer.size = Vector2(preview_size, preview_size)
	_preview_char_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_char_layer.z_index = 1
	_root.add_child(_preview_char_layer)

	_load_preview_textures()

	# --- Tab buttons (armor/weapon icons to switch inventory) ---
	var tab_icon_size := 48.0
	var tab_y := panel_y + panel_h * 0.34
	var tab_gap := 16.0
	var tabs_total_w := tab_icon_size * 2 + tab_gap
	var tab_start_x := panel_x + (panel_w - tabs_total_w) / 2.0

	# Armor tab highlight
	_armor_tab_highlight = ColorRect.new()
	_armor_tab_highlight.position = Vector2(tab_start_x - 4, tab_y - 4)
	_armor_tab_highlight.size = Vector2(tab_icon_size + 8, tab_icon_size + 8)
	_armor_tab_highlight.color = Color(1.0, 0.84, 0.0, 0.5)
	_armor_tab_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_armor_tab_highlight)

	# Weapon tab highlight
	_weapon_tab_highlight = ColorRect.new()
	_weapon_tab_highlight.position = Vector2(tab_start_x + tab_icon_size + tab_gap - 4, tab_y - 4)
	_weapon_tab_highlight.size = Vector2(tab_icon_size + 8, tab_icon_size + 8)
	_weapon_tab_highlight.color = Color(1.0, 0.84, 0.0, 0.5)
	_weapon_tab_highlight.visible = false
	_weapon_tab_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_weapon_tab_highlight)

	# Armor tab button
	var armor_tab_tex := load("res://assets/icons/armor.png") as Texture2D
	_armor_tab_btn = TextureButton.new()
	_armor_tab_btn.texture_normal = armor_tab_tex
	_armor_tab_btn.ignore_texture_size = true
	_armor_tab_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_armor_tab_btn.position = Vector2(tab_start_x, tab_y)
	_armor_tab_btn.size = Vector2(tab_icon_size, tab_icon_size)
	_armor_tab_btn.pressed.connect(_on_tab_pressed.bind(Tab.ARMOR))
	_root.add_child(_armor_tab_btn)

	# Weapon tab button
	var weapon_tab_tex := load("res://assets/icons/weapon.png") as Texture2D
	_weapon_tab_btn = TextureButton.new()
	_weapon_tab_btn.texture_normal = weapon_tab_tex
	_weapon_tab_btn.ignore_texture_size = true
	_weapon_tab_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_tab_btn.position = Vector2(tab_start_x + tab_icon_size + tab_gap, tab_y)
	_weapon_tab_btn.size = Vector2(tab_icon_size, tab_icon_size)
	_weapon_tab_btn.pressed.connect(_on_tab_pressed.bind(Tab.WEAPON))
	_root.add_child(_weapon_tab_btn)

	# --- Inventory grid (4x4 with box.png backgrounds) ---
	_box_tex = load("res://assets/inventory/box.png") as Texture2D
	var grid_w := panel_w * 0.72
	_cell_size = grid_w / float(_cols)
	_grid_x = panel_x + (panel_w - grid_w) / 2.0
	_grid_y = panel_y + panel_h * 0.44
	var box_gap := 4.0 * scale_f
	_box_size = _cell_size - box_gap

	# Grid container holds all grid items (rebuilt on tab switch)
	_grid_container = Control.new()
	_grid_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_grid_container)

	_rebuild_grid()

	# --- Start Battle button (below panel, using primary.png) ---
	var primary_tex := load("res://assets/common/buttons/primary.png") as Texture2D
	var btn_w := panel_w * 0.75
	var btn_h := btn_w * (float(primary_tex.get_height()) / float(primary_tex.get_width()))
	var btn_x := panel_x + (panel_w - btn_w) / 2.0
	var btn_y := panel_y + panel_h + 20.0

	# Button background
	var btn_bg := TextureRect.new()
	btn_bg.texture = primary_tex
	btn_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	btn_bg.stretch_mode = TextureRect.STRETCH_SCALE
	btn_bg.position = Vector2(btn_x, btn_y)
	btn_bg.size = Vector2(btn_w, btn_h)
	btn_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(btn_bg)

	# Clickable button overlay with text
	var start_btn := Button.new()
	start_btn.text = "BACK"
	start_btn.flat = true
	start_btn.position = Vector2(btn_x, btn_y + 10.0)
	start_btn.size = Vector2(btn_w, btn_h - 10.0)
	start_btn.add_theme_font_size_override("font_size", 28)
	start_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	start_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.7))
	start_btn.pressed.connect(_on_start_pressed)
	_root.add_child(start_btn)


func _rebuild_grid() -> void:
	# Clear old grid items
	for child in _grid_container.get_children():
		child.queue_free()
	_selection_highlights.clear()

	# Draw 4x4 box backgrounds
	for r in _rows:
		for c in _cols:
			var bx := _grid_x + c * _cell_size
			var by := _grid_y + r * _cell_size
			var box_bg := TextureRect.new()
			box_bg.texture = _box_tex
			box_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			box_bg.stretch_mode = TextureRect.STRETCH_SCALE
			box_bg.position = Vector2(bx, by)
			box_bg.size = Vector2(_box_size, _box_size)
			box_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid_container.add_child(box_bg)

	# Place items based on current tab
	var items: Array
	var selected: String
	var icon_path_template: String
	if _current_tab == Tab.ARMOR:
		items = ARMORS
		selected = selected_armor
		icon_path_template = "res://assets/sprites/armors/%s/icon.png"
	else:
		items = WEAPONS
		selected = selected_weapon
		icon_path_template = "res://assets/sprites/weapons/%s/icon.png"

	for i in items.size():
		var item_name: String = items[i]
		var icon_tex := load(icon_path_template % item_name) as Texture2D

		var col := i % _cols
		var row := i / _cols
		var btn_x := _grid_x + col * _cell_size
		var btn_y := _grid_y + row * _cell_size

		# Selection highlight
		var highlight := ColorRect.new()
		highlight.position = Vector2(btn_x - 3, btn_y - 3)
		highlight.size = Vector2(_box_size + 6, _box_size + 6)
		highlight.color = Color(1.0, 0.84, 0.0, 0.5)
		highlight.visible = (item_name == selected)
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid_container.add_child(highlight)
		_selection_highlights[item_name] = highlight

		# Clickable icon
		var btn := TextureButton.new()
		btn.texture_normal = icon_tex
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.position = Vector2(btn_x, btn_y)
		btn.size = Vector2(_box_size, _box_size)
		btn.pressed.connect(_on_item_pressed.bind(item_name))
		_grid_container.add_child(btn)


func _on_tab_pressed(tab: int) -> void:
	_current_tab = tab
	_armor_tab_highlight.visible = (tab == Tab.ARMOR)
	_weapon_tab_highlight.visible = (tab == Tab.WEAPON)
	_rebuild_grid()


func _on_item_pressed(item_name: String) -> void:
	if _current_tab == Tab.ARMOR:
		selected_armor = item_name
		_load_preview_textures()
	else:
		selected_weapon = item_name
	_update_equipped_icons()
	for key in _selection_highlights:
		var is_selected: bool
		if _current_tab == Tab.ARMOR:
			is_selected = (key == selected_armor)
		else:
			is_selected = (key == selected_weapon)
		_selection_highlights[key].visible = is_selected


func _update_equipped_icons() -> void:
	var armor_tex := load("res://assets/sprites/armors/%s/icon.png" % selected_armor) as Texture2D
	_equipped_armor_icon.texture = armor_tex
	var weapon_tex := load("res://assets/sprites/weapons/%s/icon.png" % selected_weapon) as Texture2D
	_equipped_weapon_icon.texture = weapon_tex


func _load_preview_textures() -> void:
	_preview_char_tex = load("res://assets/sprites/characters/breaker/idle.png") as Texture2D
	_preview_armor_tex = load("res://assets/sprites/armors/%s/idle.png" % selected_armor) as Texture2D

	if _preview_armor_tex:
		var h := _preview_armor_tex.get_height()
		_preview_frame_size = h
		_preview_total_frames = _preview_armor_tex.get_width() / h
	else:
		_preview_total_frames = 0

	_preview_frame = 0
	_preview_timer = 0.0
	_apply_preview_frame()


func _apply_preview_frame() -> void:
	if _preview_total_frames <= 0:
		return
	var region := Rect2(
		_preview_frame * _preview_frame_size, 0,
		_preview_frame_size, _preview_frame_size
	)
	if _preview_armor_tex:
		var atlas := AtlasTexture.new()
		atlas.atlas = _preview_armor_tex
		atlas.region = region
		_preview_armor_layer.texture = atlas
	if _preview_char_tex:
		var char_atlas := AtlasTexture.new()
		char_atlas.atlas = _preview_char_tex
		char_atlas.region = region
		_preview_char_layer.texture = char_atlas


func _on_start_pressed() -> void:
	battle_started.emit(selected_armor, selected_weapon)
	queue_free()
