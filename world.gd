extends Node2D

@onready var TERRAIN_TILEMAP: TileMapLayer = $city_builder/terrain
@onready var CONSTRUCTION_TILEMAP: TileMapLayer = $city_builder/construction
@onready var OVERLAY_TILEMAP: TileMapLayer = $city_builder/overlay
@onready var arcs_tilemaps: Node = $city_builder/arcs_tilemaps # Arcs tilemaps will be placed under this node
@onready var run_simulation_button: Button = $UI/side_menu/run_simulation

const OVERLAY_SHADER_PATH = "res://overlay.gdshader"
const ARCS_SHADER_PATH = "res://arcs.gdshader"

var TilesetClass = load("res://tileset.gd") # imports the class Tileset
var SetClass = load("res://set.gd") # imports the class Set

const INF = 1_000_000_000_000 # represents +infinity

var input_data_paths = {
	"Tamise à Oxford": ProjectSettings.globalize_path("res://scripts/python/data/processed_data_oxford_thames.csv"),
	"Seine à Paris": ProjectSettings.globalize_path("res://scripts/python/data/processed_data_paris_seine.csv")
}

# Game data
var nodes: Dictionary = {}
var arcs: Dictionary = {}
var terrain_tile_nodes = {} # cell coords -> terrain node name ("river_xxx" or "land")
var tile_nodes = {} # cell coords -> node name (e.g. "wwtw_0")
var terrain_tiles = {} # cell coords -> terrain tile name (e.g. "river", "ruralLand")
var tiles = {} # cell coords -> tile name (e.g. "wwtw_main")

var tileset = Tileset.new([
	["wwtw_main", Vector2i(0,0)],
	["wwtw_1", Vector2i(1,0)],
	["fwtw_main", Vector2i(2,0)],
	["residential_1", Vector2i(3,0)],
	["urbanLand", Vector2i(0,1)],
	["ruralLand", Vector2i(1,1)],
	["catchment", Vector2i(2,1)],
	["outlet", Vector2i(3,1)],
	["river", Vector2i(4,1)],
	["arcArrow_(0, -1)", Vector2i(0,2)],
	["arcArrow_(-1, 0)", Vector2i(1,2)],
	["arcArrow_(0, 1)", Vector2i(2,2)],
	["arcArrow_(1, 0)", Vector2i(3,2)],
	["arcArrow_(1, 0)_(0, -1)", Vector2i(0,3)],
	["arcArrow_(0, -1)_(1, 0)", Vector2i(1,3)],
	["arcArrow_(-1, 0)_(0, 1)", Vector2i(2,3)],
	["arcArrow_(0, 1)_(-1, 0)", Vector2i(3,3)],
	["arcArrowEnd_(1, 0)", Vector2i(0,4)],
	["arcArrowEnd_(0, -1)", Vector2i(1,4)],
	["arcArrowEnd_(-1, 0)", Vector2i(2,4)],
	["arcArrowEnd_(0, 1)", Vector2i(3,4)],
	["arcArrowStart_(0, -1)", Vector2i(0,5)],
	["arcArrowStart_(1, 0)", Vector2i(1,5)],
	["arcArrowStart_(0, 1)", Vector2i(2,5)],
	["arcArrowStart_(-1, 0)", Vector2i(3,5)],
	["arcArrow_(1, 0)_(0, 1)", Vector2i(0,6)],
	["arcArrow_(0, -1)_(-1, 0)", Vector2i(1,6)],
	["arcArrow_(0, 1)_(1, 0)", Vector2i(2,6)],
	["arcArrow_(-1, 0)_(0, -1)", Vector2i(3,6)]
])

