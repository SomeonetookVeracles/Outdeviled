extends Resource
class_name MovementProfile

# Movement profile resource for different character types
# Defines movement patterns, ranges, and restrictions

@export var profile_name: String = "Default"
@export var description: String = "Basic movement profile"

# Movement range and patterns
@export var max_movement_range: int = 3  # Maximum tiles character can move
@export var min_movement_range: int = 1  # Minimum movement distance
@export var movement_pattern: MovementPattern = MovementPattern.FREE
@export var can_move_diagonally: bool = true
@export var requires_line_of_sight: bool = false

# Movement costs
@export var movement_cost_multiplier: float = 1.0
@export var diagonal_cost_multiplier: float = 1.414  # sqrt(2)

# Raycast settings
@export var use_raycasting: bool = true
@export var raycast_collision_mask: int = 1
@export var allow_through_characters: bool = false
@export var max_raycast_distance: float = 500.0

# Special movement abilities
@export var can_jump_over_obstacles: bool = false
@export var can_move_through_walls: bool = false
@export var preferred_movement_directions: Array[Vector2i] = []

# Movement restrictions
@export var forbidden_cell_types: Array[String] = []
@export var required_cell_types: Array[String] = []
@export var layer_restrictions: Array[int] = []  # Empty = all layers allowed

enum MovementPattern {
	FREE,           # Can move in any direction within range
	CROSS_ONLY,     # Only cardinal directions (no diagonals)
	DIAGONAL_ONLY,  # Only diagonal movements
	KNIGHT,         # L-shaped movement like chess knight
	STRAIGHT_LINE,  # Must move in straight lines only
	ADJACENT_ONLY,  # Can only move to adjacent tiles
	CUSTOM          # Uses preferred_movement_directions
}

func get_valid_movement_directions() -> Array[Vector2i]:
	"""Get valid movement directions based on pattern"""
	var directions: Array[Vector2i] = []
	
	match movement_pattern:
		MovementPattern.FREE:
			if can_move_diagonally:
				directions = [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
				]
			else:
				directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		
		MovementPattern.CROSS_ONLY:
			directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		
		MovementPattern.DIAGONAL_ONLY:
			directions = [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
		
		MovementPattern.KNIGHT:
			directions = [
				Vector2i(2, 1), Vector2i(2, -1), Vector2i(-2, 1), Vector2i(-2, -1),
				Vector2i(1, 2), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(-1, -2)
			]
		
		MovementPattern.ADJACENT_ONLY:
			if can_move_diagonally:
				directions = [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)
				]
			else:
				directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		
		MovementPattern.CUSTOM:
			directions = preferred_movement_directions.duplicate()
		
		MovementPattern.STRAIGHT_LINE:
			# For straight line, we'll handle this differently in the movement calculation
			directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			if can_move_diagonally:
				directions.append_array([Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)])
	
	return directions

func is_valid_movement_distance(distance: int) -> bool:
	"""Check if movement distance is within allowed range"""
	return distance >= min_movement_range and distance <= max_movement_range

func can_move_to_layer(layer: int) -> bool:
	"""Check if movement to specific layer is allowed"""
	if layer_restrictions.is_empty():
		return true
	return layer in layer_restrictions

func get_movement_cost(from: Vector2i, to: Vector2i) -> float:
	"""Calculate movement cost between two positions"""
	var direction = to - from
	var distance = sqrt(direction.x * direction.x + direction.y * direction.y)
	
	var cost = distance * movement_cost_multiplier
	
	# Apply diagonal cost if moving diagonally
	if abs(direction.x) == abs(direction.y) and direction.length() > 1:
		cost *= diagonal_cost_multiplier
	
	return cost

# Utility functions for profile creation
static func create_infantry_profile() -> MovementProfile:
	"""Create a basic infantry profile"""
	var profile = MovementProfile.new()
	profile.profile_name = "Infantry"
	profile.description = "Basic infantry unit with short range movement"
	profile.max_movement_range = 2
	profile.min_movement_range = 1
	profile.movement_pattern = MovementPattern.FREE
	profile.can_move_diagonally = true
	profile.requires_line_of_sight = false
	profile.use_raycasting = true
	profile.raycast_collision_mask = 1
	return profile

