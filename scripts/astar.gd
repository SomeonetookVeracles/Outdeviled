extends Node
class_name IsometricPathfinder

# Grid pathfinding system for isometric strategy game with multi-layer support
# Handles stairs, teleporters, and different Z levels

signal path_calculated(path: Array)
signal accessible_cells_updated(cells: Array)

@export var terrain_node: Node2D
@export var grid_size: Vector2i = Vector2i(32, 32)
@export var cell_size: Vector2 = Vector2(64, 32)  # Isometric cell dimensions
@export var cube_height: float = 32.0  # Height of the isometric cube for vertical offset calculations
@export var debug_offset: Vector2 = Vector2(0.0, -8.0)  # X and Y offset for debug markers
@export var height_data_layer_name: String = "height"  # Name of the custom data layer for tile heights
@export var use_tile_height_offset: bool = true  # Whether to use tile height data for debug offset
@export var max_layers: int = 2
@export var debug_draw: bool = false

# Pathfinding data structures
var astar: AStar2D
var grid_data: Dictionary = {}  # [Vector3i] -> CellData
var layer_nodes: Array[Node2D] = []
var accessible_cells: Array[Vector3i] = []

# Cell types
enum CellType {
	EMPTY,
	BLOCKED,
	WALKABLE,
	STAIR_UP,
	STAIR_DOWN,
	TELEPORTER_ENTRANCE,
	TELEPORTER_EXIT
}

# Cell data structure
class CellData:
	var position: Vector3i
	var type: CellType
	var walkable: bool = false
	var movement_cost: float = 1.0
	var teleporter_target: Vector3i = Vector3i.ZERO
	var stair_target: Vector3i = Vector3i.ZERO
	
	func _init(pos: Vector3i, cell_type: CellType = CellType.EMPTY):
		position = pos
		type = cell_type
		walkable = (type in [CellType.WALKABLE, CellType.STAIR_UP, CellType.STAIR_DOWN, 
							CellType.TELEPORTER_ENTRANCE, CellType.TELEPORTER_EXIT])

func _ready():
	initialize_pathfinding_system()

func initialize_pathfinding_system():
	"""Initialize the pathfinding system and scan terrain layers"""
	astar = AStar2D.new()
	
	if not terrain_node:
		push_error("Terrain node not assigned!")
		return
	
	scan_terrain_layers()
	build_pathfinding_graph()
	update_accessible_cells()
	
	# Set up debug drawing if enabled (deferred to avoid setup conflicts)
	if debug_draw:
		setup_debug_drawing.call_deferred()

func scan_terrain_layers():
	"""Scan all terrain layers and populate grid data"""
	grid_data.clear()
	layer_nodes.clear()
	
	# Find layer nodes under terrain
	for i in range(max_layers):
		var layer_name = "Layer %d" % i
		var layer_node = terrain_node.get_node_or_null(layer_name)
		
		if layer_node:
			layer_nodes.append(layer_node)
			scan_layer(layer_node, i)
		else:
			layer_nodes.append(null)
			print("Warning: Layer %d not found" % i)

func scan_layer(layer_node: Node2D, layer_index: int):
	"""Scan a specific layer for terrain data"""
	if not layer_node:
		return
	
	# Scan grid positions for this layer
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var grid_pos = Vector3i(x, y, layer_index)
			var cell_data = analyze_cell_at_position(layer_node, Vector2i(x, y), layer_index)
			
			# Always create cell data, we'll filter debug drawing separately
			if cell_data:
				grid_data[grid_pos] = cell_data

func analyze_cell_at_position(layer_node: Node2D, grid_pos: Vector2i, layer_index: int) -> CellData:
	"""Analyze what type of cell exists at a grid position"""
	var world_pos = grid_to_world(grid_pos)
	var cell_type = CellType.EMPTY
	var cell_data: CellData
	
	# Check for collision objects to determine terrain type
	var space_state = layer_node.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = 1  # Adjust collision mask as needed
	
	var results = space_state.intersect_point(query)
	
	if results.is_empty():
		cell_type = CellType.WALKABLE  # Default to walkable if no collision obstacles
	else:
		# Check collision objects for terrain type
		for result in results:
			var collider = result.collider
			
			# Check node groups or custom properties to determine cell type
			if collider.is_in_group("blocked"):
				cell_type = CellType.BLOCKED
				break
			elif collider.is_in_group("stairs_up"):
				cell_type = CellType.STAIR_UP
				break
			elif collider.is_in_group("stairs_down"):
				cell_type = CellType.STAIR_DOWN
				break
			elif collider.is_in_group("teleporter_entrance"):
				cell_type = CellType.TELEPORTER_ENTRANCE
				break
			elif collider.is_in_group("teleporter_exit"):
				cell_type = CellType.TELEPORTER_EXIT
				break
			else:
				cell_type = CellType.WALKABLE
	
	cell_data = CellData.new(Vector3i(grid_pos.x, grid_pos.y, layer_index), cell_type)
	
	# Set up special connections for stairs and teleporters
	setup_special_connections(cell_data, layer_node)
	
	return cell_data

