extends Control
class_name StrategosCard

@export var game_manager: GameManager

var uid: int = 0

# Panel + Labels )
@onready var panel: Panel = $Panel
@onready var vbox: VBoxContainer = $Panel/VBoxContainer
@onready var info_container: HBoxContainer = $Panel/VBoxContainer/info_container
@onready var attacks_container: VBoxContainer = $Panel/VBoxContainer/attacks_container
@onready var label_name: Label = $Panel/VBoxContainer/info_container/Label_Name
@onready var label_hp: Label = $Panel/VBoxContainer/info_container/Label_HP


var attacks: Array = []
var attack_in_use_index: int = -1
var active_attack_name: String = ""

var defenses: Array = []
var defense_in_use_index: int = -1
var active_defense_name: String = ""



var player_color: String = ""
var cell: Vector2i = Vector2i.ZERO
var is_deck_card: bool = false
var pioched_this_turn: bool = false
var is_selected: bool = false

var is_targeted := false

var target_tween: Tween = null  # à mettre en haut du script

var targeted_by: StrategosCard = null

var blink_tween: Tween = null
var _attacker_blink_tween: Tween = null


var targeted_card: StrategosCard = null


var is_tactic: bool = false



# (optionnels, pour plus tard : titre/texte/image)
@onready var tactic_container: VBoxContainer = $Panel/VBoxContainer/tactic_container if has_node("Panel/VBoxContainer/tactic_container") else null
@onready var tactic_title: Label = $Panel/VBoxContainer/tactic_container/Tactic_Title if has_node("Panel/VBoxContainer/tactic_container/Tactic_Title") else null
@onready var tactic_text: Label = $Panel/VBoxContainer/tactic_container/Tactic_Text if has_node("Panel/VBoxContainer/tactic_container/Tactic_Text") else null
@onready var tactic_image: TextureRect = $Panel/VBoxContainer/tactic_container/Tactic_Image if has_node("Panel/VBoxContainer/tactic_container/Tactic_Image") else null


var is_commander: bool = false
var is_commander_card: bool = false

var _hover_timer: Timer = null
var _preview_popup: Panel = null
var _preview_label: RichTextLabel = null
var _last_mouse_local := Vector2.ZERO

var _is_mouse_inside: bool = false

var _attacker_highlight_panel: Panel = null
var _attacker_highlight: bool = false

var _target_highlight_panel: Panel = null
var _target_blink_tween: Tween = null



func _ready():
	


	update_attack_buttons()
	update_defense_buttons()

	
	if panel:
		panel.mouse_filter = MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", get_default_style())

	if info_container:
		info_container.custom_minimum_size = Vector2(50, 20)
		info_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if label_name:
		label_name.visible = true
		label_name.text = ""
		label_name.custom_minimum_size = Vector2(40, 15)
		label_name.add_theme_color_override("font_color", Color(1, 1, 1))

	if label_hp:
		label_hp.visible = true
		label_hp.text = ""
		label_hp.custom_minimum_size = Vector2(40, 15)
		label_hp.add_theme_color_override("font_color", Color(1, 1, 1))
	
		# --- Préview au survol long (1s) ---
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = 1.0
	add_child(_hover_timer)
	_hover_timer.timeout.connect(_on_hover_timeout)

	# Signaux de survol
	mouse_entered.connect(_on_card_mouse_entered)
	mouse_exited.connect(_on_card_mouse_exited)


func setup(player_color_in: String, cell_pos: Vector2i, cell_size: Vector2):
	player_color = player_color_in
	cell = cell_pos
	is_deck_card = (cell == Vector2i.ZERO)
	mouse_filter = MOUSE_FILTER_STOP

	var width = cell_size.x * 0.9
	var height = width / 2.0
	var final_size = Vector2(width, height)
	custom_minimum_size = final_size
	size = final_size
	position = (Vector2(cell) + Vector2(1, 0)) * cell_size + (cell_size - final_size) * 0.5

	if panel:
		panel.size = final_size
		panel.custom_minimum_size = final_size
		panel.clip_contents = true
		panel.add_theme_stylebox_override("panel", get_default_style())

	if info_container:
		info_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		info_container.offset_left = 0
		info_container.offset_top = 0
		info_container.offset_right = 0
		info_container.offset_bottom = 0
		info_container.size_flags_horizontal = Control.SIZE_FILL
		info_container.size_flags_vertical = Control.SIZE_FILL
		info_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var unit_type = "Hoplite"
	if game_manager and game_manager.units_data.has(unit_type):
		var unit_info = game_manager.units_data[unit_type]
		if label_name:
			label_name.text = unit_info["name"]
		if label_hp:
			label_hp.text = str(unit_info["hp"]) + " PV"
	else:
		if label_name:
			label_name.text = "???"
		if label_hp:
			label_hp.text = "0 PV"

