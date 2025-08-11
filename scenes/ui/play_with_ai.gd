extends Control
@onready var hbox = $Panel/HBoxContainer

func _ready():
	for child in hbox.get_children():
		if(child.has_signal("pressed")):
			child.connect("pressed", start_game)


func _on_play_with_ai_button_pressed():
	GameManager.scene_manager.show_game_scene()


func start_game():
	GameManager.scene_manager.transition_to("res://scenes/game/screens/PuckPlayAI.tscn")
