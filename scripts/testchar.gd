extends CharacterBody2D
# Removed class_name to avoid conflicts - you can still use this script normally

# IMPORTANT: Before using this script, you need to create the MovementProfile and 
# MovementProfileManager scripts separately! See the other artifacts for those scripts.

# HIGHLY OPTIMIZED CHARACTER CONTROLLER WITH MOVEMENT PROFILES, TILE HEIGHT & SELECTION
# - Single-pass cache building: Calls pathfinder functions ONLY ONCE during cache build
# - No repeated A* calls: All data cached (sprites + height) to eliminate lag
# - Smart caching: Fetches all pathfinder data in one operation to avoid 500+ debug messages
# - Height integration: Uses tile height data for perfect positioning
# - Movement profiles: Different character types with unique movement rules and raycasting
# - Selection system: Click to select, shows valid movement tiles with green circles
# - Progress indicators: Shows cache building progress for large maps
# 
# CONTROLS:
# - Click character: Select and show valid movement tiles
# - Click green circle: Move to that tile
# - Press K: Relocate character (instant after cache built)
# - Press P: Cycle through movement profiles
# - Press M: Show movement profile information
# - Press V: Show valid movement positions (console)
# - Press R: Refresh cache (rebuilds from pathfinder)
# - Press C: Show cache statistics
# - Press ESC: Deselect character

# Character properties
@export var move_speed: float = 200.0
@export var auto_spawn: bool = true
@export var spawn_layer: int = 0
@export var smooth_movement: bool = true
@export var rotation_speed: float = 10.0

# Position alignment
@export var position_offset: Vector2 = Vector2(0.0, -16.0)  # Base offset for sprite alignment
@export var layer_height_offset: float = 20.0  # Height separation between layers
@export var use_tile_height: bool = true  # Use tile height data for vertical positioning
@export var tile_height_multiplier: float = 1.0  # Multiplier for tile height effect

# Input controls
@export var relocation_key: Key = KEY_K  # Key to press for random relocation
@export var require_sprites: bool = true  # Only spawn on cells with sprites
@export var auto_build_cache: bool = true  # Automatically build sprite cache on first use
@export var show_progress: bool = true  # Show progress during cache building

# Movement profile settings
@export var character_name: String = "Character"  # Unique identifier for profile assignment
@export var default_profile: String = "Infantry"  # Fallback profile if none assigned
@export var use_movement_profiles: bool = true  # Enable/disable profile system

# Selection and UI settings
@export var selectable: bool = true  # Can this character be selected?
@export var highlight_color: Color = Color.YELLOW  # Color when selected
@export var valid_move_color: Color = Color.GREEN  # Color for valid movement tiles
@export var move_indicator_size: float = 12.0  # Size of movement indicators

# Pathfinding variables
var current_path: Array[Vector3i] = []
var current_world_path: Array[Vector2] = []
var path_index: int = 0
var target_position: Vector2
var grid_position: Vector3i
var is_moving: bool = false

# Sprite caching for performance
var sprite_cells_cache: Array[Vector3i] = []
var cache_built: bool = false
var accessible_cells_cache: Array[Vector3i] = []
var height_data_cache: Dictionary = {}  # [Vector3i] -> float (height offset)
var pathfinder_data_fetched: bool = false

# References (Node type to avoid class conflicts)
var pathfinder: Node
var movement_profile_manager: Node
var current_movement_profile: Resource

# Selection system
var is_selected: bool = false
var valid_movement_tiles: Array[Vector3i] = []
var selection_manager: Node  # Global selection manager

# Signals
signal movement_finished
signal reached_target
signal path_blocked
signal layer_changed(old_layer: int, new_layer: int)
signal character_relocated(new_position: Vector3i)
signal character_selected(character: Node)
signal character_deselected(character: Node)
signal tile_clicked(tile_position: Vector3i, character: Node)

func _ready():
	# Add to characters group for selection management
	add_to_group("characters")
	
	# Find the pathfinder in the scene
	find_pathfinder()
	
	# Find movement profile manager
	find_movement_profile_manager()
	
	# Find or create selection manager
	find_selection_manager()
	
	# Build cache early if auto_build_cache is enabled
	if auto_build_cache and pathfinder:
		# Defer cache building to avoid blocking initialization
		build_cache_deferred.call_deferred()
	
	# Set up initial position
	if auto_spawn:
		spawn_at_random_position()
	else:
		# Snap to nearest grid position
		snap_to_grid()

func build_cache_deferred():
	"""Build cache on next frame to avoid blocking initialization"""
	await get_tree().process_frame
	if pathfinder and not cache_built:
		build_sprite_cache()

func find_pathfinder():
	# Try to find pathfinder by group first
	var nodes_in_group = get_tree().get_nodes_in_group("pathfinder")
	for node in nodes_in_group:
		if node.has_method("find_path") and node.has_method("is_cell_walkable"):
			pathfinder = node
			break
	
	if not pathfinder:
		# Search through scene tree for node with pathfinding methods
		var current_node = get_tree().current_scene
		pathfinder = find_pathfinder_recursive(current_node)
	
	if pathfinder:
		# Connect to pathfinder signals if they exist
		if pathfinder.has_signal("path_calculated") and not pathfinder.path_calculated.is_connected(_on_path_calculated):
			pathfinder.path_calculated.connect(_on_path_calculated)
		print("Character connected to pathfinder: ", pathfinder.name)
	else:
		push_error("Could not find pathfinder! Make sure it has the required methods and is in the scene.")

func find_movement_profile_manager():
	# Try to find MovementProfileManager in the scene
	movement_profile_manager = get_tree().get_first_node_in_group("movement_profiles")
	
	if not movement_profile_manager:
		# Search through scene tree for MovementProfileManager
		var current_node = get_tree().current_scene
		movement_profile_manager = find_movement_manager_recursive(current_node)
	
	if movement_profile_manager:
		# Load movement profile for this character
		load_movement_profile()
		print("Character connected to movement profile manager: ", movement_profile_manager.name)
	else:
		push_warning("Could not find MovementProfileManager! Movement profiles disabled.")
		use_movement_profiles = false

