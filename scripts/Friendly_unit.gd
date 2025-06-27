extends CharacterBody2D
class_name PathfindingCharacter

@export var move_speed: float = 200.0
@export var snap_distance: float = 10.0
@export var pathfinding_node_path: NodePath
@export var show_path: bool = true
@export var path_color: Color = Color.YELLOW
@export var path_width: float = 2.0
@export var point_color: Color = Color.GREEN
@export var point_radius: float = 4.0

var pathfinding_module
var current_path: Array = []
var current_target_index: int = 0
var is_moving: bool = false

func _ready():
	if pathfinding_node_path:
		pathfinding_module = get_node(pathfinding_node_path)
		place_at_random_point()
	
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		request_path_to_position(event.position)

func _physics_process(delta):
	if is_moving and current_path.size() > 0:
		move_along_path(delta)

func request_path_to_position(target_pos: Vector2):
	if not pathfinding_module:
		push_error("No pathfinding module assigned!")
		return
		
	# Convert screen position to world position if needed
	var world_pos = get_global_mouse_position()
	
	# Find nearest valid point to click position
	var nearest_point = find_nearest_path_point(world_pos)
	if nearest_point == Vector2.ZERO:
		return
	
	# Get path from current position to target
	var start_point = find_nearest_path_point(global_position)
	current_path = pathfinding_module.find_path(start_point, nearest_point)
	
	if current_path.size() > 0:
		current_target_index = 0
		is_moving = true

func move_along_path(delta):
	if current_target_index >= current_path.size():
		# Reached end of path
		is_moving = false
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	var target_point = current_path[current_target_index]
	var direction = (target_point - global_position).normalized()
	var distance_to_target = global_position.distance_to(target_point)
	
	if distance_to_target <= snap_distance:
		# Snap to point and move to next
		global_position = target_point
		current_target_index += 1
		velocity = Vector2.ZERO
	else:
		# Move towards target
		velocity = direction * move_speed
		
	move_and_slide()

func find_nearest_path_point(pos: Vector2) -> Vector2:
	if not pathfinding_module or not pathfinding_module.has_method("get_all_points"):
		return Vector2.ZERO
		
	var all_points = pathfinding_module.get_all_points()
	var nearest_point = Vector2.ZERO
	var min_distance = INF
	
	for point in all_points:
		var dist = pos.distance_to(point)
		if dist < min_distance:
			min_distance = dist
			nearest_point = point
			
	return nearest_point

func place_at_random_point():
	if not pathfinding_module or not pathfinding_module.has_method("get_all_points"):
		push_error("Cannot place at random point - no pathfinding module")
		return
		
	var all_points = pathfinding_module.get_all_points()
	if all_points.size() == 0:
		push_error("No pathfinding points available")
		return
		
	var random_point = all_points[randi() % all_points.size()]
	global_position = random_point

# Optional: Draw path for debugging
func _draw():
	if not show_path:
		return
		
	if current_path.size() > 1:
		for i in range(current_path.size() - 1):
			var from = to_local(current_path[i])
			var to = to_local(current_path[i + 1])
			draw_line(from, to, path_color, path_width)
		
		# Draw remaining path points
		for i in range(current_target_index, current_path.size()):
			var point = to_local(current_path[i])
			draw_circle(point, point_radius, point_color)

# Force redraw when path changes
func _on_path_changed():
	queue_redraw()