func setup_from_unit_data(unit_data: Dictionary, cell_size: Vector2, real_player_color: String) -> void:

	# ✅ Taille de la carte
	var card_width = cell_size.x * 0.9
	var card_height = card_width / 2.0
	custom_minimum_size = Vector2(card_width, card_height)
	size = custom_minimum_size



	# ✅ Ancrage et centrage
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_top = 0
	vbox.offset_right = 0
	vbox.offset_bottom = 0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	label_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	attacks = unit_data.get("attacks", [])
	defenses = unit_data.get("defenses", [])

	# ✅ Remplissage des infos
	label_name.text = unit_data.get("name", "???")
	label_hp.text = str(unit_data.get("hp", "-")) + " PV"

	# ✅ Stocker la vraie couleur
	self.player_color = real_player_color

	# ✅ Appliquer le style
	if panel:
		panel.add_theme_stylebox_override("panel", get_default_style())

	# ✅ Nettoyage ancien contenu
	for child in attacks_container.get_children():
		attacks_container.remove_child(child)
		child.queue_free()

	# ✅ Déterminer si l’unité appartient au joueur actif local
	var is_clickable := (
		game_manager
		and real_player_color == game_manager.current_player
		and real_player_color == game_manager.local_perspective_player
	)

	# ✅ Génération dynamique des attaques
	# ✅ Génération dynamique des attaques
	if unit_data.has("attacks"):
		for attack in unit_data["attacks"]:
			var label = Label.new()
			label.text = attack.get("name", "Attaque")

			var button = Button.new()
			button.text = "+"
			button.custom_minimum_size = Vector2(20, 20)
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_filter = MOUSE_FILTER_IGNORE if not is_clickable else MOUSE_FILTER_STOP
			button.pressed.connect(_on_attack_pressed.bind(attack))
			button.set_meta("kind", "attack")          # ✚

			var hbox = HBoxContainer.new()
			hbox.set_meta("kind", "attack")            # ✚
			hbox.add_child(label)
			hbox.add_child(button)
			attacks_container.add_child(hbox)

	# ✅ Génération dynamique des DEFENSES (affichées en permanence)
	if unit_data.has("defenses"):
		for defense in unit_data["defenses"]:
			var label_d = Label.new()
			label_d.text = defense.get("name", "Défense")

			var btn_d = Button.new()
			btn_d.text = "●"  # icône simple
			btn_d.custom_minimum_size = Vector2(20, 20)
			btn_d.focus_mode = Control.FOCUS_NONE
			btn_d.pressed.connect(_on_defense_pressed.bind(defense))
			btn_d.set_meta("kind", "defense")          # ✚

			var hbox_d = HBoxContainer.new()
			hbox_d.set_meta("kind", "defense")         # ✚
			hbox_d.add_child(label_d)
			hbox_d.add_child(btn_d)
			attacks_container.add_child(hbox_d)


# Important : on fera l'activation/désactivation via update_defense_buttons()

	# ✅ Important : toujours rendre la carte cliquable, on filtre dans _gui_input()
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup_as_tactic(cell_size: Vector2, real_player_color: String, data: Dictionary = {}) -> void:
	is_tactic = true
	player_color = real_player_color
	is_deck_card = true

	# Taille
	var card_width = cell_size.x * 0.9
	var card_height = card_width / 2.0
	custom_minimum_size = Vector2(card_width, card_height)
	size = custom_minimum_size

	# Couleur du joueur
	if panel:
		panel.add_theme_stylebox_override("panel", get_default_style())

	# Masquer tout ce qui concerne les unités
	if label_name:
		label_name.text = ""
		label_name.visible = false
	if label_hp:
		label_hp.text = ""
		label_hp.visible = false
	if has_node("Panel/VBoxContainer/attacks_container"):
		var ac = get_node("Panel/VBoxContainer/attacks_container")
		ac.visible = false
	attacks = []
	defenses = []
	update_attack_button_states()
	update_defense_button_states()

	# (Pour plus tard) Affichage de contenu si fourni
	var has_any := false
	if tactic_container != null:
		tactic_container.visible = true

		if tactic_title != null and data.has("title"):
			var t = str(data["title"])
			tactic_title.text = t
			tactic_title.visible = (t != "")
			if t != "":
				has_any = true
		elif tactic_title != null:
			tactic_title.text = ""
			tactic_title.visible = false

		if tactic_text != null and data.has("text"):
			var tx = str(data["text"])
			tactic_text.text = tx
			tactic_text.visible = (tx != "")
			if tx != "":
				has_any = true
		elif tactic_text != null:
			tactic_text.text = ""
			tactic_text.visible = false

		if tactic_image != null and data.has("image_path"):
			var p = str(data["image_path"])
			if p != "":
				var tex: Texture2D = load(p)
				if tex != null:
					tactic_image.texture = tex
					tactic_image.visible = true
					has_any = true
				else:
					tactic_image.texture = null
					tactic_image.visible = false
			else:
				tactic_image.texture = null
				tactic_image.visible = false

		if not has_any:
			tactic_container.visible = false