func find_selection_manager():
	# Try to find a global selection manager
	selection_manager = get_tree().get_first_node_in_group("selection_manager")
	
	if not selection_manager:
		# Create a simple selection manager if none exists
		create_simple_selection_manager()

func create_simple_selection_manager():
	"""Create a basic selection manager for this character"""
	var manager = Node.new()
	manager.name = "SelectionManager"
	get_tree().current_scene.add_child(manager)
	manager.add_to_group("selection_manager")
	
	# Add basic selection tracking
	manager.set_script(preload("res://scripts/SimpleSelectionManager.gd") if ResourceLoader.exists("res://scripts/SimpleSelectionManager.gd") else null)
	
	selection_manager = manager

func find_movement_manager_recursive(node: Node) -> Node:
	# Check if node has required movement profile methods
	if node.has_method("get_character_profile") and node.has_method("assign_profile_to_character") and node.has_method("get_all_profile_names"):
		return node
	
	for child in node.get_children():
		var result = find_movement_manager_recursive(child)
		if result:
			return result
	
	return null

func load_movement_profile():
	"""Load movement profile for this character"""
	if not movement_profile_manager or not use_movement_profiles:
		return
	
	current_movement_profile = movement_profile_manager.get_character_profile(character_name)
	if not current_movement_profile:
		# Assign default profile
		movement_profile_manager.assign_profile_to_character(character_name, default_profile)
		current_movement_profile = movement_profile_manager.get_character_profile(character_name)
	
	if current_movement_profile:
		print("Loaded movement profile '%s' for character '%s'" % [current_movement_profile.profile_name, character_name])
	else:
		push_warning("Failed to load movement profile for character '%s'" % character_name)

func find_pathfinder_recursive(node: Node) -> Node:
	# Check if node has the required pathfinding methods (not if it's a character!)
	if node.has_method("find_path") and node.has_method("is_cell_walkable") and node.has_method("get_accessible_cells"):
		return node
	
	for child in node.get_children():
		var result = find_pathfinder_recursive(child)
		if result:
			return result
	
	return null

func _unhandled_input(event):
	"""Handle mouse input for character selection"""
	if not selectable:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if mouse is over this character
			var mouse_pos = get_global_mouse_position()
			if is_mouse_over_character(mouse_pos):
				select_character()
				get_viewport().set_input_as_handled()
			elif is_selected:
				# Check if clicking on a valid movement tile
				var clicked_tile = world_to_grid_position(mouse_pos)
				if clicked_tile in valid_movement_tiles:
					tile_clicked.emit(clicked_tile, self)
					move_to_grid_position(clicked_tile)
					get_viewport().set_input_as_handled()

func is_mouse_over_character(mouse_pos: Vector2) -> bool:
	"""Check if mouse position is over this character"""
	var character_rect = Rect2(global_position - Vector2(16, 16), Vector2(32, 32))
	return character_rect.has_point(mouse_pos)

func world_to_grid_position(world_pos: Vector2) -> Vector3i:
	"""Convert world position to grid position"""
	if not pathfinder or not pathfinder.has_method("world_to_grid"):
		return Vector3i.ZERO
	
	var grid_2d = pathfinder.world_to_grid(world_pos)
	return Vector3i(grid_2d.x, grid_2d.y, grid_position.z)  # Use current character layer

# Selection system functions
func select_character():
	"""Select this character and show valid movement options"""
	if not selectable:
		return
	
	# Deselect other characters first
	if selection_manager and selection_manager.has_method("deselect_all"):
		selection_manager.deselect_all()
	else:
		# Fallback: deselect all characters manually
		var all_characters = get_tree().get_nodes_in_group("characters")
		for character in all_characters:
			if character != self and character.has_method("deselect_character"):
				character.deselect_character()
	
	# Select this character
	is_selected = true
	update_valid_movement_tiles()
	character_selected.emit(self)
	
	print("Selected character: %s (%s profile)" % [character_name, get_movement_profile_name()])
	
	# Force redraw to show selection
	queue_redraw()

func deselect_character():
	"""Deselect this character and hide movement options"""
	if not is_selected:
		return
	
	is_selected = false
	valid_movement_tiles.clear()
	character_deselected.emit(self)
	
	# Force redraw to hide selection
	queue_redraw()

func update_valid_movement_tiles():
	"""Update the list of valid movement tiles for visualization"""
	valid_movement_tiles.clear()
	
	if not is_selected or is_moving:
		return
	
	# Get valid movement positions from movement profile system
	valid_movement_tiles = get_valid_movement_positions()
	
	print("Valid movement positions: %d tiles" % valid_movement_tiles.size())
	
	# Force redraw to show movement indicators
	queue_redraw()

func is_character_selected() -> bool:
	"""Check if this character is currently selected"""
	return is_selected

func spawn_at_random_position():
	if not pathfinder or not pathfinder.has_method("get_accessible_cells"):
		return
	
	# Stop any current movement
	stop_movement()
	
	# Build cache if not already built
	if not cache_built:
		build_sprite_cache()
	
	# Use cached accessible cells
	if accessible_cells_cache.is_empty():
		push_warning("No accessible cells found for spawning")
		return
	
	# Filter cells by spawn layer if specified
	var valid_spawn_cells: Array[Vector3i] = []
	var source_cells = sprite_cells_cache if require_sprites else accessible_cells_cache
	
	for cell in source_cells:
		if cell.z == spawn_layer:
			valid_spawn_cells.append(cell)
	
	if valid_spawn_cells.is_empty():
		push_warning("No accessible cells found on layer %d, using any layer" % spawn_layer)
		valid_spawn_cells = source_cells
	
	if valid_spawn_cells.is_empty():
		push_warning("No valid spawn cells found!")
		return
	
	# Pick random valid cell
	var random_cell = valid_spawn_cells[randi() % valid_spawn_cells.size()]
	set_grid_position(random_cell)
	
	# Emit relocation signal
	character_relocated.emit(random_cell)

