extends Node

class_name GameManager

const Board = preload("res://board/Board.gd")

@export var board: Board
@export var renderer: BoardRenderer
@export var right_panel: Node
@export var hand: Node
@export var hand2: Node

var current_player: String = "BLUE"
var local_perspective_player: String = "BLUE"

var selected_unit_info: Dictionary = {}
var warning_timer := 0.0
var warning_message := ""
var selected_card_from_deck: StrategosCard = null
var current_move_zone: Array[Vector2i] = []
var current_forbidden_zone: Array[Vector2i] = []
var unit_current_to_origin: Dictionary = {}
var selected_card_from_hand: StrategosCard = null
var click_handled := false

var card_scene = preload("res://board/card.tscn")

var units_data: Dictionary = {}

var is_attack_mode := false
var active_attack_data: Dictionary = {}
var attacking_card: StrategosCard = null

var current_phase: String = "attack"  # "attack" ou "defense"
var attack_queue: Dictionary = {}     # attacker_card -> {"target": StrategosCard, "data": Dictionary}
var defense_queue: Dictionary = {}    # target_card   -> {"data": Dictionary}

var turn_number: int = 1

var next_card_uid: int = 1

var grand_phase: int = 1      # 1..4 : 1A, 2D, 2A, 1D
var grand_tour: int = 1       # 1, 2, 3, ...

var commanders_data: Array = []

var tactics_data: Array = []




func _ready():
	# ✅ Charger les données des unités depuis units.json
	load_units_data()
	load_commanders_data()
	load_tactics_data()
	print("📦 tactics_data n=", tactics_data.size())


	# Charger les définitions d’effets
	EffectsEngine.load_definitions("res://data/commanders.json")

	
	init_starting_units()

	# ✅ Attendre une frame pour que BoardRenderer._ready() initialise card_container
	await get_tree().process_frame
	renderer.generate_cards()

	
	# ✅ Piocher une première carte pour le joueur actif
	draw_card_for_current_player()
	_on_phase_begin()


func assign_uid_to_card(card: StrategosCard) -> void:
	if card == null:
		return
	if card.uid == 0:
		card.uid = next_card_uid
		next_card_uid += 1




func get_opponent(color: String) -> String:
	if color == "BLUE":
		return "RED"
	else:
		return "BLUE"

func get_local_player() -> String:
	return local_perspective_player


func init_starting_units():
	var red_list = generate_starting_units("RED")
	var blue_list = generate_starting_units("BLUE")

	board.init_units_for_player("RED", red_list)
	board.init_units_for_player("BLUE", blue_list)
	
	


func generate_starting_units(player: String) -> Array:
	var raw_units: Array = []
	
	const COMMANDER_ROW_RED := 3
	const COMMANDER_ROW_BLUE := 4


	if player == "RED":
		raw_units = [
			{"pos": Vector2i(0, 3), "type": "Cavalier"},
			{"pos": Vector2i(1, 3), "type": "Hoplite"},
			{"pos": Vector2i(2, 3), "type": "Hoplite"},
			{"pos": Vector2i(3, 3), "type": "Hoplite"},
			{"pos": Vector2i(4, 3), "type": "Hoplite"},
			{"pos": Vector2i(5, 3), "type": "Cavalier"},
			{"pos": Vector2i(2, 2), "type": "Archer"},
			{"pos": Vector2i(3, 2), "type": "Archer"},
			# Général rouge : colonne commandant, ligne avancée arbitraire
			{"pos": Vector2i(-1, COMMANDER_ROW_RED), "type": "General"}
		]
	else:
		raw_units = [
			{"pos": Vector2i(0, 4), "type": "Cavalier"},
			{"pos": Vector2i(1, 4), "type": "Hoplite"},
			{"pos": Vector2i(2, 4), "type": "Hoplite"},
			{"pos": Vector2i(3, 4), "type": "Hoplite"},
			{"pos": Vector2i(4, 4), "type": "Hoplite"},
			{"pos": Vector2i(5, 4), "type": "Cavalier"},
			{"pos": Vector2i(2, 5), "type": "Archer"},
			{"pos": Vector2i(3, 5), "type": "Archer"},
			# Général bleu : colonne commandant, ligne avancée arbitraire
			{"pos": Vector2i(-1, COMMANDER_ROW_BLUE), "type": "General"}
		]

	var converted: Array = []
	for u in raw_units:
		var unit_type = str(u["type"])

		if unit_type == "General":
			var data_cmd = {
				"type": unit_type,              # "General" (affichage/usage actuel)
				"uid": next_card_uid,
				"is_commander": true,
				"role": "general",              # 👈 requis par l’EffectsEngine (slot_active: "general")
				"commander_id": "leon_sparta",  # 👈 identifiant du commandant

			}
			next_card_uid += 1
			converted.append({"pos": u["pos"], "data": data_cmd})
			continue


		var data = {
			"type": unit_type,
			"hp": units_data[unit_type]["hp"],
			"move_range": units_data[unit_type]["move_range"],
			"uid": next_card_uid
		}
		next_card_uid += 1
		converted.append({"pos": u["pos"], "data": data})
	
	return converted


	


func get_display_color(real_color: String) -> String:
	if real_color == local_perspective_player:
		return "BLUE"
	else:
		return "RED"