func get_tile_height_at_position(layer_node: Node, world_pos: Vector2) -> float:
	"""Get the height value from tile custom data at a given position"""
	var height_multiplier = 1.0  # Default height (full cube height)
	
	# Handle TileMapLayer (Godot 4.2+)
	if layer_node.get_class() == "TileMapLayer":
		var tilemap_layer = layer_node as TileMapLayer
		if tilemap_layer.enabled:
			var local_pos = tilemap_layer.to_local(world_pos)
			var tile_pos = tilemap_layer.local_to_map(local_pos)
			
			# Get tile data to access custom properties
			var tile_data = tilemap_layer.get_cell_tile_data(tile_pos)
			if tile_data and tile_data.get_custom_data(height_data_layer_name) != null:
				height_multiplier = tile_data.get_custom_data(height_data_layer_name)
	
	# Handle regular TileMap (Godot 4.0/4.1)
	elif layer_node is TileMap:
		var tilemap = layer_node as TileMap
		if tilemap.visible:
			var local_pos = tilemap.to_local(world_pos)
			var tile_pos = tilemap.local_to_map(local_pos)
			
			# Check all layers for tile data
			for layer_idx in range(tilemap.get_layers_count()):
				var tile_data = tilemap.get_cell_tile_data(layer_idx, tile_pos)
				if tile_data and tile_data.get_custom_data(height_data_layer_name) != null:
					height_multiplier = tile_data.get_custom_data(height_data_layer_name)
					break
	
	return height_multiplier

func has_sprite_at_position(layer_node: Node2D, world_pos: Vector2, tolerance: float = 16.0) -> bool:
	"""Check if there's a sprite at a given world position"""
	var search_rect = Rect2(world_pos - Vector2(tolerance, tolerance), Vector2(tolerance * 2, tolerance * 2))
	
	print("  Searching for sprites in layer: ", layer_node.name, " at world pos: ", world_pos)
	print("  Layer has ", layer_node.get_child_count(), " children")
	
	# List all children in the layer for debugging
	for i in range(min(5, layer_node.get_child_count())):  # Show first 5 children
		var child = layer_node.get_child(i)
		print("    Child ", i, ": ", child.name, " (", child.get_class(), ") at ", child.position)
	
	var result = _has_sprite_recursive(layer_node, search_rect, 0)
	print("  Sprite search result: ", result)
	return result

func _has_sprite_recursive(node: Node, search_rect: Rect2, depth: int = 0) -> bool:
	"""Recursively search for sprites within a rectangle"""
	# Handle TileMapLayer (Godot 4.2+) - these ARE the tiles themselves
	if node.get_class() == "TileMapLayer":
		var tilemap_layer = node as TileMapLayer
		if tilemap_layer.enabled:
			# Convert world position to tile coordinates
			var center_pos = search_rect.position + search_rect.size * 0.5
			var local_pos = tilemap_layer.to_local(center_pos)
			var tile_pos = tilemap_layer.local_to_map(local_pos)
			
			# Check if there's a tile at this position
			var tile_source_id = tilemap_layer.get_cell_source_id(tile_pos)
			if tile_source_id != -1:  # -1 means no tile
				print("    -> TILEMAP LAYER MATCH at tile pos ", tile_pos, "!")
				return true
	
	# Handle regular TileMap (Godot 4.0/4.1)
	elif node is TileMap:
		var tilemap = node as TileMap
		if tilemap.visible:
			var local_pos = tilemap.to_local(search_rect.position + search_rect.size * 0.5)
			var tile_pos = tilemap.local_to_map(local_pos)
			
			for layer_idx in range(tilemap.get_layers_count()):
				var tile_source_id = tilemap.get_cell_source_id(layer_idx, tile_pos)
				if tile_source_id != -1:
					print("    -> TILEMAP MATCH at layer ", layer_idx, "!")
					return true
	
	# Handle sprite nodes
	elif node is Sprite2D:
		var sprite = node as Sprite2D
		if sprite.texture and sprite.visible and search_rect.has_point(sprite.global_position):
			print("    -> SPRITE2D MATCH!")
			return true
	elif node is AnimatedSprite2D:
		var anim_sprite = node as AnimatedSprite2D
		if anim_sprite.sprite_frames and anim_sprite.visible and search_rect.has_point(anim_sprite.global_position):
			print("    -> ANIMATED SPRITE MATCH!")
			return true
	
	# Recursively check children (limit depth to avoid spam)
	if depth < 2:
		for child in node.get_children():
			if _has_sprite_recursive(child, search_rect, depth + 1):
				return true
	
	return false