func setup_as_commander(cell_size: Vector2, real_player_color: String, data: Dictionary = {}) -> void:
	is_commander = true
	player_color = real_player_color
	is_deck_card = false  # sur le plateau

	# Taille
	var card_width = cell_size.x * 0.9
	var card_height = card_width / 2.0
	custom_minimum_size = Vector2(card_width, card_height)
	size = custom_minimum_size

	# Couleur du joueur (cadre doré géré par get_default_style car is_commander = true)
	if panel:
		panel.add_theme_stylebox_override("panel", get_default_style())

	# Masquer les infos PV + container d'attaques
	if label_hp:
		label_hp.text = ""
		label_hp.visible = false
	if has_node("Panel/VBoxContainer/attacks_container"):
		var ac = get_node("Panel/VBoxContainer/attacks_container")
		ac.visible = false
	attacks = []
	defenses = []
	update_attack_button_states()
	update_defense_button_states()

	# 👉 Détermination automatique du nom
	var display_name := "Commandant"
	if typeof(data) == TYPE_DICTIONARY:
		if data.has("commander_id"):
			display_name = _resolve_commander_name(str(data["commander_id"]))
		elif data.has("display_name"):
			var dn := str(data["display_name"])
			if dn != "":
				display_name = dn
		elif data.has("name"):
			var n2 := str(data["name"])
			if n2 != "":
				display_name = n2
		elif data.has("type"):
			var t := str(data["type"])
			if t != "":
				display_name = t

	# ✅ Affichage du nom centré
	if label_name:
		label_name.visible = true
		label_name.text = display_name
		label_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_name.add_theme_color_override("font_color", Color(1, 1, 1))
		label_name.custom_minimum_size = Vector2(40, 15)

	# Assurer le plein ancrage du vbox
	if vbox:
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 0
		vbox.offset_top = 0
		vbox.offset_right = 0
		vbox.offset_bottom = 0
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Carte cliquable si besoin (mouvements autorisés selon tes règles)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup_as_commander_card(cell_size: Vector2, real_player_color: String, commander_name: String) -> void:
	is_commander_card = true
	is_tactic = false
	player_color = real_player_color
	is_deck_card = true

	# Taille de la carte
	var card_width := cell_size.x * 0.9
	var card_height := card_width / 2.0
	custom_minimum_size = Vector2(card_width, card_height)
	size = custom_minimum_size

	# Cadre / couleur selon le joueur (+ doré car carte commandant)
	if panel:
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.size = size
		panel.clip_contents = true
		panel.add_theme_stylebox_override("panel", get_default_style())

	# Ancrage et centrage du contenu
	if vbox:
		vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		vbox.offset_left = 0
		vbox.offset_top = 0
		vbox.offset_right = 0
		vbox.offset_bottom = 0
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# ✅ Le BON label (même que sur le plateau)
	if label_name:
		label_name.visible = true
		label_name.text = commander_name
		label_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label_name.add_theme_color_override("font_color", Color(1, 1, 1))
		label_name.custom_minimum_size = Vector2(40, 15)

	# PV et attaques masqués pour une carte de commandant piochée
	if label_hp:
		label_hp.text = ""
		label_hp.visible = false
	if attacks_container:
		attacks_container.visible = false
	# Si tu as un defense_container dans la scène, masque-le aussi :
	if has_node("Panel/VBoxContainer/defense_container"):
		get_node("Panel/VBoxContainer/defense_container").visible = false

	# Boutons inutiles ici
	attacks = []
	defenses = []
	update_attack_button_states()
	update_defense_button_states()

	# La carte de main ne vit pas sur la grille : pas de positionnement grid
	mouse_filter = Control.MOUSE_FILTER_STOP

func _is_in_commander_column() -> bool:
	return cell.x < 0


func _resolve_commander_name(commander_id: String) -> String:
	if game_manager == null:
		return "Commandant"

	# On parcourt les données de tous les commandants
	for e in game_manager.commanders_data:
		if typeof(e) == TYPE_DICTIONARY and e.has("id"):
			if str(e["id"]) == commander_id:
				if e.has("name"):
					var n := str(e["name"])
					if n != "":
						return n

	# Si rien trouvé, valeur par défaut
	return "Commandant"


	
