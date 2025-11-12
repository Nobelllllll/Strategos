extends Control

class_name BoardRenderer

@export var board: Node
@export var game_manager: Node
@export var card_scene: PackedScene
@onready var card_container: Control = $CardContainer

var font: Font = null
var selected_unit_info: Dictionary = {}
var turn_start_positions: Dictionary = {}
var warning_message: String = ""
var warning_timer := 0.0
var current_player: String = ""
var cards: Dictionary = {}
var is_flipped_view := false

var tactic_overlay: ColorRect = null


func _ready():
	update_offset()
	
	tactic_overlay = ColorRect.new()
	tactic_overlay.color = Color(0.2, 0.6, 1.0, 0.25)
	tactic_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # 👈 bloque tous les clics dessous
	tactic_overlay.z_index = 1000  # 👈 assure qu’il est tout au-dessus
	add_child(tactic_overlay)
	tactic_overlay.visible = false
	
	tactic_overlay.gui_input.connect(_on_tactic_overlay_input)




	# ✅ Création initiale pour avoir au moins un plateau vide
	# (les cartes créées ici auront taille 0 mais seront remplacées)
	generate_cards()

	# ✅ Après 1 frame, la taille réelle est connue → on force un rebuild complet
	call_deferred("_refresh_after_first_frame")

func _refresh_after_first_frame():
	clear_cards()
	generate_cards()
	queue_redraw()



func update_offset():
	custom_minimum_size = Vector2(
		(board.GRID_WIDTH + 1) * board.CELL_SIZE.x,
		board.GRID_HEIGHT * board.CELL_SIZE.y
	)

func get_dynamic_cell_size() -> Vector2:
	var available_width = size.x
	var available_height = size.y
	var cs = Vector2(
		available_width / (board.GRID_WIDTH + 1),
		available_height / board.GRID_HEIGHT
	)

	return cs

	

func flip_position(pos: Vector2i) -> Vector2i:
	if not is_flipped_view:
		return pos
	return Vector2i(pos.x, board.GRID_HEIGHT - 1 - pos.y)

func generate_cards():
	clear_cards()

	# ✅ Rouges
	for unit_pos in board.red_units.keys():
		var unit_data = board.red_units[unit_pos]

		var unit_type: String
		if typeof(unit_data) == TYPE_DICTIONARY:
			unit_type = unit_data["type"]
		else:
			unit_type = unit_data  # rétrocompatibilité avec les strings

		var card = _create_card(unit_pos, "RED", unit_type)
		card.update_grayscale()  # ✅ Applique le bon état visuel

	# ✅ Bleus
	for unit_pos in board.blue_units.keys():
		var unit_data = board.blue_units[unit_pos]

		var unit_type: String
		if typeof(unit_data) == TYPE_DICTIONARY:
			unit_type = unit_data["type"]
		else:
			unit_type = unit_data  # rétrocompatibilité avec les strings

		var card = _create_card(unit_pos, "BLUE", unit_type)
		card.update_grayscale()  # ✅ Applique le bon état visuel

	# ✅ Mise à jour des couleurs (au cas où)
	if game_manager:
		for card in cards.values():
			card.add_theme_stylebox_override("panel", card.get_default_style())