func snap_to_grid():
	if not pathfinder or not pathfinder.has_method("world_to_grid"):
		return
		
	var world_pos = position
	var grid_2d = pathfinder.world_to_grid(world_pos)
	var current_layer = grid_position.z if grid_position != Vector3i.ZERO else spawn_layer
	
	# Find nearest walkable cell on current layer
	var target_3d = Vector3i(grid_2d.x, grid_2d.y, current_layer)
	if pathfinder.has_method("is_cell_walkable") and pathfinder.is_cell_walkable(target_3d):
		set_grid_position(target_3d)
	else:
		# Find nearest walkable cell
		find_nearest_walkable_cell(target_3d)

func find_nearest_walkable_cell(around_pos: Vector3i):
	if not pathfinder or not pathfinder.has_method("is_cell_walkable"):
		return
	
	# Build cache if not already built
	if not cache_built:
		build_sprite_cache()
		
	var search_radius = 1
	var max_radius = 5
	
	# First pass: look for cells with sprites (if required)
	if require_sprites:
		while search_radius <= max_radius:
			for x in range(-search_radius, search_radius + 1):
				for y in range(-search_radius, search_radius + 1):
					var test_pos = Vector3i(around_pos.x + x, around_pos.y + y, around_pos.z)
					if pathfinder.is_cell_walkable(test_pos) and is_cell_in_sprite_cache(test_pos):
						set_grid_position(test_pos)
						return
			search_radius += 1
	
	# Second pass: any walkable cell (fallback or if sprites not required)
	search_radius = 1
	while search_radius <= max_radius:
		for x in range(-search_radius, search_radius + 1):
			for y in range(-search_radius, search_radius + 1):
				var test_pos = Vector3i(around_pos.x + x, around_pos.y + y, around_pos.z)
				if pathfinder.is_cell_walkable(test_pos):
					set_grid_position(test_pos)
					if require_sprites:
						push_warning("No sprite found at nearest walkable cell: " + str(test_pos))
					return
		search_radius += 1
	
	push_warning("Could not find walkable cell near position: " + str(around_pos))

func set_grid_position(new_grid_pos: Vector3i):
	if not pathfinder or not pathfinder.has_method("grid_to_world"):
		return
		
	var old_layer = grid_position.z
	grid_position = new_grid_pos
	
	# Convert to world position using pathfinder's isometric conversion
	var world_pos = pathfinder.grid_to_world(Vector2i(grid_position.x, grid_position.y))
	
	# Apply base position offset for sprite alignment
	world_pos += position_offset
	
	# Apply layer offset (visual depth)
	world_pos.y -= grid_position.z * layer_height_offset
	
	# Apply tile height offset if enabled
	if use_tile_height:
		var tile_height_offset = get_tile_height_offset(grid_position)
		world_pos.y += tile_height_offset * tile_height_multiplier
	
	position = world_pos
	
	if old_layer != grid_position.z:
		layer_changed.emit(old_layer, grid_position.z)

func move_to_grid_position(target_grid_pos: Vector3i):
	if not pathfinder:
		push_error("Pathfinder not found!")
		return
	
	# Validate movement using profile if enabled
	if use_movement_profiles and current_movement_profile:
		if not is_valid_movement_by_profile(grid_position, target_grid_pos):
			print("Movement blocked by profile restrictions")
			path_blocked.emit()
			return
	
	# Check if target is walkable
	if not pathfinder.has_method("is_cell_walkable") or not pathfinder.is_cell_walkable(target_grid_pos):
		path_blocked.emit()
		return
	
	# Find path using pathfinder
	if not pathfinder.has_method("find_path"):
		push_error("Pathfinder missing find_path method!")
		return
		
	var path = pathfinder.find_path(grid_position, target_grid_pos)
	
	if path.is_empty():
		path_blocked.emit()
		return
	
	# Validate path against movement profile
	if use_movement_profiles and current_movement_profile:
		path = validate_path_with_profile(path)
		if path.is_empty():
			print("Path blocked by movement profile validation")
			path_blocked.emit()
			return
	
	# Clear valid movement tiles while moving
	valid_movement_tiles.clear()
	queue_redraw()
	
	# Convert grid path to world path
	current_path = path
	current_world_path.clear()
	
	for grid_pos in path:
		var world_pos = pathfinder.grid_to_world(Vector2i(grid_pos.x, grid_pos.y))
		# Apply position offset
		world_pos += position_offset
		# Apply layer offset
		world_pos.y -= grid_pos.z * layer_height_offset
		
		# Apply tile height offset if enabled
		if use_tile_height:
			var tile_height_offset = get_tile_height_offset(grid_pos)
			world_pos.y += tile_height_offset * tile_height_multiplier
		
		current_world_path.append(world_pos)
	
	# Skip first point if it's our current position
	if current_world_path.size() > 1 and current_world_path[0].distance_to(position) < 10.0:
		current_path.remove_at(0)
		current_world_path.remove_at(0)
	
	if current_world_path.size() > 0:
		path_index = 0
		target_position = current_world_path[0]
		is_moving = true

func move_to_world_position(world_pos: Vector2, target_layer: int = -1):
	if not pathfinder or not pathfinder.has_method("world_to_grid"):
		return
		
	var grid_2d = pathfinder.world_to_grid(world_pos)
	var layer = target_layer if target_layer >= 0 else grid_position.z
	var target_3d = Vector3i(grid_2d.x, grid_2d.y, layer)
	move_to_grid_position(target_3d)

func _on_path_calculated(path: Array):
	# This gets called when pathfinder calculates any path
	# We handle our own path in move_to_grid_position
	pass