func update_attack_buttons():
	if game_manager == null:
		print("❌ update_attack_buttons ignorée car game_manager est null pour", self.name)
		return
	if not has_node("Panel/VBoxContainer/attacks_container"):
		return

	var attacks_container = get_node("Panel/VBoxContainer/attacks_container")
	var is_current_turn = (player_color == game_manager.current_player)
	var is_local_player = (player_color == game_manager.local_perspective_player)
	var enable = false
	if is_current_turn and is_local_player and game_manager.current_phase == "attack":
		enable = true

	for child in attacks_container.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			# n’agir QUE sur les attaques
			var is_attack = false
			if child.has_meta("kind"):
				var k = str(child.get_meta("kind"))
				if k == "attack":
					is_attack = true
			if not is_attack:
				continue

			var button = child.get_child(1)
			if button is Button:
				button.focus_mode = Control.FOCUS_NONE
				if enable:
					button.mouse_filter = Control.MOUSE_FILTER_STOP
				else:
					button.mouse_filter = Control.MOUSE_FILTER_IGNORE



func _on_attack_pressed(attack_data):
	if not game_manager:
		return

	if game_manager.current_player != player_color:
		game_manager._show_warning("Ce n'est pas votre unité", 1.5)
		return

	if game_manager.get_local_player() != player_color:
		game_manager._show_warning("Ce n'est pas votre main", 1.5)
		return

	if not is_selected:
		game_manager._show_warning("Sélectionnez d'abord cette carte", 1.5)
		return

	# ✅ Même attaque re-cliquée = annule la phase
	if game_manager.is_attack_mode and game_manager.attacking_card == self and game_manager.active_attack_data.get("name", "") == attack_data["name"]:
		print("❌ Attaque désactivée (sans cible) :", attack_data.get("name", "???"), "par", label_name.text)
		game_manager.cancel_attack_mode()
		update_attack_button_states()
		update_grayscale()
		return

	# ✅ Activation de la phase de ciblage (attaque non encore lancée)
	active_attack_name = attack_data["name"]
	game_manager.enter_attack_mode(self, attack_data)
	print("🎯 Phase de ciblage ouverte :", attack_data.get("name", "???"), "par", label_name.text)
	update_attack_button_states()
	update_grayscale()



func update_attack_button_states():
	var attacks_container = $Panel/VBoxContainer/attacks_container
	for hbox in attacks_container.get_children():
		if hbox is HBoxContainer:
			var label = hbox.get_child(0)
			var button = hbox.get_child(1)
			if button and label and label is Label and button is Button:
				if targeted_card != null and label.text == active_attack_name:
					button.text = "✓"
				else:
					button.text = "+"



func update_position(cell_size: Vector2, flipped := false, grid_width := 6, grid_height := 6):
	var x = cell.x
	var y = cell.y
	if flipped:
		if is_commander:
			# Commandant : on garde x tel quel (colonne -1), on inverse seulement y
			y = grid_height - 1 - y
		else:
			x = grid_width - 1 - x
			y = grid_height - 1 - y

	var width = cell_size.x * 0.9
	var height = width / 2.0
	var final_size = Vector2(width, height)
	custom_minimum_size = final_size
	size = final_size
	position = (Vector2(x, y) + Vector2(1, 0)) * cell_size + (cell_size - final_size) * 0.5
	if panel:
		panel.size = final_size


func set_selected(selected: bool) -> void:
	is_selected = selected

	if selected:
		var border := StyleBoxFlat.new()
		border.bg_color = get_default_style().bg_color
		border.set_border_width_all(4)
		border.border_color = Color(1, 1, 0)  # cadre jaune
		panel.add_theme_stylebox_override("panel", border)

		# Si cette carte a déjà une cible enregistrée, s'assurer que le marquage repart
		if targeted_card != null:
			targeted_card.set_targeted(true, self)
	else:
		panel.add_theme_stylebox_override("panel", get_default_style())

		# Si cette carte faisait clignoter une cible, couper le blink
		if targeted_card != null:
			targeted_card.stop_target_blink()

		# Si on était en phase d'attaque avec cette carte → quitter la phase
		if game_manager != null and game_manager.is_attack_mode and game_manager.attacking_card == self:
			game_manager.cancel_attack_mode()

	update_attack_button_states()
	update_defense_button_states()

	# Le grisage dépend du manager (phase de ciblage) → on ne le décide pas ici

	# 🔁 BLINK : le marquage doit exister tant que la carte qui cible est sélectionnée,
	# même hors phase de ciblage. Donc on rafraîchit EN FONCTION de "self".
	if game_manager != null:
		if selected:
			game_manager.refresh_target_blinks_for(self)
		else:
			game_manager.refresh_target_blinks_for(null)

		# Et on laisse le manager recalculer le grisage selon la phase
		game_manager.recompute_grayouts()
	
	if not selected:
		_hover_timer.stop()
		_hide_preview_popup()
	else:
		if _is_mouse_inside:
			if _is_in_commander_column():
				return
			_last_mouse_local = get_local_mouse_position()
			_hover_timer.start()

	# harmoniser l’overlay après (dé)sélection
	_ensure_attacker_highlight_panel()
	if is_selected:
		_attacker_highlight_panel.visible = false
	else:
		_attacker_highlight_panel.visible = _attacker_highlight
	
		# Harmonisation de l’overlay ciblé après (dé)sélection
	_ensure_target_highlight_panel()
	if is_targeted:
		# si l’attaquant est sélectionné → blink, sinon cadre fixe
		if targeted_by != null and targeted_by.is_selected:
			start_target_blink()
		else:
			stop_target_blink()  # garde visible sans animation
	else:
		_target_highlight_panel.visible = false