func setup_special_connections(cell_data: CellData, layer_node: Node2D):
	"""Set up special connections for stairs and teleporters"""
	match cell_data.type:
		CellType.STAIR_UP:
			# Connect to layer above
			if cell_data.position.z < max_layers - 1:
				cell_data.stair_target = Vector3i(
					cell_data.position.x, 
					cell_data.position.y, 
					cell_data.position.z + 1
				)
		
		CellType.STAIR_DOWN:
			# Connect to layer below
			if cell_data.position.z > 0:
				cell_data.stair_target = Vector3i(
					cell_data.position.x, 
					cell_data.position.y, 
					cell_data.position.z - 1
				)
		
		CellType.TELEPORTER_ENTRANCE:
			# Find corresponding teleporter exit
			cell_data.teleporter_target = find_teleporter_exit(cell_data.position, layer_node)
		
		CellType.TELEPORTER_EXIT:
			cell_data.movement_cost = 0.1  # Very low cost to prefer as destination

func find_teleporter_exit(entrance_pos: Vector3i, layer_node: Node2D) -> Vector3i:
	"""Find the corresponding teleporter exit for an entrance"""
	# This is a simplified implementation - you might want to use IDs or other matching systems
	var world_pos = grid_to_world(Vector2i(entrance_pos.x, entrance_pos.y))
	
	# Look for teleporter exits in all layers
	for layer_idx in range(max_layers):
		if not layer_nodes[layer_idx]:
			continue
			
		var exits = layer_nodes[layer_idx].get_tree().get_nodes_in_group("teleporter_exit")
		for exit in exits:
			if exit.has_method("get_teleporter_id") and layer_node.has_method("get_teleporter_id"):
				if exit.get_teleporter_id() == layer_node.get_teleporter_id():
					var exit_grid = world_to_grid(exit.global_position)
					return Vector3i(exit_grid.x, exit_grid.y, layer_idx)
	
	return Vector3i.ZERO  # No exit found

func build_pathfinding_graph():
	"""Build the AStar2D graph with all connections"""
	astar.clear()
	
	# Add all walkable points to AStar
	var point_id = 0
	var pos_to_id: Dictionary = {}
	
	for pos in grid_data.keys():
		var cell_data = grid_data[pos] as CellData
		if cell_data.walkable:
			astar.add_point(point_id, Vector2(float(pos.x + pos.y * grid_size.x + pos.z * grid_size.x * grid_size.y), 0.0))
			pos_to_id[pos] = point_id
			point_id += 1
	
	# Connect adjacent points
	for pos in grid_data.keys():
		var cell_data = grid_data[pos] as CellData
		if not cell_data.walkable:
			continue
		
		var current_id = pos_to_id[pos]
		
		# Standard adjacent connections (same layer)
		var directions = [
			Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
			Vector3i(0, 1, 0), Vector3i(0, -1, 0),
			Vector3i(1, 1, 0), Vector3i(-1, -1, 0),
			Vector3i(1, -1, 0), Vector3i(-1, 1, 0)  # Diagonal connections
		]
		
		for dir in directions:
			var neighbor_pos = pos + dir
			if neighbor_pos in grid_data and grid_data[neighbor_pos].walkable:
				var neighbor_id = pos_to_id[neighbor_pos]
				var cost = cell_data.movement_cost
				if abs(dir.x) + abs(dir.y) > 1:  # Diagonal movement
					cost *= 1.414  # sqrt(2)
				
				astar.connect_points(current_id, neighbor_id, cost)
		
		# Special connections (stairs, teleporters)
		match cell_data.type:
			CellType.STAIR_UP, CellType.STAIR_DOWN:
				if cell_data.stair_target in grid_data and grid_data[cell_data.stair_target].walkable:
					var target_id = pos_to_id[cell_data.stair_target]
					astar.connect_points(current_id, target_id, cell_data.movement_cost * 2)  # Stairs cost more
			
			CellType.TELEPORTER_ENTRANCE:
				if cell_data.teleporter_target in grid_data and grid_data[cell_data.teleporter_target].walkable:
					var target_id = pos_to_id[cell_data.teleporter_target]
					astar.connect_points(current_id, target_id, 1.0)  # Teleporter cost

