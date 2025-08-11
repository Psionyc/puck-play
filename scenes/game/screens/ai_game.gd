extends Node

@onready var table := $Game/Table

enum AIDifficulty { EASY, MEDIUM, HARD }
enum Who {UP, DOWN}
@export var difficulty: AIDifficulty = AIDifficulty.EASY

func _ready() -> void:
	# Wait for the browser canvas to finish sizing
	await get_tree().process_frame
	_set_table_position()

	# In Godot 4, use the Window signal (more reliable on Web)
	get_window().size_changed.connect(_set_table_position)

func _set_table_position() -> void:
	# Use the window's visible rect; viewport size may not reflect CSS scaling on Web
	var win_size := get_window().get_visible_rect().size
	# If table uses local coordinates under another Node2D, set global_position:
	table.global_position = win_size * 0.5
	# If it's already at the scene root (no transformed parent), position is fine too:
	# table.position = win_size * 0.5


func update_scoreboard(who: Who ):
	pass