func get_selected_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	var display_color = game_manager.get_display_color(player_color)
	if display_color == "RED":
		style.bg_color = Color(1, 0, 0)
	else:
		style.bg_color = Color(0, 0, 1)
	style.border_color = Color(0, 1, 0)
	style.set_border_width_all(2)
	return style

func get_default_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	if game_manager:
		var display_color = game_manager.get_display_color(player_color)
		if display_color == "RED":
			style.bg_color = Color(1, 0, 0)
		else:
			style.bg_color = Color(0, 0, 1)
	else:
		style.bg_color = Color(0.5, 0.5, 0.5)

	# Contour doré pour généraux ET cartes commandant piochées
	if is_commander or is_commander_card:
		style.border_color = Color(0.95, 0.8, 0.2)
		style.set_border_width_all(3)
	else:
		style.border_color = Color(0.8, 0.8, 0.8)
		style.set_border_width_all(1)
	return style



func _apply_selected_frame() -> void:
	var border := StyleBoxFlat.new()
	border.bg_color = get_default_style().bg_color
	border.set_border_width_all(4)
	# 🟨 Général reste doré même sélectionné (plus lisible)
	if is_commander:
		border.border_color = Color(0.95, 0.8, 0.2)
	else:
		border.border_color = Color(1, 1, 0)  # jaune pour les autres
	panel.add_theme_stylebox_override("panel", border)

	
func _apply_default_frame() -> void:
	panel.add_theme_stylebox_override("panel", get_default_style())

func set_targeted(targeted: bool, attacker_card: StrategosCard = null) -> void:
	is_targeted = targeted
	if targeted:
		targeted_by = attacker_card
	else:
		targeted_by = null

	_ensure_target_highlight_panel()

		# Blink/visibilité selon la règle "attaquant sélectionné seulement"
	if targeted_by != null and targeted_by.is_selected and is_targeted:
		start_target_blink()
	else:
		stop_target_blink()

	update_grayscale()

	





func start_target_blink() -> void:
	_ensure_target_highlight_panel()

	# Affiche seulement si l’attaquant est sélectionné
	var show := (is_targeted and targeted_by != null and targeted_by.is_selected)
	if not show:
		_target_highlight_panel.visible = false
		# Pas de blink si pas montré
		if _target_blink_tween:
			_target_blink_tween.kill()
			_target_blink_tween = null
		return

	_target_highlight_panel.visible = true

	# Stop ancien tween
	if _target_blink_tween:
		_target_blink_tween.kill()
		_target_blink_tween = null

	var sb := _target_highlight_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.9, 0.2, 1.0)
		_target_highlight_panel.add_theme_stylebox_override("panel", sb)

	_target_blink_tween = create_tween()
	_target_blink_tween.set_loops()
	_target_blink_tween.tween_method(func(t): sb.border_color = Color(0.3, 1.0, 0.4), 0.0, 1.0, 0.45)
	_target_blink_tween.tween_method(func(t): sb.border_color = Color(0.1, 0.8, 0.2), 0.0, 1.0, 0.45)


func stop_target_blink() -> void:
	if _target_blink_tween:
		_target_blink_tween.kill()
		_target_blink_tween = null

	_ensure_target_highlight_panel()

	# ⚠️ Nouveau comportement :
	# Le cadre ne reste PAS visible si l’attaquant n’est pas sélectionné.
	var show := (is_targeted and targeted_by != null and targeted_by.is_selected)
	_target_highlight_panel.visible = show

func start_attacker_blink() -> void:
	_ensure_attacker_highlight_panel()
	_attacker_highlight_panel.visible = true

	# Stop ancien tween
	if _attacker_blink_tween:
		_attacker_blink_tween.kill()
		_attacker_blink_tween = null

	# Anime la bordure de l’overlay attaquant
	var sb := _attacker_highlight_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(3)
		sb.border_color = Color(0.75, 0.35, 0.95)
		_attacker_highlight_panel.add_theme_stylebox_override("panel", sb)

	_attacker_blink_tween = create_tween()
	_attacker_blink_tween.set_loops()
	_attacker_blink_tween.tween_method(
		func(t):
			sb.border_color = Color(0.9, 0.5, 1.0),
		0.0, 1.0, 0.45
	)
	_attacker_blink_tween.tween_method(
		func(t):
			sb.border_color = Color(0.6, 0.25, 0.85),
		0.0, 1.0, 0.45
	)