func _input(event):
	# Press the configured key to randomly relocate the character
	if event is InputEventKey and event.pressed:
		if event.keycode == relocation_key:
			var sprite_info = get_sprite_count_info()
			print("=== CHARACTER RELOCATION ===")
			print("Cache status: ", "READY" if is_cache_ready() else "BUILDING...")
			print("Total accessible cells: ", sprite_info.total_accessible)
			print("Cells with sprites: ", sprite_info.total_with_sprites)
			print("Height data cached: ", sprite_info.height_data_cached)
			print("Movement profile: ", get_movement_profile_name())
			if current_movement_profile and current_movement_profile.has_method("get"):
				print("Movement range: %d-%d" % [current_movement_profile.min_movement_range, current_movement_profile.max_movement_range])
				if "movement_pattern" in current_movement_profile:
					print("Pattern: ", get_movement_pattern_name())
				print("Raycasting: ", "ON" if current_movement_profile.use_raycasting else "OFF")
			print("Sprite requirement: ", "ON" if require_sprites else "OFF")
			print("Tile height adjustment: ", "ON" if use_tile_height else "OFF")
			
			spawn_at_random_position()
			print("Character relocated to: ", grid_position)
			print("Has sprite: ", is_cell_in_sprite_cache(grid_position))
			if use_tile_height:
				var height_mult = get_tile_height_multiplier(grid_position)
				var height_offset = get_tile_height_offset(grid_position)
				print("Tile height multiplier: ", height_mult, " -> cached offset: ", height_offset)
		
		# Press R to refresh sprite cache
		elif event.keycode == KEY_R:
			print("Refreshing sprite cache (will rebuild from pathfinder)...")
			refresh_sprite_cache()
			print("Cache refreshed!")
		
		# Press C to show cache stats
		elif event.keycode == KEY_C:
			var stats = get_cache_stats()
			print("=== CACHE STATISTICS ===")
			for key in stats.keys():
				print(key, ": ", stats[key])
		
		# Press P to cycle through movement profiles
		elif event.keycode == KEY_P:
			cycle_movement_profile()
		
		# Press M to show movement options
		elif event.keycode == KEY_M:
			show_movement_options()
		
		# Press V to show valid movement positions
		elif event.keycode == KEY_V:
			show_valid_movements()
		
		# Press ESC to deselect character
		elif event.keycode == KEY_ESCAPE:
			if is_selected:
				deselect_character()

func cycle_movement_profile():
	"""Cycle through available movement profiles"""
	if not movement_profile_manager:
		print("No movement profile manager available!")
		return
	
	var all_profiles = movement_profile_manager.get_all_profile_names()
	if all_profiles.is_empty():
		print("No movement profiles available!")
		return
	
	var current_name = get_movement_profile_name()
	var current_index = all_profiles.find(current_name)
	var next_index = (current_index + 1) % all_profiles.size()
	var next_profile = all_profiles[next_index]
	
	set_movement_profile(next_profile)
	print("Switched to movement profile: %s" % next_profile)

func show_movement_options():
	"""Display current movement profile information"""
	print("=== MOVEMENT PROFILE INFO ===")
	print("Character: %s" % character_name)
	print("Current profile: %s" % get_movement_profile_name())
	
	if current_movement_profile:
		var description = current_movement_profile.description if "description" in current_movement_profile else "No description"
		var min_range = current_movement_profile.min_movement_range if "min_movement_range" in current_movement_profile else 1
		var max_range = current_movement_profile.max_movement_range if "max_movement_range" in current_movement_profile else 99
		var can_diagonal = current_movement_profile.can_move_diagonally if "can_move_diagonally" in current_movement_profile else true
		var requires_los = current_movement_profile.requires_line_of_sight if "requires_line_of_sight" in current_movement_profile else false
		var use_raycast = current_movement_profile.use_raycasting if "use_raycasting" in current_movement_profile else false
		var can_jump = current_movement_profile.can_jump_over_obstacles if "can_jump_over_obstacles" in current_movement_profile else false
		var can_move_through = current_movement_profile.can_move_through_walls if "can_move_through_walls" in current_movement_profile else false
		
		print("Description: %s" % description)
		print("Range: %d-%d tiles" % [min_range, max_range])
		print("Pattern: %s" % get_movement_pattern_name())
		print("Diagonal movement: %s" % ("YES" if can_diagonal else "NO"))
		print("Requires line of sight: %s" % ("YES" if requires_los else "NO"))
		print("Uses raycasting: %s" % ("YES" if use_raycast else "NO"))
		print("Can jump obstacles: %s" % ("YES" if can_jump else "NO"))
		print("Can move through walls: %s" % ("YES" if can_move_through else "NO"))
	
	if movement_profile_manager:
		var all_profiles = movement_profile_manager.get_all_profile_names()
		print("Available profiles: %s" % ", ".join(all_profiles))

func show_valid_movements():
	"""Display valid movement positions for current character"""
	print("=== VALID MOVEMENTS ===")
	var valid_positions = get_valid_movement_positions()
	print("Valid movement positions from %s: %d total" % [grid_position, valid_positions.size()])
	
	# Group by layer for easier reading
	var by_layer = {}
	for pos in valid_positions:
		if not pos.z in by_layer:
			by_layer[pos.z] = []
		by_layer[pos.z].append(Vector2i(pos.x, pos.y))
	
	for layer in by_layer.keys():
		print("Layer %d: %d positions" % [layer, by_layer[layer].size()])
		if by_layer[layer].size() <= 10:  # Only show if reasonable number
			print("  Positions: %s" % by_layer[layer])

func _physics_process(delta):
	if not is_moving or current_world_path.is_empty():
		return
	
	if smooth_movement:
		_smooth_movement(delta)
	else:
		_instant_movement()

func _smooth_movement(delta):
	var direction = (target_position - position).normalized()
	var distance_to_target = position.distance_to(target_position)
	
	if distance_to_target < 5.0:
		# Snap to exact position
		position = target_position
		
		# Update grid position if we're at a grid point
		if path_index < current_path.size():
			var old_layer = grid_position.z
			grid_position = current_path[path_index]
			if old_layer != grid_position.z:
				layer_changed.emit(old_layer, grid_position.z)
		
		# Move to next point
		path_index += 1
		
		if path_index >= current_world_path.size():
			# Reached end of path
			_finish_movement()
		else:
			target_position = current_world_path[path_index]
	else:
		# Continue moving
		velocity = direction * move_speed
		move_and_slide()
		
		# Optional: Rotate character to face movement direction
		if direction.length() > 0.1:
			var target_rotation = direction.angle()
			rotation = lerp_angle(rotation, target_rotation, rotation_speed * delta)

