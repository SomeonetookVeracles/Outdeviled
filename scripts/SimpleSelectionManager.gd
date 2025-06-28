extends Node
class_name SimpleSelectionManager

# Simple selection manager to coordinate character selection
# Ensures only one character is selected at a time

signal character_selected(character: Node)
signal character_deselected(character: Node)
signal selection_cleared()

var current_selection: Node = null

func _ready():
	add_to_group("selection_manager")
	print("Selection manager initialized")

func select_character(character: Node):
	"""Select a character, deselecting any previously selected character"""
	if current_selection == character:
		return  # Already selected
	
	# Deselect current selection first
	if current_selection and is_instance_valid(current_selection):
		if current_selection.has_method("deselect_character"):
			current_selection.deselect_character()
	
	# Select new character
	current_selection = character
	character_selected.emit(character)
	
	print("Selected character: %s" % character.name)

func deselect_character(character: Node):
	"""Deselect a specific character"""
	if current_selection == character:
		current_selection = null
		character_deselected.emit(character)
		selection_cleared.emit()

func deselect_all():
	"""Deselect all characters"""
	if current_selection and is_instance_valid(current_selection):
		if current_selection.has_method("deselect_character"):
			current_selection.deselect_character()
	
	current_selection = null
	selection_cleared.emit()

func get_selected_character() -> Node:
	"""Get the currently selected character"""
	return current_selection

func has_selection() -> bool:
	"""Check if any character is currently selected"""
	return current_selection != null and is_instance_valid(current_selection)

func _input(event):
	"""Handle global input for selection management"""
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if clicking on empty space to deselect
			var mouse_pos = get_mouse_world_position()
			var clicked_character = find_character_at_position(mouse_pos)
			
			if not clicked_character and has_selection():
				# Clicking on empty space - deselect
				deselect_all()
	
	# Global deselect with ESC
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE and has_selection():
			deselect_all()

func find_character_at_position(world_pos: Vector2) -> Node:
	"""Find which character (if any) is at the given world position"""
	var characters = get_tree().get_nodes_in_group("characters")
	
	for character in characters:
		if character.has_method("is_mouse_over_character"):
			if character.is_mouse_over_character(world_pos):
				return character
	
	return null

# Debug and utility functions
func print_selection_info():
	"""Print current selection information"""
	if has_selection():
		print("Current selection: %s" % current_selection.name)
		if current_selection.has_method("get_movement_profile_name"):
			print("Profile: %s" % current_selection.get_movement_profile_name())
	else:
		print("No character selected")

func get_all_characters() -> Array:
	"""Get all characters in the scene"""
	return get_tree().get_nodes_in_group("characters")

func select_next_character():
	"""Cycle to the next character in the scene"""
	var characters = get_all_characters()
	if characters.is_empty():
		return
	
	var current_index = -1
	if current_selection:
		current_index = characters.find(current_selection)
	
	var next_index = (current_index + 1) % characters.size()
	var next_character = characters[next_index]
	
	if next_character.has_method("select_character"):
		next_character.select_character()

func select_previous_character():
	"""Cycle to the previous character in the scene"""
	var characters = get_all_characters()
	if characters.is_empty():
		return
	
	var current_index = characters.size()
	if current_selection:
		current_index = characters.find(current_selection)
	
	var prev_index = (current_index - 1) % characters.size()
	var prev_character = characters[prev_index]
	
	if prev_character.has_method("select_character"):
		prev_character.select_character()

# Advanced selection features
func select_character_by_name(character_name: String) -> bool:
	"""Select a character by its name"""
	var characters = get_all_characters()
	
	for character in characters:
		if character.has_method("get") and "character_name" in character:
			if character.character_name == character_name:
				if character.has_method("select_character"):
					character.select_character()
					return true
		elif character.name == character_name:
			if character.has_method("select_character"):
				character.select_character()
				return true
	
	print("Character not found: %s" % character_name)
	return false

func get_characters_by_profile(profile_name: String) -> Array:
	"""Get all characters with a specific movement profile"""
	var matching_characters = []
	var characters = get_all_characters()
	
	for character in characters:
		if character.has_method("get_movement_profile_name"):
			if character.get_movement_profile_name() == profile_name:
				matching_characters.append(character)
	
	return matching_characters

func select_nearest_character_to_position(world_pos: Vector2) -> bool:
	"""Select the character closest to a given world position"""
	var characters = get_all_characters()
	if characters.is_empty():
		return false
	
	var nearest_character = null
	var nearest_distance = INF
	
	for character in characters:
		var distance = character.global_position.distance_to(world_pos)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_character = character
	
	if nearest_character and nearest_character.has_method("select_character"):
		nearest_character.select_character()
		return true
	
	return false

func get_mouse_world_position() -> Vector2:
	"""Get mouse position in world coordinates"""
	var viewport = get_viewport()
	var camera = viewport.get_camera_2d()
	
	if camera:
		return camera.get_global_mouse_position()
	else:
		# Fallback if no camera
		return viewport.get_mouse_position()

func select_character_at_mouse() -> bool:
	"""Select the character at current mouse position"""
	var mouse_pos = get_mouse_world_position()
	return select_nearest_character_to_position(mouse_pos)

# Keyboard shortcuts for selection
func _unhandled_key_input(event):
	"""Handle keyboard shortcuts for character selection"""
	if event.pressed:
		match event.keycode:
			KEY_TAB:
				# Tab to next character
				select_next_character()
				get_viewport().set_input_as_handled()
			
			KEY_TAB when event.shift_pressed:
				# Shift+Tab to previous character  
				select_previous_character()
				get_viewport().set_input_as_handled()
			
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				# Number keys to select specific characters
				var character_index = event.keycode - KEY_1
				var characters = get_all_characters()
				if character_index < characters.size():
					var character = characters[character_index]
					if character.has_method("select_character"):
						character.select_character()
				get_viewport().set_input_as_handled()