func stop_attacker_blink() -> void:
	if _attacker_blink_tween:
		_attacker_blink_tween.kill()
		_attacker_blink_tween = null
	_ensure_attacker_highlight_panel()
	# Si highlight actif, on garde le cadre fixe ; sinon on cache
	if _attacker_highlight:
		var sb := _attacker_highlight_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if sb == null:
			sb = StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(3)
			sb.border_color = Color(0.75, 0.35, 0.95)
			_attacker_highlight_panel.add_theme_stylebox_override("panel", sb)
		_attacker_highlight_panel.visible = true
	else:
		_attacker_highlight_panel.visible = false


func _ensure_target_highlight_panel() -> void:
	if _target_highlight_panel != null:
		return
	_target_highlight_panel = Panel.new()
	_target_highlight_panel.name = "TargetHighlight"
	_target_highlight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_highlight_panel.z_index = 950
	_target_highlight_panel.visible = false
	_target_highlight_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)  # fond transparent
	sb.set_border_width_all(3)
	sb.border_color = Color(0.2, 1.0, 0.3)  # violet/rose (cible)
	_target_highlight_panel.add_theme_stylebox_override("panel", sb)

	add_child(_target_highlight_panel)


func set_attacker_highlight(active: bool) -> void:
	_attacker_highlight = active
	_ensure_attacker_highlight_panel()
	if is_selected:
		# priorité visuelle : la sélection (jaune) l’emporte
		_attacker_highlight_panel.visible = false
	else:
		_attacker_highlight_panel.visible = active


func _ensure_attacker_highlight_panel() -> void:
	if _attacker_highlight_panel != null:
		return
	_attacker_highlight_panel = Panel.new()
	_attacker_highlight_panel.name = "AttackerHighlight"
	_attacker_highlight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attacker_highlight_panel.z_index = 900
	_attacker_highlight_panel.visible = false
	_attacker_highlight_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)   # fond transparent
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 0.35, 0.95)  # violet
	_attacker_highlight_panel.add_theme_stylebox_override("panel", sb)

	add_child(_attacker_highlight_panel)

func _refresh_frame() -> void:
	# Priorités visuelles :
	# 1) sélection (jaune)    — déjà gérée par set_selected()
	# 2) blink de cible       — géré ailleurs, ne touche pas l’attaquant
	# 3) highlight attaquant  — notre cadre violet
	# 4) cadre par défaut
	if panel == null:
		return

	if is_selected:
		_apply_selected_frame()
		return

	if _attacker_highlight:
		var s := StyleBoxFlat.new()
		var base := get_default_style()
		s.bg_color = base.bg_color
		s.set_border_width_all(3)
		s.border_color = Color(0.75, 0.35, 0.95)  # violet
		panel.add_theme_stylebox_override("panel", s)
		return

	# sinon, style normal
	_apply_default_frame()


# --- Grisage (NE TOUCHE PAS AU CADRE, seulement au modulate) ---
func update_grayscale() -> void:
	var should_gray_out: bool = false

	if game_manager == null or not is_instance_valid(game_manager):
		material = null
		modulate = Color(1, 1, 1, 1)
		return

	# On grise uniquement en phase d'attaque, avec attaquant sélectionné, et pour les ENNEMIS hors portée
	if game_manager.is_attack_mode and game_manager.attacking_card != null:
		var attacker: StrategosCard = game_manager.attacking_card
		if player_color != attacker.player_color:
			if attacker.is_selected:
				var attack_range: int = 1
				if not game_manager.active_attack_data.is_empty():
					if game_manager.active_attack_data.has("range"):
						attack_range = int(game_manager.active_attack_data["range"])

				var dx: int = abs(cell.x - attacker.cell.x)
				var dy: int = abs(cell.y - attacker.cell.y)

				var in_range: bool = false
				if attack_range == 1:
					if dx + dy == 1:
						in_range = true
				else:
					if dx <= attack_range and dy <= attack_range:
						in_range = true

				if not in_range:
					should_gray_out = true

	# Application visuelle : modulate hérite aux enfants, ne touche pas au cadre
	if should_gray_out:
		material = null
		modulate = Color(0.5, 0.5, 0.5, 1.0)
	else:
		material = null
		modulate = Color(1, 1, 1, 1)

func update_defense_buttons() -> void:
	if game_manager == null:
		return
	if not has_node("Panel/VBoxContainer/attacks_container"):
		return

	var attacks_container = get_node("Panel/VBoxContainer/attacks_container")
	var is_current_turn = (player_color == game_manager.current_player)
	var is_local_player = (player_color == game_manager.local_perspective_player)
	var enable = false
	if is_current_turn and is_local_player and game_manager.current_phase == "defense":
		enable = true

	for child in attacks_container.get_children():
		if child is HBoxContainer and child.get_child_count() >= 2:
			# n’agir QUE sur les défenses
			var is_defense = false
			if child.has_meta("kind"):
				var k = str(child.get_meta("kind"))
				if k == "defense":
					is_defense = true
			if not is_defense:
				continue

			var button = child.get_child(1)
			if button is Button:
				button.focus_mode = Control.FOCUS_NONE
				if enable:
					button.mouse_filter = Control.MOUSE_FILTER_STOP
				else:
					button.mouse_filter = Control.MOUSE_FILTER_IGNORE