func _instant_movement():
	# Instantly move to each point in path
	if path_index < current_world_path.size():
		position = current_world_path[path_index]
		
		if path_index < current_path.size():
			var old_layer = grid_position.z
			grid_position = current_path[path_index]
			if old_layer != grid_position.z:
				layer_changed.emit(old_layer, grid_position.z)
		
		path_index += 1
		
		if path_index >= current_world_path.size():
			_finish_movement()

func _finish_movement():
	is_moving = false
	current_path.clear()
	current_world_path.clear()
	velocity = Vector2.ZERO
	
	# Update valid movement tiles if character is still selected
	if is_selected:
		update_valid_movement_tiles()
	
	movement_finished.emit()
	reached_target.emit()

# Utility functions
func get_grid_position() -> Vector3i:
	return grid_position

func get_current_layer() -> int:
	return grid_position.z

func is_character_moving() -> bool:
	return is_moving

func stop_movement():
	is_moving = false
	current_path.clear()
	current_world_path.clear()
	velocity = Vector2.ZERO

func can_move_to(target_grid_pos: Vector3i) -> bool:
	if not pathfinder or not pathfinder.has_method("is_cell_walkable"):
		return false
	return pathfinder.is_cell_walkable(target_grid_pos)

func get_cell_data_at_position(pos: Vector3i):
	if not pathfinder or not pathfinder.has_method("get_cell_data"):
		return null
	return pathfinder.get_cell_data(pos)

func get_accessible_cells() -> Array[Vector3i]:
	if not cache_built:
		build_sprite_cache()
	return accessible_cells_cache

# Sprite detection functions
func build_sprite_cache():
	"""Build cache of cells with sprites - only called once for performance"""
	if not pathfinder:
		return
	
	print("Building sprite cache (one-time operation)...")
	var start_time = Time.get_time_dict_from_system()
	
	# STEP 1: Get accessible cells from pathfinder (ONLY ONCE)
	if not pathfinder_data_fetched:
		if show_progress:
			print("Fetching data from pathfinder...")
		accessible_cells_cache = pathfinder.get_accessible_cells()
		pathfinder_data_fetched = true
		if show_progress:
			print("Fetched %d accessible cells from pathfinder" % accessible_cells_cache.size())
	
	sprite_cells_cache.clear()
	height_data_cache.clear()
	
	# STEP 2: Check each accessible cell for sprites and cache height data
	var cells_checked = 0
	var sprites_found = 0
	
	for cell in accessible_cells_cache:
		cells_checked += 1
		
		# Check for sprite and cache height data in one pass
		var has_sprite = check_sprite_and_cache_height(cell)
		if has_sprite:
			sprite_cells_cache.append(cell)
			sprites_found += 1
		
		# Progress indicator for large maps
		if show_progress and cells_checked % 50 == 0:
			print("Processed %d/%d cells..." % [cells_checked, accessible_cells_cache.size()])
	
	cache_built = true
	var end_time = Time.get_time_dict_from_system()
	var duration = (end_time.hour * 3600 + end_time.minute * 60 + end_time.second) - (start_time.hour * 3600 + start_time.minute * 60 + start_time.second)
	
	if show_progress:
		print("=== CACHE BUILD COMPLETE ===")
		print("Accessible cells: %d" % accessible_cells_cache.size())
		print("Cells with sprites: %d" % sprite_cells_cache.size())
		print("Height data cached: %d entries" % height_data_cache.size())
		print("Build time: %d seconds" % duration)

func check_sprite_and_cache_height(cell_pos: Vector3i) -> bool:
	"""Check for sprite AND cache height data in single operation"""
	if not pathfinder:
		return false
	
	# Check if pathfinder has the required methods and properties
	if not pathfinder.has_method("grid_to_world") or not pathfinder.has_method("has_sprite_at_position") or not pathfinder.has_method("get_tile_height_at_position"):
		height_data_cache[cell_pos] = 1.0  # Default height offset
		return true  # Default to true if we can't check
	
	# Get layer node for this cell's layer
	if not ("layer_nodes" in pathfinder):
		height_data_cache[cell_pos] = 1.0  # Default height offset
		return true  # Default to true if no layer info
	
	var layer_nodes = pathfinder.layer_nodes
	if cell_pos.z >= layer_nodes.size() or not layer_nodes[cell_pos.z]:
		height_data_cache[cell_pos] = 0.0  # No layer = no height
		return false  # No layer node for this layer
	
	var layer_node = layer_nodes[cell_pos.z]
	var world_pos = pathfinder.grid_to_world(Vector2i(cell_pos.x, cell_pos.y))
	
	# GET BOTH sprite and height data in one call to avoid repeated pathfinder access
	var has_sprite = pathfinder.has_sprite_at_position(layer_node, world_pos)
	var height_multiplier = pathfinder.get_tile_height_at_position(layer_node, world_pos)
	
	# Cache height offset using same logic as pathfinder debug system
	var height_offset = 1.0  # Default offset for 0 height
	if height_multiplier >= 1.0:
		height_offset = 10.0
	elif height_multiplier >= 0.5:
		height_offset = 5.0
	elif height_multiplier >= 0.25:
		height_offset = 2.5
	else:
		height_offset = 1.0  # For 0 or very small values
	
	height_data_cache[cell_pos] = height_offset
	
	return has_sprite

func is_cell_in_sprite_cache(cell_pos: Vector3i) -> bool:
	"""Fast lookup in sprite cache"""
	return cell_pos in sprite_cells_cache

func has_sprite_at_cell(cell_pos: Vector3i) -> bool:
	"""Check if there's a sprite at the given grid cell position (uses cache)"""
	if not cache_built:
		build_sprite_cache()
	
	return is_cell_in_sprite_cache(cell_pos)

func refresh_sprite_cache():
	"""Force rebuild the sprite cache"""
	cache_built = false
	pathfinder_data_fetched = false
	sprite_cells_cache.clear()
	accessible_cells_cache.clear()
	height_data_cache.clear()
	print("Cache cleared, rebuilding...")
	build_sprite_cache()

func get_cells_with_sprites() -> Array[Vector3i]:
	"""Get all accessible cells that have sprites (from cache)"""
	if not cache_built:
		build_sprite_cache()
	return sprite_cells_cache

