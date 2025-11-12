extends Control

@export var game_manager: Node = null
@onready var end_turn_button: Button = $VBoxContainer/HBoxContainer/EndTurnButton
@onready var deck_container: VBoxContainer = $VBoxContainer/DeckContainer
@onready var tour_label: Label = ($VBoxContainer/TourLabel if has_node("VBoxContainer/TourLabel") else null)


func _ready():
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	if game_manager:
		update_button_color(game_manager.current_player == game_manager.get_local_player())


func _on_end_turn_pressed():
	if not game_manager:
		return

	# Empêche le joueur dont ce n'est pas le tour d'appuyer
	if game_manager.current_player != game_manager.get_local_player():
		return

	game_manager.switch_turn()
	update_button_color(game_manager.current_player == game_manager.get_local_player())



func update_button_color(is_players_turn: bool):
	var style = StyleBoxFlat.new()
	if is_players_turn:
		style.bg_color = Color(0, 0, 1)  # bleu
	else:
		style.bg_color = Color(1, 0, 0)  # rouge

	end_turn_button.add_theme_stylebox_override("normal", style)
	end_turn_button.add_theme_stylebox_override("hover", style)
	end_turn_button.add_theme_stylebox_override("pressed", style)
	end_turn_button.add_theme_color_override("font_color", Color(1, 1, 1))
	

func update_tour_label(grand_tour: int, suffix: String, phase_text: String):
	var txt := "Tour : " + str(grand_tour) + suffix + "  –  " + phase_text
	if tour_label:
		tour_label.text = txt