func _on_defense_pressed(defense_data: Dictionary) -> void:
	if game_manager == null:
		return

	# Mêmes checks que l’attaque
	if game_manager.current_player != player_color:
		game_manager._show_warning("Ce n'est pas votre unité", 1.5)
		return

	if game_manager.get_local_player() != player_color:
		game_manager._show_warning("Ce n'est pas votre main", 1.5)
		return

	if not is_selected:
		game_manager._show_warning("Sélectionnez d'abord cette carte", 1.5)
		return

	# Toggle via GameManager (il vérifie la phase 'defense')
	game_manager.toggle_defense(self, defense_data)

	# Mettre à jour l’état local (comme pour l’attaque)
	if game_manager.defense_queue.has(self):
		active_defense_name = str(defense_data.get("name", ""))
		defense_in_use_index = -1
		for i in range(defenses.size()):
			var d = defenses[i]
			var dname = ""
			if d.has("name"):
				dname = str(d["name"])
			if dname == active_defense_name:
				defense_in_use_index = i
				break
	else:
		active_defense_name = ""
		defense_in_use_index = -1

	update_defense_button_states()

	
func update_defense_button_states() -> void:
	if not has_node("Panel/VBoxContainer/attacks_container"):
		return

	var attacks_container = get_node("Panel/VBoxContainer/attacks_container")

	# Récupérer le nom actif (source de vérité = GameManager)
	var active_name := ""
	if game_manager != null and game_manager.defense_queue.has(self):
		var data: Dictionary = game_manager.defense_queue[self].get("data", {})
		if data.has("name"):
			active_name = str(data["name"])

	# Mettre à jour chaque ligne "defense"
	for hbox in attacks_container.get_children():
		if hbox is HBoxContainer and hbox.get_child_count() >= 2:
			var label = hbox.get_child(0)
			var button = hbox.get_child(1)
			if label is Label and button is Button:
				var is_defense_row := false
				if hbox.has_meta("kind"):
					var k = str(hbox.get_meta("kind"))
					if k == "defense":
						is_defense_row = true

				if is_defense_row:
					if active_name != "" and label.text == active_name:
						button.text = "✓"
					else:
						button.text = "●"


func set_defense_active(active: bool, defense_data: Dictionary) -> void:
	if active:
		active_defense_name = ""
		if defense_data.has("name"):
			active_defense_name = str(defense_data["name"])
		defense_in_use_index = -1
		for i in range(defenses.size()):
			var dname = ""
			if defenses[i].has("name"):
				dname = str(defenses[i]["name"])
			if dname == active_defense_name:
				defense_in_use_index = i
				break
	else:
		active_defense_name = ""
		defense_in_use_index = -1

	update_defense_button_states()


func _ensure_preview_popup() -> void:
	if _preview_popup == null:
		_preview_popup = Panel.new()
		_preview_popup.name = "PreviewPopup"
		_preview_popup.top_level = true    
		_preview_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_preview_popup.z_index = 1000
		_preview_popup.visible = false

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.set_border_width_all(1)
		style.border_color = Color(0.3, 0.3, 0.3)
		# marges internes (padding) -> utilisées pour le calcul de taille
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		_preview_popup.add_theme_stylebox_override("panel", style)

		_preview_label = RichTextLabel.new()
		_preview_label.bbcode_enabled = true
		_preview_label.fit_content = true
		_preview_label.scroll_active = false
		_preview_label.visible_ratio = 1.0
		_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preview_label.add_theme_color_override("default_color", Color.WHITE)
		_preview_label.add_theme_font_size_override("normal_font_size", 13)
		# largeur cible pour l’habillage du texte (le panel prendra + padding)
		_preview_label.custom_minimum_size = Vector2(260, 0)

		_preview_popup.add_child(_preview_label)
		add_child(_preview_popup)




func _on_card_mouse_entered() -> void:
	_is_mouse_inside = true
	if not is_selected:
		return
	if _is_in_commander_column():
		return
	_last_mouse_local = get_local_mouse_position()
	_hover_timer.start()




func _on_card_mouse_exited() -> void:
	_is_mouse_inside = false
	_hover_timer.stop()
	_hide_preview_popup()



func _on_hover_timeout() -> void:
	if not is_selected:
		return
	if _is_in_commander_column():
		return
	_show_preview_popup()