var default_attributes = { # must be intensive values (i.e. per tile values), it's easier that way
	### Nodes ###
	"wwtw": {
		"stormwater_storage_capacity": 2e3,
		"stormwater_storage_area": 2e3,
		"treatment_throughput_capacity": 5e3
	},
	"fwtw":{
		"service_reservoir_storage_capacity": 2e3,
		"service_reservoir_storage_area": 2e3,
		"treatment_throughput_capacity": 5e3
	},
	"residential":{
		"population": 1e4,
		"per_capita": 0.15
	},
	"land": {
		"pervious": {
			"area": 1e5,
			"initial_storage": 5e4,
			"field_capacity": 0.3,
			"depth": 0.5
		},
		"impervious": {
			"area": 1e5,
			"initial_storage": 5e4,
		},
		"input_data": input_data_paths.keys()[0]
	},
	"sewer": {
		"capacity": 1e6
	},
	"catchment": {
		"input_data": input_data_paths.keys()[0]
	},
	"outlet": {},
	
	### Arcs ### # must be in this dictionary to be considered valid
	"catchment_to_river": {},
	"river_to_river": {},
	"river_to_fwtw": {
		"capacity": 5e4
	},
	"fwtw_to_residential": {},
	"residential_to_wwtw": {},
	"wwtw_to_river": {},
	"river_to_outlet": {}
}

const mergeable_building_types = {
	"residential": true
}

# ---

func flatten_array(arr: Array[Array]):
	var flattened_array: Array = []
	for sub_arr in arr:
		for item in sub_arr:
			flattened_array.append(item)
	return flattened_array

func find_river_path_dfs(start: Vector2i, goal: Vector2i):
	var stack = [start] 
	var parent = {start: null}
	var visited = {start: true}
	
	while stack:
		var node = stack.pop_back()
		if node == goal:
			var path = []
			var cur = goal
			while cur != null:
				path.append(cur)
				cur = parent[cur]
			path.reverse()
			return path
		for neighbor in TERRAIN_TILEMAP.get_surrounding_cells(node):
			if neighbor in visited or neighbor not in terrain_tiles:
				continue
			if terrain_tiles[neighbor] in ["river", "outlet"] or neighbor == goal:
				visited[neighbor] = true
				parent[neighbor] = node
				stack.append(neighbor)
	return null

