extends Control


func _on_game_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_demo/game_demo.tscn")


func _on_sandbox_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/sandbox/sandbox.tscn")
