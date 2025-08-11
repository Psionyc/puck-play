extends Control




func _on_ai_pressed():
	if(GameManager.scene_manager):
		GameManager.scene_manager.transition_to("res://scenes/ui/PlayWithAI.tscn")
	else:
		print("Damn it")
