extends CanvasLayer

@export var game_manager: GameManager = null
@onready var switch_view_button: Button = $SwitchViewButton

func _ready():
	switch_view_button.pressed.connect(_on_switch_view_pressed)

func _on_switch_view_pressed():
	if game_manager:
		game_manager.swap_perspective()