func _show_preview_popup() -> void:
	if game_manager == null:
		return
	if _is_in_commander_column():
		return

	_ensure_preview_popup()

	# (Re)remplir le contenu via BBCode
	var txt := game_manager.build_incoming_preview_bbcode(self)

	_preview_label.bbcode_enabled = true
	_preview_label.text = ""              # reset propre
	_preview_label.clear()
	_preview_label.bbcode_text = txt

	# Si texte vide (ex: colonne commandant), on cache tout de suite
	if txt == "" or txt.strip_edges() == "":
		_preview_popup.visible = false
		return


	# ——— dimensionnement ———
	# hauteur du contenu du RichTextLabel (la largeur est fixée par custom_minimum_size.x)
	var content_h: float = float(_preview_label.get_content_height())
	var style: StyleBox = _preview_popup.get_theme_stylebox("panel")
	var pad_h := 0.0
	var pad_v := 0.0
	if style != null:
		pad_h = style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
		pad_v = style.get_content_margin(SIDE_TOP) + style.get_content_margin(SIDE_BOTTOM)

	var target_size := Vector2(_preview_label.custom_minimum_size.x + pad_h, content_h + pad_v)
	_preview_popup.custom_minimum_size = target_size
	_preview_popup.size = target_size

	# --- dimensionnement calculé juste avant (conserve ton code) ---

	# --- positionnement global : coin bas-gauche sur le curseur ---
	var cursor: Vector2 = get_viewport().get_mouse_position()  # coords écran
	var popup_size: Vector2 = _preview_popup.size
	var pos: Vector2 = Vector2(cursor.x, cursor.y - popup_size.y)

	# clamp dans l'écran (viewport), pas dans la carte
	var vp_size: Vector2 = get_viewport_rect().size
	if pos.x < 0.0:
		pos.x = 0.0
	if pos.y < 0.0:
		pos.y = 0.0
	if pos.x + popup_size.x > vp_size.x:
		pos.x = vp_size.x - popup_size.x
	if pos.y + popup_size.y > vp_size.y:
		pos.y = vp_size.y - popup_size.y

	_preview_popup.position = pos
	_preview_popup.visible = true






func _hide_preview_popup() -> void:
	if _preview_popup != null and is_instance_valid(_preview_popup):
		_preview_popup.visible = false







func _gui_input(event):
	if event is InputEventMouseMotion:
		_last_mouse_local = event.position
		
	if event is InputEventMouseButton and event.pressed:
		if game_manager:
			game_manager.click_handled = true

			# 🟣 Clic pendant la phase de ciblage (attaque)
			# Règles :
			#  - Il faut être en mode attaque
			#  - "self" doit être une CARTE ENNEMIE
			#  - L'attaquant doit être sélectionné
			#  - La cible DOIT être dans la portée (sinon on ignore le clic)
			if game_manager.is_attack_mode and game_manager.attacking_card != null:
				var attacker: StrategosCard = game_manager.attacking_card

				# Ennemi uniquement
				if player_color != game_manager.current_player:
					# Vérifier que l'attaquant est bien sélectionné
					if attacker.is_selected:
						# ⛔ Refuser le ciblage hors de portée
						var in_range: bool = game_manager.is_card_in_attack_range(attacker, self)
						if not in_range:
							game_manager._show_warning("Cible hors de portée", 1.5)
							get_viewport().set_input_as_handled()
							return

						# ✅ Dans la portée → toggle ciblage proprement
						if attacker.targeted_card == self:
							# --- DÉCIBLAGE ---
							attacker.targeted_card = null
							set_targeted(false)

							# Retirer de la file d’attaques
							game_manager.unregister_attack_target(attacker)

							# Log
							var aname: String = ""
							if not game_manager.active_attack_data.is_empty():
								if game_manager.active_attack_data.has("name"):
									# (pas de ternaire)
									aname = str(game_manager.active_attack_data["name"])
							print("❌ Attaque désactivée :", aname,
								"| cible retirée :", label_name.text, "(UID:", uid, ")",
								"| attaquant :", attacker.label_name.text, "(UID:", attacker.uid, ")")

						else:
							# --- NOUVELLE CIBLE ---
							if attacker.targeted_card != null:
								attacker.targeted_card.set_targeted(false)
							attacker.targeted_card = self
							set_targeted(true, attacker)

							# Enregistrer dans la file d’attaques
							game_manager.register_attack_target(attacker, self)

							# Log
							var aname2: String = ""
							if not game_manager.active_attack_data.is_empty():
								if game_manager.active_attack_data.has("name"):
									aname2 = str(game_manager.active_attack_data["name"])
							print("✅ Attaque activée :", aname2,
								"| cible :", label_name.text, "(UID:", uid, ")",
								"| attaquant :", attacker.label_name.text, "(UID:", attacker.uid, ")")

						attacker.update_attack_button_states()

						# Blink : doit être visible tant que l'attaquant est sélectionné
						game_manager.refresh_target_blinks_for(attacker)

						get_viewport().set_input_as_handled()
						return

			# 🟡 Sinon : sélection normale de la carte (main/plateau)
			game_manager.select_card(self)

