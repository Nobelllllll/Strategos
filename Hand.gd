extends Control

@export var game_manager: GameManager

@onready var renderer: BoardRenderer = game_manager.renderer if game_manager else null
@onready var children_cards: Array = get_children()

var base_spacing := 20
var max_overlap := -120
var hand_max_width := 600

func add_card_to_hand(card: StrategosCard, unit_name: String = ""):
	if card.get_parent():
		card.get_parent().remove_child(card)

	var cell_size: Vector2 = Vector2(120, 60)
	if game_manager != null and game_manager.renderer != null:
		cell_size = game_manager.renderer.get_dynamic_cell_size()

	var width = cell_size.x * 0.9
	var height = width / 2.0
	card.custom_minimum_size = Vector2(width, height)
	card.size = card.custom_minimum_size

	if card.has_node("Panel"):
		var p = card.get_node("Panel")
		p.set_anchors_preset(Control.PRESET_FULL_RECT)
		p.size = card.size

	card.set_selected(false)
	card.modulate = Color(1, 1, 1)

	if unit_name != "":
		var unit_data = game_manager.units_data[unit_name]
		card.game_manager = game_manager  # 🔧 Fix ajouté ici
		card.setup_from_unit_data(unit_data, cell_size, game_manager.current_player)

	add_child(card)
	update_card_positions()





func debug_labels(card: Control):
	var label_name = card.get_node("Panel/VBoxContainer/Label_Name")
	var label_hp = card.get_node("Panel/VBoxContainer/Label_HP")
	
	if label_name:
		# 🔴 Force une couleur visible
		label_name.add_theme_color_override("font_color", Color(1, 0, 0))
		# 🔴 Force une taille minimale
		label_name.custom_minimum_size = Vector2(200, 30)
		label_name.visible = true
	
	if label_hp:
		label_hp.add_theme_color_override("font_color", Color(0, 1, 0))
		label_hp.custom_minimum_size = Vector2(200, 30)
		label_hp.visible = true


func update_card_positions():
	var n = get_child_count()
	if n == 0:
		return

	# taille du plateau pour rester cohérent
	var cell_size = game_manager.renderer.get_dynamic_cell_size()
	if cell_size.x <= 0:
		cell_size = Vector2(120, 60)

	# on garde le même ratio que chez toi
	var card_width = cell_size.x * 0.9
	var card_height = card_width / 2.0

	# on va empiler VERTICAL
	var available_height = size.y
	if available_height <= 0:
		# si le Hand n'a pas encore de taille, on prend la hauteur du renderer
		available_height = game_manager.renderer.size.y

	var spacing = base_spacing

	# hauteur totale si on mettait les cartes sans chevauchement
	var total_height = n * card_height + (n - 1) * spacing

	# si ça dépasse, on réduit l'espacement (comme tu faisais en horizontal)
	if total_height > available_height:
		spacing = (available_height - n * card_height) / (n - 1)
		if spacing < max_overlap:
			spacing = max_overlap

	# on centre sur X dans la main
	var x_center = (size.x - card_width) / 2.0
	# on part du haut
	var start_y = 0.0

	for i in range(n):
		var c = get_child(i)
		c.custom_minimum_size = Vector2(card_width, card_height)
		c.size = c.custom_minimum_size

		var y = start_y + i * (card_height + spacing)
		c.position = Vector2(x_center, y)

		if c.has_node("Panel"):
			var p = c.get_node("Panel")
			p.set_anchors_preset(Control.PRESET_FULL_RECT)
			p.size = c.size

		if c.has_node("Panel/VBoxContainer"):
			var vbox = c.get_node("Panel/VBoxContainer")
			vbox.add_theme_color_override("bg_color", Color(1, 0, 0, 0.5))



func _notification(what):
	if what == NOTIFICATION_RESIZED:
		await get_tree().process_frame
		update_card_positions()