static func create_scout_profile() -> MovementProfile:
	"""Create a scout profile with long range"""
	var profile = MovementProfile.new()
	profile.profile_name = "Scout"
	profile.description = "Fast scout with long movement range"
	profile.max_movement_range = 5
	profile.min_movement_range = 1
	profile.movement_pattern = MovementPattern.FREE
	profile.can_move_diagonally = true
	profile.requires_line_of_sight = true
	profile.use_raycasting = true
	profile.movement_cost_multiplier = 0.8
	return profile

static func create_heavy_profile() -> MovementProfile:
	"""Create a heavy unit profile"""
	var profile = MovementProfile.new()
	profile.profile_name = "Heavy"
	profile.description = "Heavy unit with limited movement but can break obstacles"
	profile.max_movement_range = 1
	profile.min_movement_range = 1
	profile.movement_pattern = MovementPattern.ADJACENT_ONLY
	profile.can_move_diagonally = false
	profile.requires_line_of_sight = false
	profile.use_raycasting = true
	profile.can_jump_over_obstacles = true
	profile.movement_cost_multiplier = 1.5
	return profile

static func create_knight_profile() -> MovementProfile:
	"""Create a knight profile with L-shaped movement"""
	var profile = MovementProfile.new()
	profile.profile_name = "Knight"
	profile.description = "Knight with L-shaped movement pattern"
	profile.max_movement_range = 3
	profile.min_movement_range = 2
	profile.movement_pattern = MovementPattern.KNIGHT
	profile.can_move_diagonally = false
	profile.requires_line_of_sight = false
	profile.use_raycasting = true
	profile.can_jump_over_obstacles = true
	return profile

static func create_archer_profile() -> MovementProfile:
	"""Create an archer profile requiring line of sight"""
	var profile = MovementProfile.new()
	profile.profile_name = "Archer"
	profile.description = "Archer requiring clear line of sight"
	profile.max_movement_range = 3
	profile.min_movement_range = 1
	profile.movement_pattern = MovementPattern.FREE
	profile.can_move_diagonally = true
	profile.requires_line_of_sight = true
	profile.use_raycasting = true
	profile.raycast_collision_mask = 3  # More restrictive collision
	return profile

static func create_flyer_profile() -> MovementProfile:
	"""Create a flying unit profile"""
	var profile = MovementProfile.new()
	profile.profile_name = "Flyer"
	profile.description = "Flying unit that ignores ground obstacles"
	profile.max_movement_range = 4
	profile.min_movement_range = 1
	profile.movement_pattern = MovementPattern.FREE
	profile.can_move_diagonally = true
	profile.requires_line_of_sight = false
	profile.use_raycasting = false  # Can fly over everything
	profile.can_move_through_walls = true
	return profile

# Debug and info functions
func get_pattern_name() -> String:
	"""Get the movement pattern name as string"""
	match movement_pattern:
		MovementPattern.FREE: return "FREE"
		MovementPattern.CROSS_ONLY: return "CROSS_ONLY"
		MovementPattern.DIAGONAL_ONLY: return "DIAGONAL_ONLY"
		MovementPattern.KNIGHT: return "KNIGHT"
		MovementPattern.STRAIGHT_LINE: return "STRAIGHT_LINE"
		MovementPattern.ADJACENT_ONLY: return "ADJACENT_ONLY"
		MovementPattern.CUSTOM: return "CUSTOM"
		_: return "UNKNOWN"

func print_profile_info():
	"""Print detailed information about this profile"""
	print("=== MOVEMENT PROFILE: %s ===" % profile_name)
	print("Description: %s" % description)
	print("Range: %d-%d tiles" % [min_movement_range, max_movement_range])
	print("Pattern: %s" % get_pattern_name())
	print("Diagonal movement: %s" % ("YES" if can_move_diagonally else "NO"))
	print("Line of sight required: %s" % ("YES" if requires_line_of_sight else "NO"))
	print("Uses raycasting: %s" % ("YES" if use_raycasting else "NO"))
	print("Can jump obstacles: %s" % ("YES" if can_jump_over_obstacles else "NO"))
	print("Can move through walls: %s" % ("YES" if can_move_through_walls else "NO"))
	if not layer_restrictions.is_empty():
		print("Layer restrictions: %s" % layer_restrictions)
	print("Movement cost multiplier: %.2f" % movement_cost_multiplier)
