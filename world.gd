extends Node2D

@onready var TERRAIN_TILEMAP: TileMapLayer = $city_builder/terrain
@onready var CONSTRUCTION_TILEMAP: TileMapLayer = $city_builder/construction
@onready var OVERLAY_TILEMAP: TileMapLayer = $city_builder/overlay

const OVERLAY_SHADER_PATH = "res://overlay.gdshader"

var construction_map: Dictionary = {}
var terrain_map: Dictionary = {}

var constructions_inventory: Dictionary = {}
var construction_groups: Dictionary = {}

const tiles_to_nodes = {
	Vector2i(0,0): "wwtw_main",
	Vector2i(1,0): "wwtw_1",
	Vector2i(2,0): "fwtw_main",
	Vector2i(3,0): "residential_1",
	Vector2i(0,1): "rural",
	Vector2i(1,1): "urban",
	Vector2i(2,1): "river",
	Vector2i(3,1): "catchment",
	Vector2i(4,1): "outlet"
}

var nodes_to_tiles = {}

func _init():
	for key in tiles_to_nodes:
		nodes_to_tiles[tiles_to_nodes[key]] = key

func reverse_dictionary(original_dict: Dictionary) -> Dictionary:
	var reversed_dict = {}
	for key in original_dict.keys():
		reversed_dict[original_dict[key]] = key
	return reversed_dict

const default_nodes = {
	"wwtw_main": ["wwtw_main", 2e3, 2e3, 5e3], # (, stormwater_storage_capacity, stormwater_storage_area, treatment_throughput_capacity)
	"wwtw_1": ["wwtw_1"], # decorative
	"fwtw_main": ["fwtw_main", 1e4, 2e3, 5e3], # (, service_reservoir_storage_capacity, service_reservoir_storage_area, treatment_throughput_capacity)
	"residential_1": ["residential_1", 1e4, 0.15], # (, population, per_capita)
	"rural": ["rural", 1e5, 5e4, 0.3, 0.5], # (, area, initial_storage, field_capacity, depth)
	"urban": ["urban", 1e5, 5e4], # (, area, initial_storage)
	"river": ["river"],
	"catchment": ["catchment"],
	"outlet": ["outlet"]
}

func load_map_from_tilemap(tilemap: TileMapLayer):
	var used_cells = tilemap.get_used_cells()
	var map = {}
	for cell in used_cells:
		map[cell] = default_nodes[tiles_to_nodes[tilemap.get_cell_atlas_coords(cell)]]
	return map

func make_constructions_inventory():
	# Explore all cells of the construction_map to identify the locations of each building type,
	# while performing DFS on each unexplored cell to form groups of cells (e.g. a group of
	# residential tiles next to each other, or a wwtw_main tile with the decorative tiles next to it)
	# For each group, a node is chosen as the parent of the group
	
	var _constructions_inventory = {}
	var _construction_groups = {}
	
	var visited = {}
	for cell in construction_map: # TODO : changer ordre de parcours pour que cells avec un nom en "..._main" soient traitées en premier
		if cell in visited: 
			continue
		var tile_group = [cell]
		var stack = [cell]
		var cell_type = construction_map[cell][0].split("_")[0]
		while len(stack) != 0:
			var cell_ = stack.pop_back()
			visited[cell_] = true
			for neighbor in CONSTRUCTION_TILEMAP.get_surrounding_cells(cell_):
				if neighbor not in construction_map:
					continue
				var neighbor_type = construction_map[neighbor][0].split("_")[0]
				if neighbor not in visited and neighbor_type == cell_type:
					visited[neighbor] = true
					tile_group.append(neighbor)
					_construction_groups[neighbor] = cell
					stack.append(neighbor)
		if cell_type not in _constructions_inventory:
			_constructions_inventory[cell_type] = []
		_constructions_inventory[cell_type].append(tile_group)
		_construction_groups[cell] = tile_group
	
	return [_constructions_inventory, _construction_groups]