func update_accessible_cells(from_position: Vector3i = Vector3i.ZERO):
	"""Update the list of accessible cells from a given position"""
	accessible_cells.clear()
	
	if from_position == Vector3i.ZERO or not (from_position in grid_data):
		# If no position specified, return all walkable cells
		for pos in grid_data.keys():
			if grid_data[pos].walkable:
				accessible_cells.append(pos)
	else:
		# Find all cells reachable from the given position
		var from_id = get_point_id_from_position(from_position)
		if from_id != -1:
			for pos in grid_data.keys():
				if grid_data[pos].walkable:
					var to_id = get_point_id_from_position(pos)
					if to_id != -1 and astar.are_points_connected(from_id, to_id):
						accessible_cells.append(pos)
	
	accessible_cells_updated.emit(accessible_cells)

func get_point_id_from_position(pos: Vector3i) -> int:
	"""Get AStar2D point ID from grid position"""
	var point_count = astar.get_point_count()
	for i in range(point_count):
		var point_pos = astar.get_point_position(i)
		var grid_pos = Vector3i(
			int(point_pos.x) % grid_size.x,
			int(point_pos.x) / grid_size.x % grid_size.y,
			int(point_pos.x) / (grid_size.x * grid_size.y)
		)
		if grid_pos == pos:
			return i
	return -1

