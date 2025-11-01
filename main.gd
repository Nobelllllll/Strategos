extends Control

const Board = preload("res://board/Board.gd")
const BoardRenderer = preload("res://board/BoardRenderer.gd")
const GameManager = preload("res://manager/GameManager.gd")
const UIManager = preload("res://ui/UIManager.gd")

@onready var board: Board = $Board
@onready var renderer: BoardRenderer = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer/BoardRenderer
@onready var manager: GameManager = $GameManager
@onready var ui_manager: UIManager = $UIManager

func _ready():
	renderer.board = board
	renderer.game_manager = manager
	renderer.font = load("res://assets/font/BasicFont.tres")
	ui_manager.game_manager = manager
	manager.board = board
	manager.renderer = renderer
	manager.right_panel = $MarginContainer/VBoxContainer/HBoxContainer/VBoxContainer2/RightPanel
	manager.update_tour_ui_label()


	await get_tree().create_timer(2.0).timeout
	DisplayServer.window_set_min_size(Vector2(1152, 647))
	
	set_process_unhandled_input(true)  # NEW

	

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		manager.click_handled = false  # réinitialise

		await get_tree().process_frame  # laisse le temps aux _gui_input de se déclencher

		if not manager.click_handled:
			manager.deselect_everything()