# Tile height functions
func get_tile_height_offset(cell_pos: Vector3i) -> float:
	"""Get height offset for a specific tile position (uses cache)"""
	if not cache_built:
		build_sprite_cache()
	
	# Return cached height data
	return height_data_cache.get(cell_pos, 1.0)  # Default to 1.0 if not found

func get_current_tile_height() -> float:
	"""Get height offset for current character position"""
	return get_tile_height_offset(grid_position)

func get_tile_height_multiplier(cell_pos: Vector3i) -> float:
	"""Get raw tile height multiplier from cached data"""
	if not cache_built:
		build_sprite_cache()
	
	# Convert cached offset back to multiplier for display purposes
	var offset = height_data_cache.get(cell_pos, 1.0)
	if offset >= 10.0:
		return 1.0
	elif offset >= 5.0:
		return 0.75
	elif offset >= 2.5:
		return 0.375
	else:
		return 0.0

# Movement helper functions
func move_randomly():
	if not pathfinder:
		return
	
	var accessible_cells = get_accessible_cells()
	if accessible_cells.is_empty():
		return
	
	var random_cell = accessible_cells[randi() % accessible_cells.size()]
	move_to_grid_position(random_cell)

func move_to_layer(target_layer: int):
	# Move to same X,Y position but different layer
	var target_pos = Vector3i(grid_position.x, grid_position.y, target_layer)
	if can_move_to(target_pos):
		move_to_grid_position(target_pos)
	else:
		# Find nearest walkable cell on target layer
		find_nearest_walkable_cell(target_pos)

func move_towards_position(world_pos: Vector2, target_layer: int = -1):
	# Convert world position to grid and move towards it
	if not pathfinder or not pathfinder.has_method("world_to_grid"):
		return
		
	var grid_2d = pathfinder.world_to_grid(world_pos)
	var layer = target_layer if target_layer >= 0 else grid_position.z
	var target_3d = Vector3i(grid_2d.x, grid_2d.y, layer)
	move_to_grid_position(target_3d)

# Alignment helper functions
func set_position_offset(new_offset: Vector2):
	"""Update position offset and refresh character position"""
	position_offset = new_offset
	if grid_position != Vector3i.ZERO:
		set_grid_position(grid_position)  # Refresh position with new offset

func set_layer_height_offset(new_offset: float):
	"""Update layer height offset and refresh character position"""
	layer_height_offset = new_offset
	if grid_position != Vector3i.ZERO:
		set_grid_position(grid_position)  # Refresh position with new offset

func set_tile_height_enabled(enabled: bool):
	"""Enable/disable tile height adjustment and refresh position"""
	use_tile_height = enabled
	if grid_position != Vector3i.ZERO:
		set_grid_position(grid_position)  # Refresh position

func set_tile_height_multiplier(multiplier: float):
	"""Set tile height effect multiplier and refresh position"""
	tile_height_multiplier = multiplier
	if grid_position != Vector3i.ZERO:
		set_grid_position(grid_position)  # Refresh position

func relocate_randomly():
	"""Programmatically relocate character to random position"""
	spawn_at_random_position()

func relocate_to_layer(target_layer: int):
	"""Relocate character to random position on specific layer"""
	var old_spawn_layer = spawn_layer
	spawn_layer = target_layer
	spawn_at_random_position()
	spawn_layer = old_spawn_layer  # Restore original spawn layer

func relocate_to_sprite_only():
	"""Force relocate to only positions with sprites (ignores require_sprites setting)"""
	var old_require_sprites = require_sprites
	require_sprites = true
	spawn_at_random_position()
	require_sprites = old_require_sprites

func get_sprite_count_info() -> Dictionary:
	"""Get information about available sprite positions (from cache)"""
	if not cache_built:
		build_sprite_cache()
	
	var layer_counts = {}
	
	for cell in sprite_cells_cache:
		if not cell.z in layer_counts:
			layer_counts[cell.z] = 0
		layer_counts[cell.z] += 1
	
	return {
		"total_accessible": accessible_cells_cache.size(),
		"total_with_sprites": sprite_cells_cache.size(),
		"layers_with_sprites": layer_counts.keys(),
		"cells_per_layer": layer_counts,
		"cache_built": cache_built,
		"height_data_cached": height_data_cache.size(),
		"pathfinder_data_fetched": pathfinder_data_fetched
	}

# Cache management functions
func is_cache_ready() -> bool:
	"""Check if cache is built and ready"""
	return cache_built and pathfinder_data_fetched

func get_cache_stats() -> Dictionary:
	"""Get detailed cache statistics"""
	return {
		"cache_built": cache_built,
		"pathfinder_data_fetched": pathfinder_data_fetched,
		"accessible_cells": accessible_cells_cache.size(),
		"sprite_cells": sprite_cells_cache.size(),
		"height_data_entries": height_data_cache.size()
	}

func force_cache_build():
	"""Force immediate cache building (blocks until complete)"""
	if not is_cache_ready():
		print("Force building cache...")
		build_sprite_cache()
	else:
		print("Cache already built!")

# Movement Profile System Functions