func load_terrain_from_default_tilemap():
	var used_cells = TERRAIN_TILEMAP.get_used_cells()
	nodes["land"] = {
		"tiles": [],
		"attributes": default_attributes["land"]
	}
	nodes["sewer"] = { "tiles": [], "attributes": default_attributes["sewer"] }
	
	var catchments = []
	var outlets = []
	
	### Land, catchments and outlets ###
	
	for cell in used_cells:
		var tile_name = tileset.get_tile_name(TERRAIN_TILEMAP.get_cell_atlas_coords(cell))
		terrain_tiles[cell] = tile_name
		if tile_name in ["ruralLand", "urbanLand"]:
			nodes["land"]["tiles"].append(cell)
			terrain_tile_nodes[cell] = "land"
		if tile_name == "catchment":
			var node_name = "catchment_%s" % len(catchments)
			nodes[node_name] = { "tiles": [cell], "attributes": default_attributes["catchment"] }
			terrain_tile_nodes[cell] = node_name
			catchments.append(cell)
		if tile_name == "outlet":
			var node_name = "outlet_%s" % len(outlets)
			nodes[node_name] = { "tiles": [cell], "attributes": default_attributes["outlet"]}
			terrain_tile_nodes[cell] = node_name
			outlets.append(cell)

	### Rivers ###
	
	# 1. Selecting the tiles that will act as actual river nodes
	var rivers = []
	var remaining_catchments = catchments.duplicate()
	while len(remaining_catchments) != 0:
		var catchment = remaining_catchments.pop_front()
		
		var river: Array[Array] = []
		for outlet in outlets: # Find all the outlets where the river starting from catchment goes to
			var path = find_river_path_dfs(catchment, outlet)
			if path != null:
				if len(river) == 0: # first path found between a catchment and an outlet
					river.append(path)
				else: # make a junction with the first path found
					var shortest_path = null
					var shortest_length = INF
					var river_tiles_without_boundaries = Set.new(flatten_array(river)) \
						.difference(Set.new(catchments + outlets)).elements()
					for tile in river_tiles_without_boundaries:
						var path_ = find_river_path_dfs(tile, outlet)
						if len(path_) < shortest_length:
							shortest_path = path_
							shortest_length = len(path_)
					river.append(shortest_path)
		if (len(river) == 0): print("Catchment is not connected to any outlet") # TODO : Popup d'erreur
		for catchment_ in remaining_catchments:
			var path = find_river_path_dfs(catchment, river[0][-1])
			if path != null:
				var shortest_path = null
				var shortest_length = INF
				var river_tiles_without_boundaries = Set.new(flatten_array(river)) \
					.difference(Set.new(catchments + outlets)).elements()
				for tile in river_tiles_without_boundaries:
					var path_ = find_river_path_dfs(catchment_, tile)
					if len(path_) < shortest_length:
						shortest_path = path_
						shortest_length = len(path_)
					river.append(shortest_path)
					remaining_catchments.erase(catchment_)
		
		var r = len(rivers)
		for b in range(len(river)):
			var branch = river[b]
			print(b, branch)
			for n in range(len(branch)):
				if n not in [0, len(branch)-1]:
					var node = branch[n]
					if node in catchments or node in outlets: continue
					var node_name = "river_%s_%s_%s" % [r, b, n]
					nodes[node_name] = { "tiles": [node] }
					terrain_tile_nodes[node] = node_name
				if n > 0:
					add_arc_if_possible(terrain_tile_nodes[branch[n-1]], terrain_tile_nodes[branch[n]])
		rivers.append(river)
		
		# 2. Connect decorative tile nodes
		
		# Before connecting the decorative river nodes to the actual river nodes, we sort the nodes by their distance to
		# the outlet of their branch (or the outlet of the branch their branch point to), so that if a decorative river
		# node is at the same distance from two actual river nodes, it is connected to the one which is furthest downstream.
		var distances = {}
		for branch in river:
			if branch[-1] in outlets:
				for i in range(branch.size() - 1, -1, -1):
					var node = branch[i]
					distances[node] = i
			else: # means there is a junction, the branch connects to the main path river[0]
				for i in range(branch.size() - 1, -1, -1):
					var node = branch[i]
					var river_reversed = river[0].duplicate()
					river_reversed.reverse()
					distances[node] = i + river_reversed.find(branch[-1])
		
		var river_nodes = Set.new(flatten_array(river))
		#for node in river_nodes.elements():
			#OVERLAY_TILEMAP.set_cell(node, 0, Vector2i(0,1))
		
		# We perform a dfs to connect all the decorative river nodes
		# We exclude catchments since we do not want decorative river nodes to be connected to catchments
		var a_parcourir = river_nodes.difference(Set.new(catchments+outlets)).elements()
		var distance_sort = func(a, b) -> bool:
			return distances[a] < distances[b]
		a_parcourir.sort_custom(distance_sort)
		var connected = {}
		for node in river_nodes.elements():
			connected[node] = true
			
		while len(a_parcourir) != 0:
			var node = a_parcourir.pop_front()
			var unconnected_river_neighbors = []
			for neighbor in TERRAIN_TILEMAP.get_surrounding_cells(node):
				if not (neighbor in connected) and tileset.get_tile_name(TERRAIN_TILEMAP.get_cell_atlas_coords(neighbor)) == "river":
					unconnected_river_neighbors.append(neighbor)
			for neighbor in unconnected_river_neighbors:
				terrain_tile_nodes[neighbor] = terrain_tile_nodes[node]
				connected[neighbor] = true
				a_parcourir.append(neighbor)