func _create_card(pos: Vector2i, player: String, unit_type: String = "Hoplite") -> StrategosCard:
	var card = card_scene.instantiate() as StrategosCard
	card_container.add_child(card)

	var cell_size = get_dynamic_cell_size()
	if cell_size == Vector2(0, 0):
		cell_size = Vector2(120, 60)

	card.game_manager = game_manager  # Toujours AVANT le setup

	# --- Récupération des données du modèle à cette position ---
	var raw_unit_data = null
	if player == "RED":
		if board.red_units.has(pos):
			raw_unit_data = board.red_units[pos]
	else:
		if board.blue_units.has(pos):
			raw_unit_data = board.blue_units[pos]

	# --- Valeurs par défaut ---
	var uid_in_model: int = 0
	var unit_data_dict: Dictionary = {}
	var is_commander := false

	# --- Déduire type/uid/commander + construire unit_data_dict (si unité classique) ---
	if typeof(raw_unit_data) == TYPE_DICTIONARY:
		# type / uid
		if raw_unit_data.has("type"):
			unit_type = str(raw_unit_data["type"])
		if raw_unit_data.has("uid"):
			uid_in_model = int(raw_unit_data["uid"])

		# commander ?
		if raw_unit_data.has("is_commander"):
			if bool(raw_unit_data["is_commander"]) == true:
				is_commander = true

		# données complètes pour une unité classique
		if not is_commander:
			unit_data_dict = {
				"name": unit_type,
				"hp": raw_unit_data.get("hp", 0),
				"move_range": raw_unit_data.get("move_range", 1),
				"attacks": game_manager.units_data.get(unit_type, {}).get("attacks", []),
				"defenses": game_manager.units_data.get(unit_type, {}).get("defenses", [])
			}
	else:
		# rétrocompat : si c'est un string (ancien format)
		if game_manager and game_manager.units_data.has(unit_type):
			unit_data_dict = game_manager.units_data[unit_type]
		else:
			unit_data_dict = {"name": "??", "hp": 0, "move_range": 1}

	# --- Assigner UID à la carte UI ---
	if uid_in_model != 0:
		card.uid = uid_in_model
	elif game_manager:
		game_manager.assign_uid_to_card(card)

	# --- Setup visuel selon le type (commandant vs unité classique) ---
	if is_commander:
		# Passe les données pour que la carte puisse afficher le nom
		card.setup_as_commander(cell_size, player, raw_unit_data)

	else:
		# Unité classique
		card.setup_from_unit_data(unit_data_dict, cell_size, player)

	# --- Infos communes ---
	card.cell = pos
	card.player_color = player
	card.set_meta("unit_type", unit_type)

	# Style par défaut (couleur selon perspective)
	if card.panel:
		card.panel.add_theme_stylebox_override("panel", card.get_default_style())

	# Enregistrement
	cards[pos] = card

	# Mises à jour UI (sans effet pour les commandants, mais sans danger)
	card.update_attack_buttons()
	card.update_defense_buttons()
	card.update_defense_button_states()
	card.update_grayscale()

	return card




func clear_cards():
	for c in cards.values():
		c.queue_free()
	cards.clear()

func update_cards_positions():
	var cell_size = get_dynamic_cell_size()
	for card in cards.values():
		card.update_position(cell_size, is_flipped_view, board.GRID_WIDTH, board.GRID_HEIGHT)



func _process(delta):
	if warning_timer > 0:
		warning_timer -= delta
		if warning_timer <= 0:
			warning_message = ""
			queue_redraw()

	# afficher/cacher l’overlay de tactique
	if tactic_overlay != null and game_manager != null:
		if game_manager.is_tactic_mode:
			tactic_overlay.visible = true
			_update_tactic_overlay_rect()
		else:
			tactic_overlay.visible = false


func _draw():
	

	var cell_size = get_dynamic_cell_size()

	for x in range(board.GRID_WIDTH):
		for y in range(board.GRID_HEIGHT):
			var draw_y = y
			if is_flipped_view:
				draw_y = board.GRID_HEIGHT - 1 - y
			var pos = Vector2(x + 1, draw_y) * cell_size
			draw_rect(Rect2(pos, cell_size), Color(1, 1, 1, 0.2), false)

	for y in range(board.GRID_HEIGHT):
		var draw_y = y
		if is_flipped_view:
			draw_y = board.GRID_HEIGHT - 1 - y
		var pos = Vector2(0, draw_y) * cell_size
		var size = cell_size * 0.9
		var offset = (cell_size - size) / 2
		draw_rect(Rect2(pos + offset, size), Color(0.7, 0.7, 0.7, 0.3), true)
	
	if game_manager != null:
		if game_manager.is_tactic_mode:
			_draw_tactic_overlay()


	draw_move_highlights()
	draw_warning()

func draw_move_highlights():
	var cell_size = get_dynamic_cell_size()

	if selected_unit_info.has("origin"):
		var origin = selected_unit_info["origin"]
		print("🎯 draw_move_highlights → origin sélectionné :", origin)

		# ✅ Zone autorisée (jaune clair), sauf case actuelle ou interdite
		var current = game_manager.selected_unit_info.get("current", Vector2i(-1, -1))

		for pos in game_manager.current_move_zone:
			if pos != origin and pos != current and not pos in game_manager.current_forbidden_zone:
				var flipped = flip_position_180(pos)
				draw_rect(
					Rect2((Vector2(flipped) + Vector2(1, 0)) * cell_size, cell_size),
					Color(1, 1, 0, 0.3),
					true
				)

		# ✅ Case d'origine (jaune opaque, ou atténué si interdite IIH), seulement si vide
		if not cards.has(origin):
			var flipped = flip_position_180(origin)
			var base_color := Color(1, 1, 0, 0.6)

			if game_manager.current_forbidden_zone.has(origin):
				base_color = Color(1, 1, 0, 0.2)  # Moins visible si IIH

			draw_rect(
				Rect2((Vector2(flipped) + Vector2(1, 0)) * cell_size, cell_size),
				base_color,
				true
			)

		# ✅ Zone interdite IIH (orange)
		if game_manager.current_forbidden_zone.is_empty():
			print("⚠️ Aucune case interdite IIH à colorer")
		else:
			print("🟧 Cases interdites IIH à afficher :", game_manager.current_forbidden_zone)

		for pos in game_manager.current_forbidden_zone:
			var flipped = flip_position_180(pos)
			print("🟧 Dessin case interdite :", pos, " → après flip :", flipped)
			draw_rect(
				Rect2((Vector2(flipped) + Vector2(1, 0)) * cell_size, cell_size),
				Color(1, 0.5, 0, 0.3),
				true
			)
		
		# ✅ Si une carte de la main (commandant) est sélectionnée
	if game_manager.selected_card_from_deck != null and game_manager.selected_card_from_deck.is_commander_card:
		for pos in game_manager.current_move_zone:
			var flipped = flip_position_180(pos)
			draw_rect(
				Rect2((Vector2(flipped) + Vector2(1, 0)) * cell_size, cell_size),
				Color(0.2, 1, 0.2, 0.4),  # vert clair
				true
			)