func map_to_model():
	# var rural_area = ...
	# var urban_area = ...
	
	### 1. Rivers ###
	
	### 2. Constructions ###
		# Handle constraints ? (fwtw_main / wwtw_main must be next to a river tile
	return {}

func _ready():
	OVERLAY_TILEMAP.clear()
	var overlay_shader = load(OVERLAY_SHADER_PATH)
	var overlay_material = ShaderMaterial.new()
	overlay_material.shader = overlay_shader
	overlay_material.set_shader_parameter("opacity", 0.5)
	OVERLAY_TILEMAP.material = overlay_material
	
	construction_map = load_map_from_tilemap(CONSTRUCTION_TILEMAP)
	terrain_map = load_map_from_tilemap(TERRAIN_TILEMAP)
	update_constructions()

enum State { IDLE, ARC_CREATION, BUILDING }
var current_state = State.IDLE
var hovered_cell = null
var clicked_cells = []
var requested_building = null

func update_constructions():
	var constructions_inventory_and_group_parents = make_constructions_inventory()
	constructions_inventory = constructions_inventory_and_group_parents[0]
	construction_groups = constructions_inventory_and_group_parents[1]

func add_building(building: Array, coords: Vector2i):
	print(building, construction_map, coords)
	construction_map[coords] = building
	CONSTRUCTION_TILEMAP.set_cell(coords, 0, nodes_to_tiles[building[0]])
	update_constructions()
	

func _on_create_arc_pressed() -> void:
	current_state = State.ARC_CREATION
	clicked_cells = []

func _on_residential_1_pressed() -> void:
	current_state = State.BUILDING
	requested_building = default_nodes["residential_1"]

func _input(event):
	var mouse_pos = TERRAIN_TILEMAP.get_local_mouse_position()
	var new_hovered_cell = TERRAIN_TILEMAP.local_to_map(mouse_pos)
	
	match current_state:
		State.BUILDING:
			# Overlay over available terrain
			if not (hovered_cell == new_hovered_cell):
				if hovered_cell != null:
					OVERLAY_TILEMAP.clear()
					
			if new_hovered_cell not in construction_groups \
				and new_hovered_cell in terrain_map \
				and terrain_map[new_hovered_cell][0] not in ["river", "catchment", "outlet"]:
				
				if not (hovered_cell == new_hovered_cell):
					OVERLAY_TILEMAP.set_cell(new_hovered_cell, 0, nodes_to_tiles[requested_building[0]])
				
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					print("build", requested_building)
					add_building(requested_building, new_hovered_cell)
					OVERLAY_TILEMAP.clear()
					current_state = State.IDLE
				
		State.ARC_CREATION:
			# Overlay over hovered buildings
			if not (hovered_cell == new_hovered_cell):
				if new_hovered_cell in construction_groups:
					if hovered_cell != null:
						OVERLAY_TILEMAP.clear()
					# Overlay over the whole group of buildings
					var cell_group = construction_groups[new_hovered_cell]
					if cell_group is Vector2i: # fetch the group from the parent
						cell_group = construction_groups[cell_group]
					for cell in cell_group:
						OVERLAY_TILEMAP.set_cell(cell, 0, CONSTRUCTION_TILEMAP.get_cell_atlas_coords(cell))
				else:
					OVERLAY_TILEMAP.clear()
			# Selecting the two nodes to make an arc between
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if len(clicked_cells) == 1:
					print("end selection")
					clicked_cells.append(new_hovered_cell)
					print(clicked_cells)
					current_state = State.IDLE
					OVERLAY_TILEMAP.clear()
				if len(clicked_cells) == 0:
					print("start selection")
					clicked_cells.append(new_hovered_cell)
			# Check for right click to cancel selection
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				print("cancel selection")
				current_state = State.IDLE
				OVERLAY_TILEMAP.clear()
			
	hovered_cell = new_hovered_cell