func save_game(directory: String = "saves"):
	var game_data_json = JSON.stringify({
		"nodes": nodes, 
		"arcs": arcs,
		"terrain_tile_nodes": terrain_tile_nodes,
		"tile_nodes": tile_nodes,
		"terrain_tiles": terrain_tiles,
		"tiles": tiles,
		"input_data_paths": input_data_paths
	}, "\t")
	
	var time = Time.get_datetime_dict_from_system()
	var save_filename = "save_%04d%02d%02d_%02d%02d%02d.json" % [time.year, time.month, time.day, time.hour, time.minute, time.second]
	var save_filepath = "user://%s/%s" % [directory, save_filename]
	var user_dir = DirAccess.open("user://")
	if not user_dir.dir_exists(directory):
		print("'%s' folder does not exist, creating it" % directory)
		user_dir.make_dir(directory)
	var file = FileAccess.open(save_filepath, FileAccess.WRITE)
	if file != null:
		file.store_string(game_data_json)
		file = null  # Explicitly close the file
		print("Successfully saved game data to %s" % ProjectSettings.globalize_path(save_filepath))
	else:
		print("Error opening file for writing")
		return
		
	return save_filepath

func load_saved_game():
	# TODO
	pass


func add_building(coords: Vector2i, tile_name: String):
	CONSTRUCTION_TILEMAP.set_cell(coords, 0, tileset.get_atlas_coords(tile_name))
	var building_type = tile_name.split("_")[0] # e.g. wwtw or fwtw
	tiles[coords] = tile_name
	var neighbors_of_same_type = Set.new([])
	for neighbor in CONSTRUCTION_TILEMAP.get_surrounding_cells(coords):
		if neighbor in tile_nodes and tile_nodes[neighbor].split("_")[0] == building_type:
			var main_building_already_exists = false
			for tile in nodes[tile_nodes[neighbor]]["tiles"]:
				if "_main" in tileset.get_tile_name(CONSTRUCTION_TILEMAP.get_cell_atlas_coords(tile)):
					main_building_already_exists = true
			if not ("main" in tile_name and main_building_already_exists):
				neighbors_of_same_type.add(tile_nodes[neighbor])
	neighbors_of_same_type = neighbors_of_same_type.elements()
	
	# Find a node name that is not already in use
	var i = 0
	var node_name = building_type + "_%s" % i
	while node_name in nodes:
		i += 1
		node_name = building_type + "_%s" % i
	
	print("neighbors same type", neighbors_of_same_type)
	if len(neighbors_of_same_type) == 0: # create new node
		nodes[node_name] = {
			"tiles": [coords],
			"attributes": default_attributes[building_type]
		}
		tile_nodes[coords] = node_name
		if building_type in ["fwtw", "wwtw"]:
			for tile in TERRAIN_TILEMAP.get_surrounding_cells(coords):
				if tile in terrain_tile_nodes:
					print(terrain_tile_nodes[tile])
				if tile in terrain_tile_nodes and terrain_tile_nodes[tile].begins_with("river"):
					if building_type == "fwtw":
						add_arc_if_possible(terrain_tile_nodes[tile], node_name)
					if building_type == "wwtw":
						add_arc_if_possible(node_name, terrain_tile_nodes[tile])
					break
		print("create new node: ", node_name)
	elif len(neighbors_of_same_type) == 1 or building_type not in mergeable_building_types: # append tile to existing node
		var neighbor_node = neighbors_of_same_type[0]
		nodes[neighbor_node]["tiles"].append(coords)
		tile_nodes[coords] = neighbor_node
		print("append tile to existing node: ", neighbor_node)
	else : # (len(neighbors_of_same_type) > 1 and building_type in mergeable_building_types) merge the neighbor nodes and append
		var all_tiles = [] # merge the tiles of all the neighbor nodes of same type
		var previous_nodes = []
		for neighbor_node in neighbors_of_same_type:
			all_tiles.append_array(nodes[neighbor_node]["tiles"])
			previous_nodes.append(neighbor_node)
			for tile in nodes[neighbor_node]["tiles"]:
				tile_nodes[tile] = node_name
		nodes[node_name] = {
			"tiles": all_tiles,
			"attributes": default_attributes[building_type]
		}
		tile_nodes[coords] = node_name
		print("merge nodes ", previous_nodes," -> ", node_name)
		
		# Erase former nodes and rename nodes in arcs accordingly
		for node in previous_nodes:
			nodes.erase(node)
			for arc in arcs:
				if node in arc:
					var new_arc_name = arc.replace(node+"_", node_name+"_").replace("_"+node, "_"+node_name)
					arcs[new_arc_name] = arcs[arc]
					if arcs[new_arc_name]["from"] == node:
						arcs[new_arc_name]["from"] = node_name
					if arcs[new_arc_name]["to"] == node:
						arcs[new_arc_name]["to"] = node_name
					arcs.erase(arc)
	if show_arcs:
		display_arcs()

