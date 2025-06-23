extends Control

# Called when the scene enters the scene tree
func _ready():
	# Connect buttons with functions
	$VBoxContainer/ContinueButton.pressed.connect(_on_continue_pressed)
	$VBoxContainer/NewGameButton.pressed.connect(_on_new_game_pressed)
	$VBoxContainer/OptionsButton.pressed.connect(_on_options_pressed)
	$VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)

	# Disable Continue if no save exists (placeholder)
	#TODO Make this grey it out instead
	if not FileAccess.file_exists("user://savegame.save"):
		$VBoxContainer/ContinueButton.disabled = true


func _on_continue_pressed():
	# Load game from a save
	print("Continue game")
	# Replace w/ load logic
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")


func _on_new_game_pressed():
	# Start new game 
	#! TODO - Add a confirmation prompt
	print("New game")
	# Replace with game scene 
	get_tree().change_scene_to_file("res://Scenes/Test_scene.tscn")


func _on_options_pressed():
	# Open options menu
	print("Options")
	# Replace with options scene or popup
	get_tree().change_scene_to_file("res://Scenes/OptionsMenu.tscn")


func _on_quit_pressed():
	# Quit game
	print("Quitting...")
	get_tree().quit()
