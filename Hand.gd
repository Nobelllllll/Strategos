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

	# ✅ Si Hand.size.x est 0 (pas encore calculé par le layout), on force une largeur par défaut
	var available_width = size.x
	if available_width <= 0:
		# largeur par défaut = taille du plateau pour éviter un calcul explosif
		available_width = game_manager.renderer.size.x

	# ✅ On récupère la taille des cases du plateau pour que les cartes soient cohérentes
	var cell_size = game_manager.renderer.get_dynamic_cell_size()
	if cell_size.x <= 0:
		# fallback si le plateau n'a pas encore été calculé
		cell_size = Vector2(120, 60)

	var card_width = cell_size.x * 0.9
	var card_height = card_width / 2.0

	# ✅ Espacement de base
	var spacing = base_spacing

	# ✅ Largeur totale avec espacement normal
	var total_width = n * card_width + (n - 1) * base_spacing

	# ✅ Si ça dépasse → chevauchement dynamique
	if total_width > available_width:
		spacing = (available_width - n * card_width) / (n - 1)
		spacing = max(spacing, max_overlap)


	# ✅ Alignement à gauche
	var start_x = 0.0

	for i in range(n):
		var c = get_child(i)
		c.custom_minimum_size = Vector2(card_width, card_height)
		c.size = c.custom_minimum_size

		# ✅ CENTRAGE VERTICAL dans le Hand
		var y_center = (size.y - card_height) / 2.0

		c.position = Vector2(start_x + i * (card_width + spacing), y_center)

		# ✅ Forcer le Panel interne à suivre la taille
		if c.has_node("Panel"):
			var p = c.get_node("Panel")
			p.set_anchors_preset(Control.PRESET_FULL_RECT)
			p.size = c.size

		# ✅ DEBUG : essayer de voir si le VBoxContainer est compressé
		if c.has_node("Panel/VBoxContainer"):
			var vbox = c.get_node("Panel/VBoxContainer")
			# On met un fond rouge semi-transparent pour voir s'il est dessiné
			vbox.add_theme_color_override("bg_color", Color(1, 0, 0, 0.5))
			




func _notification(what):
	if what == NOTIFICATION_RESIZED:
		await get_tree().process_frame
		update_card_positions()