func find_path(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	"""Find a path between two grid positions"""
	if not (from in grid_data) or not (to in grid_data):
		return []
	
	if not grid_data[from].walkable or not grid_data[to].walkable:
		return []
	
	var from_id = get_point_id_from_position(from)
	var to_id = get_point_id_from_position(to)
	
	if from_id == -1 or to_id == -1:
		return []
	
	var astar_path = astar.get_point_path(from_id, to_id)
	var grid_path: Array[Vector3i] = []
	
	for point in astar_path:
		var grid_pos = Vector3i(
			int(point.x) % grid_size.x,
			int(point.x) / grid_size.x % grid_size.y,
			int(point.x) / (grid_size.x * grid_size.y)
		)
		grid_path.append(grid_pos)
	
	path_calculated.emit(grid_path)
	return grid_path

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	"""Convert grid position to world position (isometric)"""
	var world_x = (grid_pos.x - grid_pos.y) * cell_size.x * 0.5
	var world_y = (grid_pos.x + grid_pos.y) * cell_size.y * 0.5
	return Vector2(world_x, world_y)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	"""Convert world position to grid position (isometric)"""
	var grid_x = int((world_pos.x / cell_size.x + world_pos.y / cell_size.y))
	var grid_y = int((world_pos.y / cell_size.y - world_pos.x / cell_size.x))
	return Vector2i(grid_x, grid_y)

func get_cell_data(pos: Vector3i) -> CellData:
	"""Get cell data at a specific position"""
	return grid_data.get(pos, null)

func is_cell_walkable(pos: Vector3i) -> bool:
	"""Check if a cell is walkable"""
	var cell_data = get_cell_data(pos)
	return cell_data != null and cell_data.walkable

func get_accessible_cells() -> Array[Vector3i]:
	"""Get the current list of accessible cells"""
	return accessible_cells

func refresh_pathfinding():
	"""Refresh the entire pathfinding system"""
	initialize_pathfinding_system()

# Debug drawing system
var debug_canvas: Node2D

func setup_debug_drawing():
	"""Set up debug drawing canvas"""
	if debug_draw and not debug_canvas:
		debug_canvas = Node2D.new()
		debug_canvas.name = "PathfindingDebug"
		get_tree().current_scene.add_child.call_deferred(debug_canvas)
		# Wait a frame before drawing to ensure canvas is ready
		await get_tree().process_frame
		draw_debug_grid()

func draw_debug_grid():
	"""Draw debug visualization of the grid"""
	if not debug_draw or not debug_canvas:
		return
	
	# Clear previous debug drawings
	for child in debug_canvas.get_children():
		child.queue_free()
	
	print("=== DEBUG GRID DRAWING ===")
	print("Total cells in grid_data: ", grid_data.size())
	print("Layer nodes available: ", layer_nodes.size())
	
	var sprites_found = 0
	var cells_drawn = 0
	var total_checked = 0
	
	for pos in grid_data.keys():
		var cell_data = grid_data[pos] as CellData
		var world_pos = grid_to_world(Vector2i(pos.x, pos.y))
		world_pos.y -= pos.z * 20  # Offset for different layers
		
		total_checked += 1
		
		# Check if there's a sprite at this position
		var layer_node = layer_nodes[pos.z] if pos.z < layer_nodes.size() else null
		var has_sprite = false
		
		if layer_node:
			# Use the original world position (without layer offset) for sprite detection
			var sprite_check_pos = grid_to_world(Vector2i(pos.x, pos.y))
			has_sprite = has_sprite_at_position(layer_node, sprite_check_pos)
			if has_sprite:
				sprites_found += 1
		
		# Only draw if sprite is found (fixed this line!)
		if not has_sprite:
			continue
			
		cells_drawn += 1
		
		var color = Color.RED
		match cell_data.type:
			CellType.WALKABLE:
				color = Color.GREEN
			CellType.BLOCKED:
				color = Color.RED
			CellType.STAIR_UP:
				color = Color.BLUE
			CellType.STAIR_DOWN:
				color = Color.CYAN
			CellType.TELEPORTER_ENTRANCE:
				color = Color.MAGENTA
			CellType.TELEPORTER_EXIT:
				color = Color.YELLOW
		
		# Make the color more transparent and discrete
		color.a = 0.4
		
		# Create debug marker with adjustable offset and tile height
		var debug_circle = ColorRect.new()
		debug_circle.size = Vector2(10.0, 10.0)
		
		# Calculate offset position - start at bottom of cell
		var offset_pos = world_pos - debug_circle.size * 0.5
		offset_pos.x += debug_offset.x  # Custom X offset
		offset_pos.y += debug_offset.y  # Custom Y offset
		
		# Position at bottom of cell first, then offset UP based on tile height
		offset_pos.y += cell_size.y * 0.5  # Move to bottom of isometric cell
		
		# Apply tile-specific height offset if enabled - offset DOWN from bottom
		if use_tile_height_offset and layer_node:
			# Use the original world position (without layer offset) for height detection
			var height_check_pos = grid_to_world(Vector2i(pos.x, pos.y))
			var tile_height_multiplier = get_tile_height_at_position(layer_node, height_check_pos)
			
			print("  Layer ", pos.z, " (", layer_node.name, ") checking height at pos: ", height_check_pos)
			print("  Layer ", pos.z, " node type: ", layer_node.get_class())
			
			# Offset DOWN from bottom based on tile height with specific values
			var height_offset = 1.0  # Default offset for 0 height
			if tile_height_multiplier >= 1.0:
				height_offset = 10.0
			elif tile_height_multiplier >= 0.5:
				height_offset = 5.0
			elif tile_height_multiplier >= 0.25:
				height_offset = 2.5
			else:
				height_offset = 1.0  # For 0 or very small values
			
			offset_pos.y += height_offset  # Add to move DOWN from bottom position
			print("  Layer ", pos.z, " tile height multiplier: ", tile_height_multiplier, " -> downward offset: ", height_offset)
		else:
			print("  Layer ", pos.z, " - no height offset applied (use_tile_height_offset: ", use_tile_height_offset, ", layer_node: ", layer_node != null, ")")
		
		debug_circle.position = offset_pos
		debug_circle.color = color
		debug_canvas.add_child.call_deferred(debug_circle)
		
		# Add layer number label to each debug marker
		var layer_label = Label.new()
		layer_label.text = str(pos.z)
		layer_label.position = offset_pos + Vector2(2.0, -2.0)  # Slight offset from marker center
		layer_label.add_theme_font_size_override("font_size", 8)  # Small font
		layer_label.add_theme_color_override("font_color", Color.WHITE)
		layer_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		layer_label.add_theme_constant_override("shadow_offset_x", 1)
		layer_label.add_theme_constant_override("shadow_offset_y", 1)
		# Make sure the label is always visible
		layer_label.z_index = 100
		debug_canvas.add_child.call_deferred(layer_label)
	
	print("=== SUMMARY ===")
	print("Checked: ", total_checked, " positions")
	print("Sprites found: ", sprites_found)
	print("Cells drawn: ", cells_drawn)

func toggle_debug_drawing():
	"""Toggle debug drawing on/off"""
	debug_draw = !debug_draw
	if debug_draw:
		setup_debug_drawing()
		draw_debug_grid()
	elif debug_canvas:
		debug_canvas.queue_free()
		debug_canvas = null