# Movement validation functions
func is_valid_movement_by_profile(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	"""Validate movement against current movement profile"""
	if not current_movement_profile or not use_movement_profiles:
		return true  # No restrictions if profiles disabled
	
	# Check layer restrictions
	if current_movement_profile.has_method("can_move_to_layer"):
		if not current_movement_profile.can_move_to_layer(to_pos.z):
			print("Movement blocked: Layer %d not allowed by profile" % to_pos.z)
			return false
	elif "layer_restrictions" in current_movement_profile:
		var layer_restrictions = current_movement_profile.layer_restrictions
		if not layer_restrictions.is_empty() and not (to_pos.z in layer_restrictions):
			print("Movement blocked: Layer %d not allowed by profile" % to_pos.z)
			return false
	
	# Calculate movement distance
	var distance_2d = Vector2i(to_pos.x - from_pos.x, to_pos.y - from_pos.y).length()
	var distance_3d = from_pos.distance_to(Vector3(to_pos))
	
	# Check movement range
	var min_range = current_movement_profile.min_movement_range if "min_movement_range" in current_movement_profile else 1
	var max_range = current_movement_profile.max_movement_range if "max_movement_range" in current_movement_profile else 99
	
	if distance_2d < min_range or distance_2d > max_range:
		print("Movement blocked: Distance %.1f outside allowed range %d-%d" % [distance_2d, min_range, max_range])
		return false
	
	# Check movement pattern
	if not is_valid_movement_pattern(from_pos, to_pos):
		print("Movement blocked: Pattern not allowed by profile")
		return false
	
	# Check line of sight if required
	var requires_los = current_movement_profile.requires_line_of_sight if "requires_line_of_sight" in current_movement_profile else false
	if requires_los:
		if not has_line_of_sight(from_pos, to_pos):
			print("Movement blocked: No line of sight")
			return false
	
	# Check raycast obstacles if enabled
	var use_raycast = current_movement_profile.use_raycasting if "use_raycasting" in current_movement_profile else false
	if use_raycast:
		if not raycast_movement_clear(from_pos, to_pos):
			print("Movement blocked: Raycast collision detected")
			return false
	
	return true

func is_valid_movement_pattern(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	"""Check if movement follows the allowed pattern"""
	if not current_movement_profile:
		return true
	
	var direction_2d = Vector2i(to_pos.x - from_pos.x, to_pos.y - from_pos.y)
	var valid_directions = get_valid_movement_directions()
	
	# Get movement pattern as integer (0=FREE, 1=CROSS_ONLY, etc.)
	var movement_pattern = current_movement_profile.movement_pattern if "movement_pattern" in current_movement_profile else 0
	
	match movement_pattern:
		3:  # KNIGHT
			# Knight moves must be exact L-shape
			return direction_2d in valid_directions
		
		4:  # STRAIGHT_LINE
			# Must be in straight line (same x, y, or diagonal)
			return direction_2d.x == 0 or direction_2d.y == 0 or abs(direction_2d.x) == abs(direction_2d.y)
		
		5:  # ADJACENT_ONLY
			# Only adjacent tiles
			return direction_2d.length() <= 1.5  # Allow diagonal (sqrt(2) ≈ 1.414)
		
		6:  # CUSTOM
			# Check if direction matches any allowed custom direction
			for allowed_dir in valid_directions:
				if direction_2d.normalized() == allowed_dir.normalized():
					return true
			return false
		
		_:
			# Free movement or cross/diagonal patterns - check basic direction validity
			var normalized_dir = direction_2d.normalized()
			for allowed_dir in valid_directions:
				if normalized_dir == allowed_dir.normalized() or allowed_dir == Vector2i.ZERO:
					return true
			return false

func get_valid_movement_directions() -> Array[Vector2i]:
	"""Get valid movement directions based on current profile"""
	var directions: Array[Vector2i] = []
	
	if not current_movement_profile:
		return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
				Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	
	# Use profile's method if available, otherwise generate based on pattern
	if current_movement_profile.has_method("get_valid_movement_directions"):
		return current_movement_profile.get_valid_movement_directions()
	
	# Fallback: generate directions based on pattern
	var movement_pattern = current_movement_profile.movement_pattern if "movement_pattern" in current_movement_profile else 0
	var can_diagonal = current_movement_profile.can_move_diagonally if "can_move_diagonally" in current_movement_profile else true
	
	match movement_pattern:
		0:  # FREE
			if can_diagonal:
				directions = [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
				]
			else:
				directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		
		1:  # CROSS_ONLY
			directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		
		2:  # DIAGONAL_ONLY
			directions = [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
		
		3:  # KNIGHT
			directions = [
				Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
				Vector2i(1, 2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(-1, -2)
			]
		
		5:  # ADJACENT_ONLY
			if can_diagonal:
				directions = [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
				]
			else:
				directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		
		6:  # CUSTOM
			if "preferred_movement_directions" in current_movement_profile:
				directions = current_movement_profile.preferred_movement_directions.duplicate()
		
		4:  # STRAIGHT_LINE
			directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			if can_diagonal:
				directions.append_array([Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)])
	
	return directions

func get_movement_pattern_name() -> String:
	"""Get movement pattern name as string"""
	if not current_movement_profile or not ("movement_pattern" in current_movement_profile):
		return "FREE"
	
	var pattern_names = ["FREE", "CROSS_ONLY", "DIAGONAL_ONLY", "KNIGHT", "STRAIGHT_LINE", "ADJACENT_ONLY", "CUSTOM"]
	var pattern_index = current_movement_profile.movement_pattern
	
	if pattern_index >= 0 and pattern_index < pattern_names.size():
		return pattern_names[pattern_index]
	
	return "UNKNOWN"

func has_line_of_sight(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	"""Check if there's a clear line of sight between positions"""
	var requires_los = current_movement_profile.requires_line_of_sight if (current_movement_profile and "requires_line_of_sight" in current_movement_profile) else false
	if not requires_los:
		return true
	
	# Convert to world positions for raycast
	var from_world = pathfinder.grid_to_world(Vector2i(from_pos.x, from_pos.y))
	var to_world = pathfinder.grid_to_world(Vector2i(to_pos.x, to_pos.y))
	
	# Apply layer offsets
	from_world.y -= from_pos.z * layer_height_offset
	to_world.y -= to_pos.z * layer_height_offset
	
	var collision_mask = current_movement_profile.raycast_collision_mask if "raycast_collision_mask" in current_movement_profile else 1
	return raycast_between_points(from_world, to_world, collision_mask)

func raycast_movement_clear(from_pos: Vector3i, to_pos: Vector3i) -> bool:
	"""Check if movement path is clear using raycast"""
	var use_raycast = current_movement_profile.use_raycasting if (current_movement_profile and "use_raycasting" in current_movement_profile) else false
	if not use_raycast:
		return true
	
	# Special cases for abilities
	var can_move_through = current_movement_profile.can_move_through_walls if "can_move_through_walls" in current_movement_profile else false
	if can_move_through:
		return true
	
	# Convert to world positions
	var from_world = pathfinder.grid_to_world(Vector2i(from_pos.x, from_pos.y))
	var to_world = pathfinder.grid_to_world(Vector2i(to_pos.x, to_pos.y))
	
	# Apply layer offsets
	from_world.y -= from_pos.z * layer_height_offset
	to_world.y -= to_pos.z * layer_height_offset
	
	var collision_mask = current_movement_profile.raycast_collision_mask if "raycast_collision_mask" in current_movement_profile else 1
	var allow_through_chars = current_movement_profile.allow_through_characters if "allow_through_characters" in current_movement_profile else false
	
	if allow_through_chars:
		# Modify collision mask to ignore character layer
		collision_mask &= ~2  # Assuming characters are on layer 2
	
	var is_clear = raycast_between_points(from_world, to_world, collision_mask)
	
	# If blocked but can jump over obstacles, check if it's a jumpable obstacle
	var can_jump = current_movement_profile.can_jump_over_obstacles if "can_jump_over_obstacles" in current_movement_profile else false
	if not is_clear and can_jump:
		return true  # Allow movement anyway
	
	return is_clear

func raycast_between_points(from_world: Vector2, to_world: Vector2, collision_mask: int) -> bool:
	"""Perform raycast between two world positions"""
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from_world, to_world)
	query.collision_mask = collision_mask
	query.exclude = [self]  # Don't collide with self
	
	var result = space_state.intersect_ray(query)
	return result.is_empty()  # True if no collision (clear path)

func validate_path_with_profile(path: Array[Vector3i]) -> Array[Vector3i]:
	"""Validate entire path against movement profile, return valid portion"""
	if not current_movement_profile or not use_movement_profiles:
		return path
	
	var validated_path: Array[Vector3i] = []
	
	if path.is_empty():
		return validated_path
	
	validated_path.append(path[0])  # Always include starting position
	
	# Check each step in the path
	for i in range(1, path.size()):
		var from_pos = path[i - 1]
		var to_pos = path[i]
		
		if is_valid_movement_by_profile(from_pos, to_pos):
			validated_path.append(to_pos)
		else:
			# Stop at first invalid movement
			print("Path validation stopped at step %d/%d" % [i, path.size()])
			break
	
	return validated_path

# Movement profile management functions
func set_movement_profile(profile_name: String) -> bool:
	"""Set movement profile for this character"""
	if not movement_profile_manager:
		push_warning("No movement profile manager found!")
		return false
	
	var success = movement_profile_manager.assign_profile_to_character(character_name, profile_name)
	if success:
		load_movement_profile()
	return success

func get_movement_profile_name() -> String:
	"""Get current movement profile name"""
	if current_movement_profile and "profile_name" in current_movement_profile:
		return current_movement_profile.profile_name
	return "None"

func get_movement_range() -> Vector2i:
	"""Get movement range (min, max)"""
	if current_movement_profile:
		var min_range = current_movement_profile.min_movement_range if "min_movement_range" in current_movement_profile else 1
		var max_range = current_movement_profile.max_movement_range if "max_movement_range" in current_movement_profile else 99
		return Vector2i(min_range, max_range)
	return Vector2i(1, 99)  # Default unlimited range

func get_valid_movement_positions() -> Array[Vector3i]:
	"""Get all valid movement positions from current location"""
	if not current_movement_profile or not pathfinder:
		return get_accessible_cells()
	
	var valid_positions: Array[Vector3i] = []
	var accessible_cells = get_accessible_cells()
	
	for cell in accessible_cells:
		if is_valid_movement_by_profile(grid_position, cell):
			valid_positions.append(cell)
	
	return valid_positions

# Debug function
func _draw():
	if Engine.is_editor_hint():
		return
	
	# Draw selection highlight
	if is_selected:
		# Draw highlight circle around character
		draw_circle(Vector2.ZERO, 20, highlight_color, false, 3.0)
		
		# Draw valid movement tiles
		if pathfinder and pathfinder.has_method("grid_to_world"):
			for tile_pos in valid_movement_tiles:
				var tile_world_pos = pathfinder.grid_to_world(Vector2i(tile_pos.x, tile_pos.y))
				
				# Apply position offset
				tile_world_pos += position_offset
				
				# Apply layer offset
				tile_world_pos.y -= tile_pos.z * layer_height_offset
				
				# Apply tile height offset if enabled
				if use_tile_height:
					var tile_height_offset = get_tile_height_offset(tile_pos)
					tile_world_pos.y += tile_height_offset * tile_height_multiplier
				
				# Convert to local coordinates for drawing
				var local_tile_pos = to_local(tile_world_pos)
				
				# Draw green circle for valid movement
				draw_circle(local_tile_pos, move_indicator_size, valid_move_color, false, 2.0)
				
				# Draw small dot in center
				draw_circle(local_tile_pos, 3, valid_move_color, true)
	
	# Draw current path
	if current_world_path.size() > 1:
		for i in range(current_world_path.size() - 1):
			var start = to_local(current_world_path[i])
			var end = to_local(current_world_path[i + 1])
			draw_line(start, end, Color.CYAN, 2.0)
	
	# Draw grid position indicator
	if pathfinder and pathfinder.has_method("grid_to_world"):
		var grid_world_pos = pathfinder.grid_to_world(Vector2i(grid_position.x, grid_position.y))
		grid_world_pos += position_offset
		grid_world_pos.y -= grid_position.z * layer_height_offset
		
		# Apply tile height offset if enabled
		if use_tile_height:
			var tile_height_offset = get_tile_height_offset(grid_position)
			grid_world_pos.y += tile_height_offset * tile_height_multiplier
		
		var local_grid_pos = to_local(grid_world_pos)
		
		# Draw different colors based on selection state
		var indicator_color = Color.GREEN if not is_selected else Color.BLUE
		draw_circle(local_grid_pos, 8, indicator_color)
		
		# Draw layer number and height info
		var font = ThemeDB.fallback_font
		var layer_text = "L" + str(grid_position.z)
		if use_tile_height:
			var height_mult = get_tile_height_multiplier(grid_position)
			layer_text += " H:" + str(snappedf(height_mult, 0.01))
		draw_string(font, local_grid_pos + Vector2(-10, -10), layer_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