func remove_node(node_name: String):
	print("remove node: ", node_name)
	# Remove node and all associated arcs
	# Clear all tiles
	pass # TODO

func open_node_editor(node_name: String) -> void:
	# TODO : select list for catchment input_data_path
	var attributes = nodes[node_name]["attributes"]
	# Create the popup panel
	var popup = PopupPanel.new()
	popup.size = Vector2(256, 0)
	
	# Create the main container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)
	
	# Add title
	var title = Label.new()
	title.text = "Node settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	
	# Dictionary to store input controls by attribute name
	var input_controls = {}
	
	# Create input fields for each attribute
	for attr_name in attributes.keys():
		# Label
		var label = Label.new()
		label.text = attr_name + ":"
		vbox.add_child(label)
		
		# Input field
		var input = LineEdit.new()
		input.text = str(attributes[attr_name])
		vbox.add_child(input)
		input_controls[attr_name] = input
	
	# Add spacing
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	# Add OK button
	var ok_button = Button.new()
	ok_button.text = "OK"
	vbox.add_child(ok_button)
	
	# Connect button signal to handle submission
	ok_button.pressed.connect(func():
		var new_attributes = {}
		for attr_name in input_controls.keys():
			var value = input_controls[attr_name].text
			# Try to convert to appropriate type based on original type
			var original_value = attributes[attr_name]
			if original_value is float or original_value is int:
				if value.is_valid_float():
					new_attributes[attr_name] = float(value)
				else:
					new_attributes[attr_name] = value
			elif original_value is Dictionary:
				var parsed_value = JSON.parse_string(value)
				if parsed_value == null:
					new_attributes[attr_name] = original_value
				else:
					new_attributes[attr_name] = parsed_value
			else:
				new_attributes[attr_name] = value
		
		nodes[node_name]["attributes"] = new_attributes
		popup.queue_free()
	)
	
	# Add popup to scene tree and display it
	add_child(popup)
	popup.popup_centered()

func add_arc_if_possible(node_from: String, node_to: String):
	if node_from != node_to:
		var arc_name = "%s_to_%s" % [node_from, node_to]
		var arc_name_reversed = "%s_to_%s" % [node_to, node_from]
		if arc_name not in arcs and arc_name_reversed not in arcs: # if the arc does not already exist
			var attributes = {}
			var arc_type = "%s_to_%s" % [node_from.split("_")[0], node_to.split("_")[0]]
			
			if arc_type not in default_attributes: # arc not valid
				print("This arc is not valid")
				return
			
			attributes = default_attributes[arc_type]
				
			arcs[arc_name] = {
				"from": node_from,
				"to": node_to,
				"attributes": attributes
			}
			#arcs_from.get_or_add(node_from, []).append(arc_name)
			#arcs_to.get_or_add(node_to, []).append(arc_name)
			
			print("Created arc %s:" % arc_name, arcs[arc_name])
			return true
	return false

func remove_arc_if_possible(node_from: String, node_to: String):
	# TODO
	print("remove arc if possible: ", node_from, " -> ", node_to)

func find_angle_path(start: Vector2i, end: Vector2i):
	var path = [start]
	
	if end[1] > start[1]:
		for k in range(start[1]+1, end[1]+1):
			path.append(Vector2i(start[0], k))
	else:
		for k in range(start[1]-1, end[1]-1, -1):
			path.append(Vector2i(start[0], k))
	
	if end[0] > start[0]:
		for k in range(start[0]+1, end[0]+1):
			path.append(Vector2i(k, end[1]))
	else:
		for k in range(start[0]-1, end[0]-1, -1):
			path.append(Vector2i(k, end[1]))

	return path