func draw_warning():
	if font and warning_timer > 0 and warning_message != "":
		var ts = font.get_string_size(warning_message).x
		var x = (size.x - ts) / 2
		draw_string(font, Vector2(x, 40), warning_message)

func _draw_tactic_overlay() -> void:
	var cell_size = get_dynamic_cell_size()
	# le plateau commence à x=1 cellule (car x=0 = généraux)
	var board_size = Vector2(
		(board.GRID_WIDTH) * cell_size.x,
		board.GRID_HEIGHT * cell_size.y
	)
	var board_pos = Vector2(1 * cell_size.x, 0)

	var col = Color(0.2, 0.6, 1.0, 0.25)
	draw_rect(Rect2(board_pos, board_size), col, true)

func _on_tactic_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if game_manager != null and game_manager.is_tactic_mode:
			game_manager.apply_current_tactic()


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		# 1️⃣ priorité au mode tactique
		if game_manager != null:
			if game_manager.is_tactic_mode:
				game_manager.apply_current_tactic()
				return

		if game_manager:
			game_manager.click_handled = true

		var local_pos = event.position
		var cell_size = get_dynamic_cell_size()

		var visual_cell = Vector2i(
			floor(local_pos.x / cell_size.x) - 1,
			floor(local_pos.y / cell_size.y)
		)

		var cell = flip_position_180(visual_cell)

		# ✅ Vérifie que c'est bien dans la grille
		if not board.is_in_bounds(cell):
			if game_manager and game_manager.is_attack_mode:
				game_manager.cancel_attack_mode()
			return

		# ✅ En mode attaque, clic sur la case seule = annule
		if game_manager and game_manager.is_attack_mode:
			game_manager.cancel_attack_mode()
			return

		# ✅ Si une carte de la main est sélectionnée → tentative de POSE
		if game_manager and game_manager.selected_card_from_deck != null:
			if game_manager.selected_card_from_deck.is_commander_card:
				if not game_manager.current_move_zone.has(cell):
					game_manager._show_warning("Case invalide pour un commandant", 1.2)
					return
			game_manager.attempt_place(cell)
			update_cards_positions()
			queue_redraw()
			return

		# ✅ Phase classique : tentative de déplacement
		if selected_unit_info.has("origin") and selected_unit_info.has("current"):
			game_manager.attempt_move(cell)
			update_cards_positions()






func _notification(what):
	if what == NOTIFICATION_RESIZED:
		await get_tree().process_frame
		update_cards_positions()
		queue_redraw()

		if tactic_overlay != null:
			_update_tactic_overlay_rect()

		if game_manager:
			for card in cards.values():
				card.add_theme_stylebox_override("panel", card.get_default_style())

func _update_tactic_overlay_rect() -> void:
	if tactic_overlay == null:
		return

	var cell_size = get_dynamic_cell_size()

	# on part de x=0 pour inclure la colonne des commandants
	var board_pos = Vector2(0, 0)
	var board_size = Vector2(
		(board.GRID_WIDTH + 1) * cell_size.x,
		board.GRID_HEIGHT * cell_size.y
	)

	tactic_overlay.position = board_pos
	tactic_overlay.size = board_size




func flip_position_180(pos: Vector2i) -> Vector2i:
	if not is_flipped_view:
		return pos

	var new_x: int = pos.x
	# On NE retourne JAMAIS la colonne commandant (x < 0)
	if pos.x >= 0:
		new_x = board.GRID_WIDTH - 1 - pos.x

	var new_y: int = board.GRID_HEIGHT - 1 - pos.y
	return Vector2i(new_x, new_y)


