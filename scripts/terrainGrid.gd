extends Node2D

@export var map_size: Vector2i = Vector2i(8, 8)          # Grid size (width x height)
@export var tile_size: Vector2 = Vector2(64, 32)         # Size of one diamond tile (width, height)
@export var grid_offset: Vector2 = Vector2.ZERO           # Center position of the first tile

@export var show_debug_points: bool = true
@export var icon_texture: Texture2D
@export var icon_scale: float = 0.5

var grid: Dictionary = {}  # { Vector2i(x, y): Vector2(world_pos) }
var debug_icons: Array[Sprite2D] = []
var last_grid_offset: Vector2 = Vector2.INF  # Track changes to grid_offset

func _ready():
	_generate_grid()
	_spawn_debug_icons()
	set_process(true)
	set_process_internal(true)  # Enable running in editor

func _process(_delta):
	# Detect changes to grid_offset or show_debug_points at runtime or editor time
	if grid_offset != last_grid_offset:
		last_grid_offset = grid_offset
		_update_grid_and_icons()

func _generate_grid():
	grid.clear()
	for x in map_size.x:
		for y in map_size.y:
			var coord = Vector2i(x, y)
			var offset_x = (coord.x - coord.y) * (tile_size.x / 2)
			var offset_y = (coord.x + coord.y) * (tile_size.y / 2)
			var world_pos = grid_offset + Vector2(offset_x, offset_y)
			grid[coord] = world_pos

func _spawn_debug_icons():
	_clear_debug_icons()

	if not show_debug_points or icon_texture == null:
		return

	for coord in grid.keys():
		var pos = grid[coord]

		var icon = Sprite2D.new()
		icon.texture = icon_texture
		icon.scale = Vector2(icon_scale, icon_scale)
		icon.position = pos
		icon.centered = true
		icon.z_index = 1000
		icon.visible = true

		add_child(icon)
		debug_icons.append(icon)

func _clear_debug_icons():
	for icon in debug_icons:
		if is_instance_valid(icon):
			icon.queue_free()
	debug_icons.clear()

func _update_grid_and_icons():
	_generate_grid()
	if show_debug_points:
		if debug_icons.size() == 0:
			_spawn_debug_icons()
		else:
			for i in range(debug_icons.size()):
				if i >= grid.size():
					break
				var pos = grid[grid.keys()[i]]
				debug_icons[i].position = pos
	else:
		_clear_debug_icons()