func load_tilemaps_from_tile_dicts():
	for tile in terrain_tiles:
		TERRAIN_TILEMAP.set_cell(tile, 0, tileset.get_atlas_coords(terrain_tiles[tile]))
	for tile in tiles:
		CONSTRUCTION_TILEMAP.set_cell(tile, 0, tileset.get_atlas_coords(tiles[tile]))

func display_arcs():
	clear_arcs()
	
	var arcs_shader = load(ARCS_SHADER_PATH)
	var arcs_material = ShaderMaterial.new()
	arcs_material.shader = arcs_shader
	
	for arc in arcs:
		var arc_tilemap = TileMapLayer.new()
		arc_tilemap.tile_set=OVERLAY_TILEMAP.tile_set
		arc_tilemap.position=OVERLAY_TILEMAP.position
		arc_tilemap.material=arcs_material
		arc_tilemap.z_index = 2
		arcs_tilemaps.add_child(arc_tilemap)
		
		var path = find_angle_path(nodes[arcs[arc]["from"]]["tiles"][0], nodes[arcs[arc]["to"]]["tiles"][0])
		
		# Start
		arc_tilemap.set_cell(path[0], 0, tileset.get_atlas_coords("arcArrowStart_%s" % (path[1]-path[0])))
		
		for i in range(1, len(path)-1):
			if (path[i]-path[i-1]) != (path[i+1]-path[i]):
				arc_tilemap.set_cell(path[i], 0, tileset.get_atlas_coords("arcArrow_%s_%s" % [(path[i]-path[i-1]),(path[i+1]-path[i])]))
			else:
				arc_tilemap.set_cell(path[i], 0, tileset.get_atlas_coords("arcArrow_%s" % (path[i+1]-path[i])))
		# End
		arc_tilemap.set_cell(path[-1], 0, tileset.get_atlas_coords("arcArrowEnd_%s" % (path[-1]-path[-2])))

func clear_arcs():
	for child in arcs_tilemaps.get_children():
		if child is TileMapLayer:
			child.clear()

# ---

func _ready():
	print("Ready")

	OVERLAY_TILEMAP.clear()
	var overlay_shader = load(OVERLAY_SHADER_PATH)
	var overlay_material = ShaderMaterial.new()
	overlay_material.shader = overlay_shader
	overlay_material.set_shader_parameter("opacity", 0.5)
	OVERLAY_TILEMAP.material = overlay_material
	
	# TODO : add the ability to load save from json file
	load_terrain_from_default_tilemap()	
	
	print(nodes)
	# TODO : save dicts in json file to be able to save game progression
	load_tilemaps_from_tile_dicts()

enum State { IDLE, CREATE_ARC, CREATE_BUILDING, REMOVE_BUILDING, REMOVE_ARC }
var show_arcs = false
var current_state = { "type": State.IDLE }
var hovered_cell = null