func load_units_data():
	var file = FileAccess.open("res://data/units.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			units_data = parsed
			
		else:
			push_error("Erreur JSON dans units.json")
	else:
		push_error("Impossible de charger units.json")

func swap_perspective():
	# Inverser la vue locale
	local_perspective_player = "RED" if local_perspective_player == "BLUE" else "BLUE"
	renderer.is_flipped_view = (local_perspective_player != "BLUE")

	# Mise à jour graphique du plateau
	renderer.update_cards_positions()
	renderer.queue_redraw()

	# ✅ Rafraîchir les styles visuels des cartes du plateau
	for card in renderer.cards.values():
		if card.panel:
			card.panel.add_theme_stylebox_override("panel", card.get_default_style())

	# ✅ Rafraîchir les styles des cartes dans les deux mains
	if hand:
		for card in hand.get_children():
			if card is StrategosCard and card.panel:
				card.panel.add_theme_stylebox_override("panel", card.get_default_style())

	if hand2:
		for card in hand2.get_children():
			if card is StrategosCard and card.panel:
				card.panel.add_theme_stylebox_override("panel", card.get_default_style())

	# 🔁 Échanger visuellement les cartes des deux mains
	_swap_hands_contents()

	# ✅ Mettre à jour la couleur du bouton Fin de tour après la vue
	if right_panel:
		right_panel.update_button_color(current_player == get_local_player())

	# ✅ 🆕 Mettre à jour les boutons d’attaque pour refléter la nouvelle perspective
	update_all_attack_buttons()
	update_all_defense_buttons()
	
	clear_all_highlights()
	refresh_all_cards_visuals()
	
	recompute_grayouts()
	update_tour_ui_label()
	
	_refresh_attacker_highlights_for_selected()







func _swap_hands_contents():
	var hand_cards = hand.get_children()
	var hand2_cards = hand2.get_children()

	for c in hand_cards:
		hand.remove_child(c)
		hand2.add_child(c)

	for c in hand2_cards:
		hand2.remove_child(c)
		hand.add_child(c)

	hand.update_card_positions()
	hand2.update_card_positions()



func switch_turn():
	# 🔒 On ferme la phase en cours et on prépare la suivante
	if current_phase == "attack":
		# Après l'attaque de X → défense de l'adversaire
		current_phase = "defense"
		current_player = get_opponent(current_player)
	else:
		# Après la défense → on résout TOUT, puis
		# même joueur commence immédiatement sa phase d'attaque
		resolve_round()
		current_phase = "attack"
		turn_number += 1  # Nouveau tour complet après retour à l'attaque
		# current_player NE change PAS ici
		
		
		


	# ✅ Affichage console du changement de tour
	print("🔄 Tour ", turn_number, " | Joueur actuel : ", current_player, " | Phase : ", current_phase)

	# 🔄 Nettoyages/UI communs
	selected_unit_info = {}
	renderer.selected_unit_info.clear()

	selected_card_from_deck = null
	unit_current_to_origin.clear()
	_clear_warning()

	for c in renderer.cards.values():
		c.set_selected(false)
		# le blink sera recalculé si nécessaire

	selected_card_from_hand = null

	current_move_zone.clear()
	current_forbidden_zone.clear()

	renderer.current_player = current_player
	renderer.update_cards_positions()
	renderer.queue_redraw()

	# Couleurs/UI
	if right_panel:
		right_panel.update_button_color(current_player == get_local_player())
		update_tour_ui_label()

		
	clear_all_targeting()


	# Réactualise boutons (attaques/défenses) et visuels (grisage)
	update_all_attack_buttons()
	update_all_defense_buttons()
	recompute_grayouts()

	# Pioche si tu veux conserver la pioche à chaque début de tour :
	# (sinon, commente ces lignes ou conditionne à current_phase == "attack")
	draw_card_for_current_player()
	_on_phase_begin()
	
	_clear_attacker_highlights()



func clear_all_targeting() -> void:
	if renderer == null:
		return
	for c in renderer.cards.values():
		if c is StrategosCard:
			# sur la carte ciblée
			c.is_targeted = false
			c.targeted_by = null
			c.stop_target_blink()
			# sur la carte potentiellement attaquante
			c.targeted_card = null
			c.active_attack_name = ""
			c.update_attack_button_states()
			c.update_grayscale()
			_clear_attacker_highlights()



func select_card(card: StrategosCard) -> void:
	if card.get_parent() == hand2:
		_show_warning("Vous ne pouvez pas sélectionner la main adverse", 1.5)
		return

	if local_perspective_player != current_player:
		_show_warning("Ce n'est pas votre tour", 1.5)
		return

	# 🧯 Cliquer la même carte → désélection
	if selected_unit_info.has("card") and selected_unit_info["card"] == card:
		card.set_selected(false)

		# Si cette carte était en phase d'attaque, on annule
		if is_attack_mode and attacking_card == card:
			cancel_attack_mode()

		# Éteindre/blinker et nettoyer grisage immédiatement
		refresh_target_blinks_for(card)
		recompute_grayouts()

		selected_unit_info.clear()
		renderer.selected_unit_info.clear()
		renderer.queue_redraw()
		
		_clear_attacker_highlights()


		# Sécurité
		for c in renderer.cards.values():
			if c.is_targeted:
				c.stop_target_blink()

		click_handled = true
		return

	# 🔄 Nettoyage des anciennes sélections plateau
	if selected_card_from_deck != null:
		selected_card_from_deck.set_selected(false)

	for c in renderer.cards.values():
		c.set_selected(false)
		c.stop_target_blink()

	# Dans select_card(card), bloc: if card.is_deck_card:
	if card.is_deck_card:
		selected_card_from_deck = card
		card.set_selected(true)

		# 🔁 Nettoyer toute ancienne sélection plateau (évite la zone jaune résiduelle)
		selected_unit_info.clear()
		renderer.selected_unit_info.clear()
	
		# ✅ Si c'est une carte commandant → calculer zone de placement
		if card.is_commander_card:
			current_move_zone = compute_commander_place_zone()
			current_forbidden_zone.clear()
			if renderer:
				renderer.queue_redraw()  # affiche tout de suite la zone verte
		else:
			renderer.selected_unit_info = {"deck_card": true}
			renderer.queue_redraw()

		click_handled = true
		return




		# Si on quitte une attaque en cours (d'une autre carte) → annule
		if is_attack_mode and attacking_card != null and attacking_card != card:
			cancel_attack_mode()
			# après annulation, plus d'attaquant actif → on nettoie blink + grisage
			refresh_target_blinks_for(attacking_card)
			recompute_grayouts()

		renderer.selected_unit_info = { "deck_card": true }
		renderer.queue_redraw()
		click_handled = true
		return

	# Ne pas sélectionner les cartes de l'adversaire
	if card.player_color != current_player:
		return

	# ✅ Sélection de la carte plateau
	selected_card_from_deck = null
	card.set_selected(true)

	# Si une attaque était en cours mais que ce n’est plus la bonne carte → annule
	if is_attack_mode and attacking_card != null and attacking_card != card:
		cancel_attack_mode()
		refresh_target_blinks_for(attacking_card)
		recompute_grayouts()

	# ⬇️⬇️ CHANGEMENT ICI ⬇️⬇️
	# Si c’est bien la carte attaquante → relancer blink + recalcul grisage
	if is_attack_mode and attacking_card == card:
		refresh_target_blinks_for(card)
	else:
		# ✅ Hors phase d'attaque : le marquage doit exister tant que
		# la carte qui a ciblé est sélectionnée → on rafraîchit avec "card"
		refresh_target_blinks_for(card)
		recompute_grayouts()
	# ⬆️⬆️ CHANGEMENT ICI ⬆️⬆️

	# ✅ Enregistrement de la position d’origine
	if not unit_current_to_origin.has(card.cell):
		unit_current_to_origin[card.cell] = card.cell
	var origin: Vector2i = unit_current_to_origin[card.cell]
	var current_pos: Vector2i = card.cell

	# 📦 Déduction du type d’unité
	var raw_value = null
	if board.red_units.has(card.cell):
		raw_value = board.red_units[card.cell]
	elif board.blue_units.has(card.cell):
		raw_value = board.blue_units[card.cell]

	var unit_type: String = ""
	if raw_value != null:
		if raw_value is String:
			unit_type = raw_value
		elif raw_value is Dictionary and raw_value.has("type"):
			unit_type = raw_value["type"]
	else:
		unit_type = str(card.get_meta("unit_type", "Hoplite"))

	# 📏 Portée de déplacement
	var move_range_val: int = 1
	if units_data.has(unit_type):
		var unit_data = units_data[unit_type]
		if unit_data.has("move_range"):
			move_range_val = unit_data["move_range"]

	# 💾 Infos de l’unité sélectionnée
	selected_unit_info = {
		"origin": origin,
		"current": current_pos,
		"unit_type": unit_type,
		"move_range": move_range_val,
		"card": card
	}
	
	_refresh_attacker_highlights_for_selected()

	current_move_zone = compute_move_zone_for(origin, current_pos)
	renderer.selected_unit_info = selected_unit_info
	renderer.queue_redraw()

	click_handled = true

	# 🔒 Filet de sécurité final :
	# Si la carte sélectionnée est (ou fut) l'attaquante et qu'elle a des cibles enregistrées,
	# on force le marquage à (re)partir même hors phase.
	refresh_target_blinks_for(card)




func compute_move_zone_for(origin: Vector2i, current: Vector2i) -> Array[Vector2i]:
	var zone: Array[Vector2i] = []
	current_forbidden_zone.clear()

	var move_range = selected_unit_info.get("move_range", 1)

	var visited: Dictionary = {}
	var frontier: Array = [origin]
	visited[origin] = 0

	while not frontier.is_empty():
		var current_cell = frontier.pop_front()
		var dist = visited[current_cell]

		if dist < move_range:
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var target = current_cell + dir
				if not board.is_in_bounds(target):
					continue
				if visited.has(target):
					continue

				# Interdiction diagonale
				if abs(target.x - origin.x) > 0 and abs(target.y - origin.y) > 0:
					continue

				# Interdiction zone généraux
				if (target.x < 0 and origin.x >= 0) or (target.x >= 0 and origin.x < 0):
					continue

				# Blocage si occupée (sauf soi-même ou position actuelle)
				if target != origin and not board.is_empty(target) and target != current:
					continue

				visited[target] = dist + 1
				zone.append(target)

				if board.is_empty(target) or target == origin or target == current:
					frontier.append(target)

	if not zone.has(origin):
		zone.append(origin)

	# ✅ Bloc IIH : réplique exacte de attempt_move(), appliqué à toutes les cases atteignables
	for pos in zone:
		if origin.y == pos.y:
			for other_current in board.get_units(current_player):
				if other_current == current:
					continue

				var other_origin = unit_current_to_origin.get(other_current, other_current)

				if origin.y != other_origin.y or origin.y != other_current.y:
					continue

				var initial_relation = sign(origin.x - other_origin.x)
				var future_relation = sign(pos.x - other_current.x)

				if initial_relation != 0 and future_relation != 0 and initial_relation != future_relation:
					if not current_forbidden_zone.has(pos):
						current_forbidden_zone.append(pos)

	
	return zone





func attempt_move(pos: Vector2i):
	
	if current_phase == "defense":
		_show_warning("Déplacement interdit en phase de défense", 1.5)
		return

	if local_perspective_player != current_player:
		_show_warning("Ce n'est pas votre tour", 1.5)
		return

	if not selected_unit_info.has("current"):
		return

	var current = selected_unit_info["current"]
	var origin = selected_unit_info["origin"]

	# ✅ Récupérer la carte active
	var card = renderer.cards.get(current, null)

	# 🆕 Blocage si une cible est définie
	if card and card.targeted_card != null:
		_show_warning("Impossible de déplacer une carte qui a une attaque active", 2.0)
		return

	# ✅ Blocage si clic sur case actuelle
	if pos == current:
		return

	# 🔌 HOOK Effets (commandants) — tentative de déplacement
	var mover_card: StrategosCard = null
	if selected_unit_info.has("card"):
		mover_card = selected_unit_info["card"]

	var move_ctx := {
		"board": board,
		"player": current_player,
		"from": current,
		"to": pos,
		"mover_card": mover_card
	}
	var move_res := EffectsEngine.on_move_attempt(move_ctx)
	if move_res.has("forbid") and bool(move_res["forbid"]) == true:
		_show_warning("Mouvement interdit par le commandement", 1.5)
		return
	# (Option future: si l'engine renvoie une position corrigée)
	if move_res.has("pos"):
		pos = move_res["pos"]

	if current_forbidden_zone.has(pos):
		_show_warning("Interchangeabilité horizontale interdite", 2.0)
		return

	if not current_move_zone.has(pos):
		_show_warning("Déplacement interdit vers cette case", 2.0)
		return

	# 🔁 LOGIQUE IIH SYNCHRONISÉE
	if origin.y == pos.y:
		for other_current in board.get_units(current_player):
			if other_current == current:
				continue

			var other_origin = unit_current_to_origin.get(other_current, other_current)

			if origin.y != other_origin.y or origin.y != other_current.y:
				continue

			var initial_relation = sign(origin.x - other_origin.x)
			var future_relation = sign(pos.x - other_current.x)

			if initial_relation != 0 and future_relation != 0 and initial_relation != future_relation:
				_show_warning("Interchangeabilité horizontale interdite", 2.0)
				return

	board.move_unit(current_player, current, pos)
	unit_current_to_origin[pos] = origin
	unit_current_to_origin.erase(current)

	if card:
		renderer.cards.erase(current)
		renderer.cards[pos] = card
		card.cell = pos
		card.update_position(board.CELL_SIZE)

	selected_unit_info["current"] = pos
	renderer.selected_unit_info = selected_unit_info
	renderer.queue_redraw()
	click_handled = true



func attempt_place(pos: Vector2i):
	if local_perspective_player != current_player:
		_show_warning("Ce n'est pas votre tour", 1.5)
		return

	if selected_card_from_deck == null:
		return

	# ✅ Cartes commandant : branche dédiée
	if selected_card_from_deck.is_commander_card:
		_attempt_place_commander(pos)
		return

	# 🚫 Empêcher les cartes normales d'être posées dans la colonne commandant
	if pos.x < 0:
		_show_warning("Impossible de poser cette carte ici", 1.2)
		return

	# --- Logique standard pour les unités ---
	var unit_type = "Hoplite"
	if selected_card_from_deck.label_name:
		unit_type = selected_card_from_deck.label_name.text
	if not units_data.has(unit_type):
		_show_warning("Carte non posable (type inconnu)", 1.2)
		return

	var full_data = {
		"type": unit_type,
		"hp": units_data[unit_type]["hp"],
		"move_range": units_data[unit_type]["move_range"]
	}

	board.add_unit(current_player, pos, full_data)

	var card = renderer._create_card(pos, current_player, unit_type)
	card.is_deck_card = false
	card.pioched_this_turn = true
	card.set_selected(false)

	selected_card_from_deck.queue_free()
	selected_card_from_deck = null
	
	# 🔁 Nettoyage visuel après pose
	current_move_zone.clear()
	current_forbidden_zone.clear()
	renderer.selected_unit_info.clear()
	
	renderer.queue_redraw()
	click_handled = true


func _attempt_place_commander(pos: Vector2i):
	# ✅ Vérifier colonne commandant
	if pos.x != -1:
		_show_warning("Un commandant doit être placé dans la colonne spéciale", 1.5)
		return

	# ✅ Vérifier que la case est libre
	if board.red_units.has(pos) or board.blue_units.has(pos):
		_show_warning("Case de commandant déjà occupée", 1.5)
		return

	# ✅ Vérifier la ligne (condition alliés/enemis)
	var y = pos.y
	var allies: Array = []
	var enemies: Array = []

	if current_player == "RED":
		for u in board.get_units("RED"):
			if u.y == y and u.x >= 0:
				allies.append(u)
		for u in board.get_units("BLUE"):
			if u.y == y and u.x >= 0:
				enemies.append(u)
	else:
		for u in board.get_units("BLUE"):
			if u.y == y and u.x >= 0:
				allies.append(u)
		for u in board.get_units("RED"):
			if u.y == y and u.x >= 0:
				enemies.append(u)

	if allies.is_empty():
		_show_warning("Impossible : la ligne n’a pas d’unités alliées", 1.5)
		return
	if not enemies.is_empty():
		_show_warning("Impossible : la ligne contient des ennemis", 1.5)
		return

	# ✅ Récupération du commandant choisi
	var commander_id = selected_card_from_deck.get_meta("commander_id", "unknown_commander")
	var commander_name = selected_card_from_deck.get_meta("commander_name", "Commandant")

	# ✅ Création du modèle commandant
	var data_cmd = {
		"type": commander_name,  # visible dans le plateau
		"uid": next_card_uid,
		"is_commander": true,
		"commander_id": commander_id
	}

	


	
	next_card_uid += 1
	board.add_unit(current_player, pos, data_cmd)

	# ✅ Création de la carte UI
	var cell_size = renderer.get_dynamic_cell_size()
	var card = renderer._create_card(pos, current_player, "Commander")
	card.is_commander = true
	card.is_deck_card = false
	card.set_selected(false)

	# ✅ Retirer la carte de la main
	selected_card_from_deck.queue_free()
	selected_card_from_deck = null
	
	# 🔁 Nettoyage visuel après pose
	current_move_zone.clear()
	current_forbidden_zone.clear()
	renderer.selected_unit_info.clear()

	renderer.queue_redraw()
	click_handled = true


func _show_warning(msg: String, duration: float):
	warning_message = msg
	warning_timer = duration
	renderer.warning_message = msg
	renderer.warning_timer = duration
	renderer.queue_redraw()


func _clear_warning():
	warning_message = ""
	warning_timer = 0
	renderer.warning_message = ""
	renderer.warning_timer = 0
	renderer.queue_redraw()


func deselect_everything():
	if selected_card_from_deck:
		selected_card_from_deck.set_selected(false)
		selected_card_from_deck = null

	selected_card_from_hand = null

	selected_unit_info.clear()
	current_move_zone.clear()
	current_forbidden_zone.clear()

	for c in renderer.cards.values():
		c.set_selected(false)

	renderer.selected_unit_info.clear()
	renderer.queue_redraw()
	
		# Masquer tous les surlignages (attaquants + cibles)
	_clear_attacker_highlights()
	refresh_target_blinks_for(null)  # ⇒ cache tous les cadres des cibles



func draw_card_for_current_player():
	var target_hand: Node = null
	if current_player == local_perspective_player:
		target_hand = hand
	else:
		target_hand = hand2

	var cell_size = renderer.get_dynamic_cell_size()
	if cell_size == Vector2.ZERO:
		await get_tree().process_frame
		cell_size = renderer.get_dynamic_cell_size()
		if cell_size == Vector2.ZERO:
			cell_size = Vector2(120, 60)

	var card = card_scene.instantiate() as StrategosCard
	card.is_deck_card = true
	card.game_manager = self                 # ✅ avant add_child
	assign_uid_to_card(card)

	# 🎴 tirer une vraie tactique
	var tactic_data := {}
	if not tactics_data.is_empty():
		tactic_data = tactics_data.pick_random()
	else:
		print("⚠️ Aucune tactique chargée")

	# ✅ ajouter D’ABORD, puis setup (ainsi les @onready sont valides)
	target_hand.add_child(card)
	card.setup_as_tactic(cell_size, current_player, tactic_data)

	print("🃏 Tactique piochée:", tactic_data.get("id","?"), tactic_data.get("title","(sans titre)"))

	target_hand.update_card_positions()
	
	
func draw_commander_card_for_current_player():
	if commanders_data.is_empty():
		push_error("Aucun commandant trouvé dans commanders.json")
		return

	var commander_info = commanders_data.pick_random()
	var commander_id = commander_info.get("id", "unknown_commander")
	var commander_name = commander_info.get("name", "Commandant inconnu")

	var target_hand: Node = null
	if current_player == local_perspective_player:
		target_hand = hand
	else:
		target_hand = hand2

	var cell_size = renderer.get_dynamic_cell_size()
	if cell_size == Vector2.ZERO:
		await get_tree().process_frame
		cell_size = renderer.get_dynamic_cell_size()
		if cell_size == Vector2.ZERO:
			cell_size = Vector2(120, 60)

	var card = card_scene.instantiate() as StrategosCard
	card.is_deck_card = true
	card.is_commander_card = true
	card.game_manager = self
	assign_uid_to_card(card)

	card.set_meta("commander_id", commander_id)
	card.set_meta("commander_name", commander_name)

	# ✅ 1) Ajouter à la scène AVANT le setup pour que _ready() ne ré-efface pas le nom
	target_hand.add_child(card)

	# ✅ 2) Maintenant faire le setup (écrit le nom après _ready)
	card.setup_as_commander_card(cell_size, current_player, commander_name)

	target_hand.update_card_positions()



func compute_commander_place_zone() -> Array[Vector2i]:
	var zone: Array[Vector2i] = []

	# Parcourir toutes les cases commandant (colonne -1)
	for y in range(board.GRID_HEIGHT):
		var pos = Vector2i(-1, y)

		# Case libre ?
		if board.red_units.has(pos) or board.blue_units.has(pos):
			continue

		# Vérif alliés / ennemis
		var allies: Array = []
		var enemies: Array = []

		if current_player == "RED":
			for u in board.get_units("RED"):
				if u.y == y and u.x >= 0:
					allies.append(u)
			for u in board.get_units("BLUE"):
				if u.y == y and u.x >= 0:
					enemies.append(u)
		else:
			for u in board.get_units("BLUE"):
				if u.y == y and u.x >= 0:
					allies.append(u)
			for u in board.get_units("RED"):
				if u.y == y and u.x >= 0:
					enemies.append(u)

		if allies.is_empty():
			continue
		if not enemies.is_empty():
			continue

		zone.append(pos)

	return zone

	

func _on_phase_begin():
	# Affiche l'état actuel avant de muter la phase
	update_tour_ui_label()

	# Règle de pioche commandant :
	# - Grand tour 1 : aucune pioche (phases 1..4)
	# - Grand tour >= 2 : pioche seulement en phases 1 et 2 (attaque J1, défense J2)
	if grand_tour >= 2:
		if grand_phase == 1 or grand_phase == 2:
			draw_commander_card_for_current_player()

	# Avancer le cycle 1→2→3→4 puis grand_tour++
	grand_phase += 1
	if grand_phase > 4:
		grand_phase = 1
		grand_tour += 1






func update_all_attack_buttons():
	# Cartes sur le plateau
	for card in renderer.cards.values():
		if card.has_method("update_attack_buttons"):
			card.update_attack_buttons()
	# Cartes dans la main du joueur local
	for card in hand.get_children():
		if card.has_method("update_attack_buttons"):
			card.update_attack_buttons()
	# Cartes dans la main adverse
	for card in hand2.get_children():
		if card.has_method("update_attack_buttons"):
			card.update_attack_buttons()

func notify_attack_activation(card: StrategosCard, attack_data):
	if attack_data == null:
		print("ℹ️ Attaque désactivée pour :", card.label_name.text, "(UID:", card.uid, ")")
	else:
		print("⚔️ Attaque activée :", attack_data["name"], "par", card.label_name.text, "(UID:", card.uid, ")")

	renderer.queue_redraw()


func enter_attack_mode(card: StrategosCard, attack_data: Dictionary) -> void:
	is_attack_mode = true
	active_attack_data = attack_data
	attacking_card = card

	print("🎯 Entrée en mode attaque avec :", attack_data.get("name", "???"), "| carte :", card.label_name.text, "(UID:", card.uid, ")")

	# Blink des cibles éventuelles
	refresh_target_blinks_for(attacking_card)

	# Grisage immédiat (pas d’attente)
	recompute_grayouts()



func cancel_attack_mode() -> void:
	var prev_attacker: StrategosCard = attacking_card

	if is_attack_mode:
		print("❌ Annulation de la phase d’attaque")
		is_attack_mode = false
		active_attack_data = {}

		# On conserve la cible enregistrée (✓) mais on coupe le blink
		if prev_attacker != null and prev_attacker.targeted_card != null:
			prev_attacker.targeted_card.stop_target_blink()

	# Désigner qu'il n'y a plus d'attaquant
	attacking_card = null
	
	if prev_attacker != null:
		prev_attacker.active_attack_name = ""
		prev_attacker.update_attack_button_states()

	# Plus de blink
	refresh_target_blinks_for(prev_attacker)
	
	_refresh_attacker_highlights_for_selected()


	# Nettoyage du grisage (immédiat, donc pas d'apparition retardée)
	recompute_grayouts()
	





func confirm_attack_on_target(target_card: StrategosCard):
	if not is_attack_mode or attacking_card == null or active_attack_data.is_empty():
		print("⛔ Phase d'attaque inactive ou données manquantes")
		return

	var attacker_pos = attacking_card.cell
	var target_pos = target_card.cell
	var range = active_attack_data.get("range", 1)

	var in_range := false
	if range == 1:
		in_range = (abs(attacker_pos.x - target_pos.x) + abs(attacker_pos.y - target_pos.y) == 1)
	else:
		var dx = abs(attacker_pos.x - target_pos.x)
		var dy = abs(attacker_pos.y - target_pos.y)
		in_range = (dx <= range and dy <= range)

	if not in_range:
		print("⚠️ Cible hors de portée")
		_show_warning("Cible hors de portée", 1.5)
		cancel_attack_mode()
		refresh_all_cards_visuals()

		return

	if target_card.is_targeted:
		print("🟣 Carte déciblée :", target_card.label_name.text, "(UID:", target_card.uid, ")")
		target_card.set_targeted(false)  # 👈 pas besoin de stop ici
	else:
		print("🎯 Carte ciblée :", target_card.label_name.text, "(UID:", target_card.uid, ")", "à la position", target_card.cell, "par", attacking_card.label_name.text, "(UID:", attacking_card.uid, ")")
		target_card.set_targeted(true, attacking_card)  # 👈 blink sera géré dedans

	# ✅ Ne quitte pas la phase pour que la cible reste visible



func highlight_attack_targets() -> void:
	refresh_all_cards_visuals()
	


func refresh_all_cards_visuals() -> void:
	if renderer == null:
		return
	# Plateau
	for c in renderer.cards.values():
		if is_instance_valid(c):
			c.update_attack_button_states()
			# 🔑 Enlève toute teinte résiduelle + recalcul
			c.modulate = Color(1, 1, 1, 1)
			c.update_grayscale()
	# Main du bas
	if hand:
		for c in hand.get_children():
			if c is StrategosCard:
				c.update_attack_button_states()
				c.modulate = Color(1, 1, 1, 1)
				c.update_grayscale()
	# Main du haut
	if hand2:
		for c in hand2.get_children():
			if c is StrategosCard:
				c.update_attack_button_states()
				c.modulate = Color(1, 1, 1, 1)
				c.update_grayscale()

func clear_all_highlights() -> void:
	# Supprime TOUT modulate gris laissé par l'ancien système
	for c in renderer.cards.values():
		if is_instance_valid(c):
			c.modulate = Color(1, 1, 1, 1)
	if hand:
		for c in hand.get_children():
			if c is StrategosCard:
				c.modulate = Color(1, 1, 1, 1)
	if hand2:
		for c in hand2.get_children():
			if c is StrategosCard:
				c.modulate = Color(1, 1, 1, 1)

func refresh_target_blinks_for(attacker: StrategosCard) -> void:
	if renderer == null:
		return

	# Si pas d'attaquant sélectionné → on coupe tout blink
	if attacker == null or not attacker.is_selected:
		for c in renderer.cards.values():
			if is_instance_valid(c):
				c.stop_target_blink()
		return

	# Clignote SEULEMENT si :
	# - la carte est ciblée
	# - elle a été ciblée par 'attacker'
	# - et 'attacker' est actuellement sélectionnée
	for c in renderer.cards.values():
		if not is_instance_valid(c):
			continue
		if c.is_targeted and c.targeted_by == attacker:
			c.start_target_blink()
		else:
			c.stop_target_blink()

func _clear_attacker_highlights() -> void:
	if renderer == null:
		return
	for c in renderer.cards.values():
		if c is StrategosCard:
			c.set_attacker_highlight(false)
			c.stop_attacker_blink()

func _refresh_attacker_highlights_for_selected() -> void:
	_clear_attacker_highlights()

	if not selected_unit_info.has("card"):
		return
	var sel: StrategosCard = selected_unit_info["card"]
	if sel == null:
		return

	# Toutes les cartes qui ont 'sel' comme cible deviennent surlignées + BLINK
	for attacker in attack_queue.keys():
		var info: Dictionary = attack_queue[attacker]
		var tgt: StrategosCard = info.get("target", null)
		if tgt == sel and attacker is StrategosCard:
			attacker.set_attacker_highlight(true)
			# Blink attaquant seulement si une carte est bien sélectionnée (c’est le cas ici)
			attacker.start_attacker_blink()



func recompute_grayouts() -> void:
	# Affiche le grisage UNIQUEMENT si :
	# - on est en phase d'attaque,
	# - il y a une carte attaquante,
	# - et cette attaquante est sélectionnée.
	var in_targeting: bool = false
	var range: int = 1
	var attacker: StrategosCard = null

	if is_attack_mode and attacking_card != null and attacking_card.is_selected:
		in_targeting = true
		attacker = attacking_card
		if not active_attack_data.is_empty():
			if active_attack_data.has("range"):
				range = int(active_attack_data["range"])

	# Appliquer (ou nettoyer) le grisage à TOUTES les cartes du plateau
	for c in renderer.cards.values():
		if not is_instance_valid(c):
			continue

		# Nettoyage par défaut
		c.material = null
		c.modulate = Color(1, 1, 1, 1)

		if in_targeting:
			# Ne jamais griser un allié
			if c.player_color != attacker.player_color:
				var dx: int = abs(c.cell.x - attacker.cell.x)
				var dy: int = abs(c.cell.y - attacker.cell.y)

				var in_range: bool = false
				if range == 1:
					if dx + dy == 1:
						in_range = true
				else:
					if dx <= range and dy <= range:
						in_range = true

				if not in_range:
					c.modulate = Color(0.5, 0.5, 0.5, 1.0)



func is_card_in_attack_range(attacker: StrategosCard, target: StrategosCard) -> bool:
	if attacker == null:
		return false
	if target == null:
		return false

	var range: int = 1
	if not active_attack_data.is_empty():
		if active_attack_data.has("range"):
			range = int(active_attack_data["range"])

	var dx: int = abs(attacker.cell.x - target.cell.x)
	var dy: int = abs(attacker.cell.y - target.cell.y)

	var in_range: bool = false
	if range == 1:
		if dx + dy == 1:
			in_range = true
	else:
		if dx <= range and dy <= range:
			in_range = true

	return in_range


func register_attack_target(attacker: StrategosCard, target: StrategosCard) -> void:
	# Appelé quand on valide une cible (dans _gui_input de la carte)
	if attacker == null or target == null:
		return
	if active_attack_data.is_empty():
		return
	attack_queue[attacker] = {"target": target, "data": active_attack_data}
	
	_refresh_attacker_highlights_for_selected()


func unregister_attack_target(attacker: StrategosCard) -> void:
	if attacker == null:
		return
	if attack_queue.has(attacker):
		attack_queue.erase(attacker)
	
	_refresh_attacker_highlights_for_selected()
	

func toggle_defense(card: StrategosCard, defense_data: Dictionary) -> void:
	if current_phase != "defense":
		_show_warning("Défenses utilisables en phase de défense uniquement", 1.5)
		return
	if card.player_color != current_player:
		_show_warning("Ce n'est pas votre unité", 1.5)
		return

	if defense_queue.has(card):
		defense_queue.erase(card)
		card.set_defense_active(false, {})
		var dname_off := ""
		if defense_data.has("name"):
			dname_off = str(defense_data["name"])
		print("❌ Défense désactivée :", dname_off, "| carte :", card.label_name.text, "(UID:", card.uid, ")")
	else:
		defense_queue[card] = {"data": defense_data}
		card.set_defense_active(true, defense_data)
		var dname_on := ""
		if defense_data.has("name"):
			dname_on = str(defense_data["name"])
		print("🛡️ Défense activée :", dname_on, "| carte :", card.label_name.text, "(UID:", card.uid, ")")

	update_all_defense_buttons()

# Calcule le dégât de base en fonction de la distance et de la définition d'attaque.
# - damage peut être un entier ou un tableau (ex: [15,10,5]).
# - pour les attaques à distance (range > 1), on indexe par la distance de Chebyshev (max(dx,dy)).
# - pour la mêlée (range == 1), on prend l'index 0 ou l'entier direct.
func compute_damage_for_attack(attacker: StrategosCard, target: StrategosCard, atk: Dictionary) -> int:
	var base_damage: int = 0
	if atk == null or atk.is_empty():
		return 0

	var dmg_raw = atk.get("damage", 0)
	var rng: int = int(atk.get("range", 1))

	var dx: int = abs(attacker.cell.x - target.cell.x)
	var dy: int = abs(attacker.cell.y - target.cell.y)

	var dist: int = 1
	if rng == 1:
		dist = 1
	else:
		var dcheb: int = dx
		if dy > dcheb:
			dcheb = dy
		if dcheb < 1:
			dcheb = 1
		dist = dcheb

	if typeof(dmg_raw) == TYPE_INT or typeof(dmg_raw) == TYPE_FLOAT:
		base_damage = int(dmg_raw)
	elif typeof(dmg_raw) == TYPE_ARRAY:
		var arr: Array = dmg_raw
		if arr.is_empty():
			base_damage = 0
		else:
			var idx: int = dist - 1
			if idx < 0:
				idx = 0
			if idx >= arr.size():
				idx = arr.size() - 1
			var val = arr[idx]
			if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
				base_damage = int(val)
			else:
				base_damage = 0
	else:
		base_damage = 0

	# 🔌 HOOK Effets (commandants) — ajustement des dégâts d'attaque (ex: +5 en mêlée sur ligne commandée)
	var ef_ctx := {
		"board": board,
		"attacker": attacker,
		"target": target,
		"attack_data": atk,
		"base_damage": base_damage
	}
	var ef_res := EffectsEngine.on_attack_compute(ef_ctx)
	if ef_res.has("damage"):
		base_damage = int(ef_res["damage"])

	return base_damage



func resolve_round() -> void:
	print("— Résolution — attaques:", attack_queue.size(),
		" | défenses:", defense_queue.size(),
		" | tour:", turn_number, " | phase:", current_phase)

	for attacker in attack_queue.keys():
		var info: Dictionary = attack_queue[attacker]
		var target: StrategosCard = info.get("target", null)
		var atk: Dictionary = info.get("data", {})

		if target == null:
			continue

		var base_damage: int = compute_damage_for_attack(attacker, target, atk)

		var reduction_flat: int = 0
		if defense_queue.has(target):
			var ddef: Dictionary = defense_queue[target].get("data", {})
			if ddef.has("reduction"):
				reduction_flat = int(ddef["reduction"])
				if reduction_flat < 0:
					reduction_flat = 0

		var dmg_after_def := base_damage - reduction_flat
		if dmg_after_def < 0:
			dmg_after_def = 0

		# 🔌 HOOK Effets (commandants) — juste avant d'appliquer les dégâts (ex: -20% Hoplite groupé si Général)
		var dmg_ctx := {
			"board": board,
			"target": target,
			"incoming_damage": dmg_after_def
		}
		var dmg_res := EffectsEngine.on_damage_before(dmg_ctx)
		if dmg_res.has("damage"):
			dmg_after_def = int(dmg_res["damage"])

		var final_damage: int = dmg_after_def

		print("[RESOLVE] ",
			atk.get("name","?"),
			" | Att:", attacker.label_name.text, "#", str(attacker.uid),
			" → Cible:", target.label_name.text, "#", str(target.uid),
			" | Base:", base_damage,
			" | -Red:", reduction_flat,
			" | =Dégâts:", final_damage)

		apply_damage_to_card(target, final_damage)
	
	clear_all_targeting()
	
	attack_queue.clear()
	_clear_attacker_highlights()

	defense_queue.clear()
	
	if renderer:
		renderer.queue_redraw()

	



func apply_damage_to_card(target: StrategosCard, damage: int) -> void:
	if target == null:
		return
	if damage < 0:
		damage = 0

	var cell := target.cell
	var owner := target.player_color

	# 1) Récupérer/initialiser l'entrée modèle (source de vérité)
	var raw = null
	if owner == "RED":
		if board.red_units.has(cell):
			raw = board.red_units[cell]
	elif owner == "BLUE":
		if board.blue_units.has(cell):
			raw = board.blue_units[cell]

	var model_dict: Dictionary = {}
	var unit_type := ""
	var uid_val := 0

	if typeof(raw) == TYPE_DICTIONARY:
		model_dict = raw
		if model_dict.has("type"):
			unit_type = str(model_dict["type"])
		if model_dict.has("uid"):
			uid_val = int(model_dict["uid"])
	elif typeof(raw) == TYPE_STRING:
		unit_type = str(raw)
	else:
		# cas improbable : rien dans le modèle → essayer meta de la carte
		unit_type = str(target.get_meta("unit_type", "Hoplite"))

	# Si le modèle n'est pas un dictionnaire complet, on l'initialise depuis units.json
	if model_dict.is_empty():
		var base_hp := 0
		var move_rng := 1
		if units_data.has(unit_type):
			var ud: Dictionary = units_data[unit_type]
			base_hp = int(ud.get("hp", 0))
			move_rng = int(ud.get("move_range", 1))

		model_dict = {
			"type": unit_type,
			"hp": base_hp,
			"move_range": move_rng,
			"uid": uid_val if uid_val != 0 else target.uid
		}

		# Écrire immédiatement dans le modèle
		if owner == "RED":
			board.red_units[cell] = model_dict
		else:
			board.blue_units[cell] = model_dict

	# 2) Appliquer les dégâts côté modèle
	var current_hp := int(model_dict.get("hp", 0))
	var new_hp := current_hp - damage
	if new_hp < 0:
		new_hp = 0
	model_dict["hp"] = new_hp
	
	show_damage_popup(target, damage)

	# 3) Réécrire le dictionnaire dans le bon camp (sécurité de référence)
	if owner == "RED":
		board.red_units[cell] = model_dict
	else:
		board.blue_units[cell] = model_dict

	# 4) Pousser l'UI depuis le modèle (jamais l'inverse)
	if target.label_hp:
		target.label_hp.text = str(new_hp) + " PV"

	# 5) Mort → retirer modèle + UI
	if new_hp == 0:
		# modèle
		if owner == "RED":
			if board.red_units.has(cell):
				board.red_units.erase(cell)
		else:
			if board.blue_units.has(cell):
				board.blue_units.erase(cell)

		# renderer
		if renderer != null and renderer.cards.has(cell):
			var dead_card: StrategosCard = renderer.cards[cell]
			renderer.cards.erase(cell)
			if is_instance_valid(dead_card):
				dead_card.queue_free()

		# nettoyer sélections/attaque si besoin
		if selected_unit_info.has("card") and selected_unit_info["card"] == target:
			selected_unit_info.clear()
			renderer.selected_unit_info.clear()
		if attacking_card == target:
			cancel_attack_mode()

		if renderer:
			renderer.queue_redraw()

func _compute_preview_damage(attacker: StrategosCard, target: StrategosCard, atk: Dictionary) -> Dictionary:
	# Renvoie un dict détaillé :
	# {
	#   "base": int,              # dégâts après on_attack_compute (bonus d'attaque)
	#   "reduction_flat": int,    # réduction fixe via défense (bouton défense) si présente
	#   "after_def": int,         # base - reduction_flat (>=0)
	#   "after_cmd": int          # après on_damage_before (commandants)
	# }
	var result := {
		"base": 0,
		"reduction_flat": 0,
		"after_def": 0,
		"after_cmd": 0
	}

	if attacker == null or target == null:
		return result
	if atk == null or atk.is_empty():
		return result

	# 1) Dégâts de base + effets d’attaque (commandants) via compute_damage_for_attack
	var base_damage := compute_damage_for_attack(attacker, target, atk)
	if base_damage < 0:
		base_damage = 0
	result["base"] = base_damage

	# 2) Réduction fixe si la cible a activé une défense (phase défense)
	var reduction_flat := 0
	if defense_queue.has(target):
		var ddef: Dictionary = defense_queue[target].get("data", {})
		if ddef.has("reduction"):
			var r = int(ddef["reduction"])
			if r > 0:
				reduction_flat = r
	result["reduction_flat"] = reduction_flat

	var after_def := base_damage - reduction_flat
	if after_def < 0:
		after_def = 0
	result["after_def"] = after_def

	# 3) Effets défensifs de commandants (on_damage_before)
	var final_val := after_def
	var dmg_ctx := {
		"board": board,
		"target": target,
		"incoming_damage": after_def
	}
	var dmg_res := EffectsEngine.on_damage_before(dmg_ctx)
	if dmg_res.has("damage"):
		final_val = int(dmg_res["damage"])
	if final_val < 0:
		final_val = 0
	result["after_cmd"] = final_val

	return result


func build_incoming_preview_bbcode(card: StrategosCard) -> String:
	var lines: Array = []
	lines.append("[b]" + card.label_name.text + " #[/b]" + str(card.uid))

	var any_incoming: bool = false

	for attacker in attack_queue.keys():
		var info: Dictionary = attack_queue[attacker]
		var target2: StrategosCard = info.get("target", null)
		var atk2: Dictionary = info.get("data", {})

		if target2 != card or attacker == null or atk2.is_empty():
			continue
		any_incoming = true

		# --- ATTACK: base brute + bonus cmd d’attaque ---
		var rng: int = int(atk2.get("range", 1))
		var dmg_raw = atk2.get("damage", 0)  # Variant (int/array)
		var base_raw: int = 0

		if typeof(dmg_raw) == TYPE_INT or typeof(dmg_raw) == TYPE_FLOAT:
			base_raw = int(dmg_raw)
		elif typeof(dmg_raw) == TYPE_ARRAY:
			var arr: Array = dmg_raw
			if arr.size() > 0:
				var dx: int = abs(attacker.cell.x - card.cell.x)
				var dy: int = abs(attacker.cell.y - card.cell.y)

				var dist: int = 1
				if rng == 1:
					dist = 1
				else:
					if dx > dy:
						dist = dx
					else:
						dist = dy
					if dist < 1:
						dist = 1

				var idx: int = dist - 1
				if idx < 0:
					idx = 0
				if idx >= arr.size():
					idx = arr.size() - 1

				var v = arr[idx]
				if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
					base_raw = int(v)
				else:
					base_raw = 0
			else:
				base_raw = 0
		else:
			base_raw = 0

		var with_cmd: int = compute_damage_for_attack(attacker, card, atk2)
		if with_cmd < 0:
			with_cmd = 0
		var atk_cmd_bonus: int = with_cmd - base_raw
		if atk_cmd_bonus < 0:
			atk_cmd_bonus = 0

		# --- DEFENSE: réduction fixe + bonus cmd défensif ---
		var red_flat: int = 0
		if defense_queue.has(card):
			var ddef: Dictionary = defense_queue[card].get("data", {})
			if ddef.has("reduction"):
				var rr: int = int(ddef["reduction"])
				if rr > 0:
					red_flat = rr

		var after_def: int = with_cmd - red_flat
		if after_def < 0:
			after_def = 0

		var final_val: int = after_def
		var dmg_ctx := {
			"board": board,
			"target": card,
			"incoming_damage": after_def
		}
		var dmg_res: Dictionary = EffectsEngine.on_damage_before(dmg_ctx)
		if dmg_res.has("damage"):
			final_val = int(dmg_res["damage"])
		if final_val < 0:
			final_val = 0

		var def_cmd_bonus: int = after_def - final_val
		if def_cmd_bonus < 0:
			def_cmd_bonus = 0

		# --- Texte : ATTAQUE puis DÉFENSE ---
		var atk_name: String = str(atk2.get("name", "Attaque"))
		lines.append("[color=#d32f2f][b]ATTAQUE[/b][/color]")
		lines.append("• " + attacker.label_name.text + "  (#" + str(attacker.uid) + ") — " + atk_name)

		var atk_line: String = "    Base : [b]" + str(base_raw) + "[/b]"
		if atk_cmd_bonus > 0:
			atk_line += "  |  Bonus commandant : [b]+" + str(atk_cmd_bonus) + "[/b]"
		lines.append(atk_line)

		lines.append("[color=#2e7d32][b]DÉFENSE[/b][/color]")
		var showed_def: bool = false
		if red_flat > 0:
			lines.append("    Base : [b]-" + str(red_flat) + "[/b]")
			showed_def = true
		if def_cmd_bonus > 0:
			lines.append("    Bonus commandant : [b]-" + str(def_cmd_bonus) + "[/b]")
			showed_def = true
		if not showed_def:
			lines.append("    (aucune)")

		lines.append("→ Dégâts estimés reçus : [b]" + str(final_val) + "[/b]")
		lines.append("")

	if not any_incoming:
		lines.append("[i]Aucune attaque entrante prévue contre cette unité.[/i]")

	return "\n".join(lines)



# --- Récupère la réduction plate de défense active sur une carte (0 si aucune) ---
func _get_defense_flat_for_card(card: StrategosCard) -> Dictionary:
	var out := {"name": "", "flat": 0}
	if defense_queue.has(card):
		var ddef: Dictionary = defense_queue[card].get("data", {})
		if ddef.has("name"):
			out["name"] = str(ddef["name"])
		if ddef.has("reduction"):
			var r := int(ddef["reduction"])
			if r < 0:
				r = 0
			out["flat"] = r
	return out


# --- Construit le BBCode du pop-up "résolution attendue" pour une carte ciblée ---
func get_hover_breakdown_bbcode(target: StrategosCard) -> String:
	# Pas de pop-up sur la colonne commandant
	if target == null:
		return ""
	if target.cell.x < 0:
		return ""

	var lines_attack: Array[String] = []
	var lines_def: Array[String] = []

	var total_before := 0
	var total_after := 0

	# Défense éventuelle de la carte (appliquée INDÉPENDAMMENT à chaque attaque entrante)
	var def_info := _get_defense_flat_for_card(target)
	var def_name := str(def_info["name"])
	var def_flat := int(def_info["flat"])

	# Parcourt toutes les attaques qui visent CETTE carte
	var found_any := false
	for attacker in attack_queue.keys():
		var info: Dictionary = attack_queue[attacker]
		var tgt: StrategosCard = info.get("target", null)
		if tgt != target:
			continue
		found_any = true

		var atk: Dictionary = info.get("data", {})
		var atk_name := str(atk.get("name", "Attaque"))

		# 1) Dégâts de base (valeur ou tableau → on prend la 1ère valeur si tableau)
		var base_dmg := 0
		var dmg_raw = atk.get("damage", 0)
		if typeof(dmg_raw) == TYPE_INT or typeof(dmg_raw) == TYPE_FLOAT:
			base_dmg = int(dmg_raw)
		elif typeof(dmg_raw) == TYPE_ARRAY:
			var arr: Array = dmg_raw
			if not arr.is_empty():
				var v0 = arr[0]
				if typeof(v0) == TYPE_INT or typeof(v0) == TYPE_FLOAT:
					base_dmg = int(v0)

		# 2) Bonus/malus offensifs via commandement (on_attack_compute)
		var off_ctx := {
			"board": board,
			"attacker": attacker,
			"target": target,
			"attack_data": atk,
			"base_damage": base_dmg
		}
		var off_res := EffectsEngine.on_attack_compute(off_ctx)
		var after_off := int(off_res.get("damage", base_dmg))
		var delta_off := after_off - base_dmg

		# 3) Défense plate de la cible (appliquée à CETTE attaque)
		var after_defense := after_off
		if def_flat > 0:
			after_defense = after_off - def_flat
			if after_defense < 0:
				after_defense = 0

		# 4) Modifs défensives via commandement (on_damage_before)
		var def_ctx := {
			"board": board,
			"target": target,
			"incoming_damage": after_defense
		}
		var def_res := EffectsEngine.on_damage_before(def_ctx)
		var final_dmg := int(def_res.get("damage", after_defense))
		var delta_def := final_dmg - after_defense  # souvent négatif (réduction)

		# Accumule les totaux
		total_before += after_off   # "avant défense" = après bonus d'attaque
		total_after += final_dmg

		# --------------------
		# Sortie détaillée
		# --------------------
		# Attaque (rouge)
		lines_attack.append("[color=#CC3333]• " + attacker.label_name.text + " — " + atk_name + "[/color]")
		lines_attack.append("[color=#CC3333]   Base : " + str(base_dmg) + "[/color]")
		if delta_off != 0:
			var off_txt := str(delta_off)
			if delta_off > 0:
				off_txt = "+" + off_txt
			lines_attack.append("[color=#CC3333]   Bonus commandement (attaque) : " + off_txt + "[/color]")
		lines_attack.append("[color=#CC3333]   Sous-total (avant défense) : " + str(after_off) + "[/color]")

		# Défense (vert)
		if def_flat > 0:
			var label_def := def_name
			if label_def == "":
				label_def = "Défense"
			lines_def.append("[color=#2E8B57]   " + label_def + " : -" + str(def_flat) + "[/color]")
		if delta_def != 0:
			lines_def.append("[color=#2E8B57]   Modifs commandement (défense) : " + str(delta_def) + "[/color]")
		lines_def.append("[color=#2E8B57]   Sous-total (après défense/effets) : " + str(final_dmg) + "[/color]")

	# Si aucune attaque ne cible cette carte
	if not found_any:
		return "[b]" + target.label_name.text + "[/b]\n[i]Aucune attaque adverse enregistrée contre cette carte.[/i]"

	# Construction du BBCode final
	var out: Array[String] = []
	out.append("[b]" + target.label_name.text + "[/b]")

	if not lines_attack.is_empty():
		out.append("")
		out.append("[b][color=#CC3333]Dégâts adverses (détail)[/color][/b]")
		for L in lines_attack:
			out.append(L)

	if not lines_def.is_empty():
		out.append("")
		out.append("[b][color=#2E8B57]Atténuations (défense / commandement)[/color][/b]")
		for L2 in lines_def:
			out.append(L2)

	out.append("")
	out.append("[b]Total estimé :[/b]  [color=#CC3333]" + str(total_before) + "[/color]  →  [b][color=#2E8B57]" + str(total_after) + "[/color][/b]")

	return "\n".join(out)


func update_all_defense_buttons() -> void:
	# Plateau
	for card in renderer.cards.values():
		if card.has_method("update_defense_buttons"):
			card.update_defense_buttons()
	# Mains
	if hand:
		for c in hand.get_children():
			if c is StrategosCard:
				c.update_defense_buttons()
	if hand2:
		for c in hand2.get_children():
			if c is StrategosCard:
				c.update_defense_buttons()
				

func show_damage_popup(target: StrategosCard, amount: int) -> void:
	if target == null or amount <= 0:
		return

	var popup := Label.new()
	popup.text = "-" + str(amount)
	popup.add_theme_color_override("font_color", Color(0, 1, 0))
	popup.add_theme_font_size_override("font_size", 20)
	popup.z_index = 100

	# Positionner le label au-dessus de la carte
	popup.position = target.position + Vector2(0, -20)

	if target.get_parent():
		target.get_parent().add_child(popup)

	# Animation simple (monte et s'efface)
	var tween := create_tween()
	tween.tween_property(popup, "position", popup.position + Vector2(0, -40), 0.8)
	tween.tween_property(popup, "modulate:a", 0.0, 0.8)
	tween.finished.connect(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)

func _tour_suffix_from_phase(p: int) -> String:
	if p == 1 or p == 2:
		return "a"
	return "b"

func update_tour_ui_label() -> void:
	if right_panel and right_panel.has_method("update_tour_label"):
		var suffix := _tour_suffix_from_phase(grand_phase)
		var phase_txt := _phase_for_local_view()
		right_panel.update_tour_label(grand_tour, suffix, phase_txt)


func _phase_for_local_view() -> String:
	var result := ""
	if current_player == local_perspective_player:
		# on voit la phase “telle quelle”
		if current_phase == "attack":
			result = "Attaque"
		else:
			result = "Défense"
	else:
		# on voit la phase “complémentaire”
		if current_phase == "attack":
			result = "Défense"
		else:
			result = "Attaque"
	return result

func load_commanders_data():
	var file = FileAccess.open("res://data/commanders.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_ARRAY:
			commanders_data = parsed
		else:
			push_error("Erreur JSON dans commanders.json : format inattendu")
	else:
		push_error("Impossible de charger commanders.json")

func load_tactics_data():
	var file = FileAccess.open("res://data/tactics.json", FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_ARRAY:
			tactics_data = parsed
		else:
			push_error("Erreur JSON dans tactics.json : format inattendu")
	else:
		push_error("Impossible de charger tactics.json")


func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		# Fin de tour -> ESPACE
		if event.keycode == KEY_SPACE:
			if current_player == get_local_player():
				switch_turn()
			else:
				_show_warning("Ce n'est pas votre tour", 1.5)

		# Changer de vue -> N
		elif event.keycode == KEY_N:
			swap_perspective()
