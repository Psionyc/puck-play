extends Node
class_name SceneManager

@onready var never_delete := $NeverDelete
@onready var main_screen := $NeverDelete/MainScreen


@export var fade_time := 0.25

func _ready():
	GameManager.scene_manager = self
	var farcasterSDK = JavaScriptBridge.get_interface("sdk");
	print(farcasterSDK)
	if(farcasterSDK):
		farcasterSDK.actions.ready()





func show_game_scene():
	main_screen.show()
	# Hide only top-level content scenes, not anything inside NeverDelete
	for child in get_children():
		if child == never_delete:
			continue
		if child.has_method("hide"):
			child.hide()

func transition_to(scene_path: String) -> void:


	# Remove all content scenes except the NeverDelete subtree
	for child in get_children():
		if child == never_delete:
			continue
		child.queue_free()

	var new_scene = load(scene_path)
	if new_scene is PackedScene:
		var inst = new_scene.instantiate()
		add_child(inst)