func _input(event):
	var mouse_pos = TERRAIN_TILEMAP.get_local_mouse_position()
	var new_hovered_cell = TERRAIN_TILEMAP.local_to_map(mouse_pos)
	
	if current_state["type"] == State.IDLE:
		# Overlay over hovered buildings and catchments
		if not (new_hovered_cell == hovered_cell):
			OVERLAY_TILEMAP.clear()
			if new_hovered_cell in tile_nodes:
				for tile in nodes[tile_nodes[new_hovered_cell]]["tiles"]:
					OVERLAY_TILEMAP.set_cell(tile, 0, tileset.get_atlas_coords(tiles[tile]))
			if new_hovered_cell in terrain_tile_nodes and terrain_tile_nodes[new_hovered_cell].split("_")[0] == "catchment":
				OVERLAY_TILEMAP.set_cell(new_hovered_cell, 0, tileset.get_atlas_coords(terrain_tiles[new_hovered_cell]))
		
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if new_hovered_cell in tile_nodes:
				open_node_editor(tile_nodes[new_hovered_cell])
			elif new_hovered_cell in terrain_tile_nodes and terrain_tile_nodes[new_hovered_cell].split("_")[0] == "catchment":
				open_node_editor(terrain_tile_nodes[new_hovered_cell])
	
	if current_state["type"] == State.CREATE_BUILDING:
		# The terrain is available if there is no building on the terrain and the terrain is not a river
		var terrain_available = new_hovered_cell in terrain_tiles and new_hovered_cell not in tile_nodes and \
				not (new_hovered_cell in terrain_tiles and terrain_tiles[new_hovered_cell].split("_")[0] in ["river", "catchment", "outlet"])
		
		# Constraints
		if current_state["attributes"]["tile_name"] in ["fwtw_main", "wwtw_main"]:
			var has_river_neighbor = false
			for neighbor_tile in TERRAIN_TILEMAP.get_surrounding_cells(new_hovered_cell):
				if neighbor_tile in terrain_tiles and terrain_tiles[neighbor_tile] == "river":
					has_river_neighbor = true
			if !has_river_neighbor:
				terrain_available = false
		if current_state["attributes"]["tile_name"].split("_")[0] in ["wwtw", "fwtw"] and not current_state["attributes"]["tile_name"].split("_")[1] == "main":
			var has_main_building_neighbor = false
			for neighbor_tile in CONSTRUCTION_TILEMAP.get_surrounding_cells(new_hovered_cell):
				if neighbor_tile in tile_nodes:
					for tile in nodes[tile_nodes[neighbor_tile]]["tiles"]:
						if tileset.get_tile_name(CONSTRUCTION_TILEMAP.get_cell_atlas_coords(tile)) == current_state["attributes"]["tile_name"].split("_")[0]+"_main":
							has_main_building_neighbor = true
			if not has_main_building_neighbor:
				terrain_available = false
					
		# Overlay over available terrain
		if not (new_hovered_cell == hovered_cell):
			OVERLAY_TILEMAP.clear()
			if terrain_available:
				OVERLAY_TILEMAP.set_cell(new_hovered_cell, 0, tileset.get_atlas_coords(current_state["attributes"]["tile_name"]))
		
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
			and terrain_available:
			add_building(new_hovered_cell, current_state["attributes"]["tile_name"])
			current_state = { "type": State.IDLE }
			OVERLAY_TILEMAP.clear()
	
	if current_state["type"] == State.REMOVE_BUILDING:
		# Overlay over hovered buildings and catchments
		if not (new_hovered_cell == hovered_cell):
			OVERLAY_TILEMAP.clear()
			if new_hovered_cell in tile_nodes:
				for tile in nodes[tile_nodes[new_hovered_cell]]["tiles"]:
					OVERLAY_TILEMAP.set_cell(tile, 0, tileset.get_atlas_coords(tiles[tile]))
		# Handle click
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if new_hovered_cell in tile_nodes:
				remove_node(tile_nodes[new_hovered_cell])
			current_state = { "type": State.IDLE }
	
	if current_state["type"] in [State.CREATE_ARC, State.REMOVE_ARC]:
		# Overlay over hovered buildings
		if not (new_hovered_cell == hovered_cell):
			OVERLAY_TILEMAP.clear()
			if new_hovered_cell in tile_nodes:
				for tile in nodes[tile_nodes[new_hovered_cell]]["tiles"]:
					OVERLAY_TILEMAP.set_cell(tile, 0, tileset.get_atlas_coords(tiles[tile]))
		
		# Overlay over selected "from" building
		if current_state["attributes"]["from"] != null:
			for tile in nodes[current_state["attributes"]["from"]]["tiles"]:
				OVERLAY_TILEMAP.set_cell(tile, 0, tileset.get_atlas_coords(tiles[tile]))
		
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if new_hovered_cell in tile_nodes:
				if current_state["attributes"]["from"] == null: # first click
					current_state["attributes"]["from"] = tile_nodes[new_hovered_cell]
				elif current_state["attributes"]["to"] == null: # second click
					current_state["attributes"]["to"] = tile_nodes[new_hovered_cell]
			if current_state["attributes"]["from"] != null and current_state["attributes"]["to"] != null:
				match current_state["type"]:
					State.CREATE_ARC:
						add_arc_if_possible(current_state["attributes"]["from"], current_state["attributes"]["to"])
					State.REMOVE_ARC:
						remove_arc_if_possible(current_state["attributes"]["from"], current_state["attributes"]["to"])
				if show_arcs:
					display_arcs()
				current_state = { "type": State.IDLE }
				OVERLAY_TILEMAP.clear()
	
	hovered_cell = new_hovered_cell

func _on_fwtw_main_pressed() -> void:
	current_state = {
		"type": State.CREATE_BUILDING,
		"attributes": { "tile_name": "fwtw_main" }
	}

func _on_wwtw_main_pressed() -> void:
	current_state = {
		"type": State.CREATE_BUILDING,
		"attributes": { "tile_name": "wwtw_main" }
	}

func _on_wwtw_1_pressed() -> void:
	current_state = {
		"type": State.CREATE_BUILDING,
		"attributes": { "tile_name": "wwtw_1" }
	}

func _on_residential_1_pressed() -> void:
	current_state = {
		"type": State.CREATE_BUILDING,
		"attributes": { "tile_name": "residential_1" }
	}

func _on_remove_building_pressed() -> void:
	current_state = {
		"type": State.REMOVE_BUILDING
	}

func _on_show_arcs_toggled(toggled_on: bool) -> void:
	show_arcs = toggled_on
	if show_arcs:
		display_arcs()
	else:
		clear_arcs()

func _on_create_arc_pressed() -> void:
	current_state = {
		"type": State.CREATE_ARC,
		"attributes": {
			"from": null,
			"to": null
		}
	}

func _on_remove_arc_pressed() -> void:
	current_state = {
		"type": State.REMOVE_ARC,
		"attributes": {
			"from": null,
			"to": null
		}
	}

func _on_sewer_settings_pressed() -> void:
	open_node_editor("sewer")

func _on_land_settings_pressed() -> void:
	open_node_editor("land")

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _on_run_simulation_pressed() -> void:
	print("Run simulation")
	var initial_run_simulation_button_text = run_simulation_button.text
	run_simulation_button.text = "..."
	await wait(1e-3) # wait a bit to let the button change its text
	
	var save_filepath = save_game("simulations_input")
	# Wait a bit to ensure file is written
	await get_tree().process_frame
	
	var save_filepath_absolute = ProjectSettings.globalize_path(save_filepath)
	var output_dir = ProjectSettings.globalize_path("user://outputs/%s" % save_filepath.get_file().get_slice(".",0))
	var python_script = ProjectSettings.globalize_path("res://scripts/python/run_simulation.py")
	
	var logs = []
	var exit_code = OS.execute("python", [python_script, save_filepath_absolute, output_dir], logs)
	
	print(logs)
	
	# TODO : Error/warning messages
	# nowhere for sludge to go -> means arc is missing between fwtw and wwtw
	
	if exit_code != 0:
		print("Failed to run the python simulation script: ", logs)
		return
	
	print("Success")
	
	run_simulation_button.text = initial_run_simulation_button_text

	#var image = Image.new()
	#var error = image.load(output_image)
	#
	#if error != OK:
		#print("Error loading image: ", error)
		#return
	#
	##var texture = ImageTexture.create_from_image(image)
	##var sprite = Sprite2D.new()
	##sprite.texture = texture
	##sprite.position.x = 640
	##sprite.position.y = 360
	##sprite.z_index = 1000
	##add_child(sprite)
	#
	#print("Image displayed!")
	pass # Replace with function body.
