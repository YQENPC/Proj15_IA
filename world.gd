extends Node2D

func flatten_array(arr: Array[Array]):
	var flattened_array: Array = []
	for sub_arr in arr:
		for item in sub_arr:
			flattened_array.append(item)
	return flattened_array

@onready var TERRAIN_TILEMAP: TileMapLayer = $city_builder/terrain
@onready var CONSTRUCTION_TILEMAP: TileMapLayer = $city_builder/construction
@onready var OVERLAY_TILEMAP: TileMapLayer = $city_builder/overlay
@onready var arcs_tilemaps: Node = $city_builder/arcs_tilemaps # Arcs tilemaps will be placed under this node

const OVERLAY_SHADER_PATH = "res://overlay.gdshader"

var TilesetClass = load("res://tileset.gd") # imports the class Tileset
var SetClass = load("res://set.gd") # imports the class Set

const INF = 1_000_000_000_000 # represents +infinity

var nodes: Dictionary = {}

var arcs: Dictionary = {}
var arcs_from: Dictionary = {} # node -> array of arcs (arcs going from node)
var arcs_to: Dictionary = {} # node -> array of arcs (arcs going to node)

var terrain_tile_nodes = {} # cell coords -> terrain node name ("river_xxx" or "urbanLand" or "ruralLand")
var tile_nodes = {} # cell coords -> node name (e.g. "wwtw_0")
var terrain_tiles = {} # cell coords -> terrain tile name (e.g. "river", "ruralLand")
var tiles = {} # cell coords -> tile name (e.g. "wwtw_main")

var tileset = Tileset.new([
	["wwtw_main", Vector2i(0,0)],
	["wwtw_0", Vector2i(1,0)],
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

const default_attributes = { # must be intensive values (i.e. per tile values), it's easier that way
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
	"ruralLand": {
		"area": 1e5,
		"initial_storage": 5e4,
		"field_capacity": 0.3,
		"depth": 0.5
	},
	"urbanLand": {
		"area": 1e5,
		"initial_storage": 5e4
	},
	"catchment": {},
	"outlet": {},
	
	### Arcs ###
	"river_to_fwtw": {
		"capacity": 5e4
	}
}

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
	nodes["ruralLand"] = { "tiles": [], "attributes": default_attributes["ruralLand"]}
	nodes["urbanLand"] = { "tiles": [], "attributes": default_attributes["urbanLand"]}
	
	var catchments = []
	var outlets = []
	
	### Land, catchments and outlets ###
	
	for cell in used_cells:
		var tile_name = tileset.get_tile_name(TERRAIN_TILEMAP.get_cell_atlas_coords(cell))
		terrain_tiles[cell] = tile_name
		if tile_name in ["ruralLand", "urbanLand"]:
			nodes[tile_name]["tiles"].append(cell)
			terrain_tile_nodes[cell] = tile_name
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
		for catchment_ in catchments:
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
			for n in range(len(branch)):
				var node = branch[n]
				var node_name = "river_%s_%s_%s" % [r, b, n]
				nodes[node_name] = { "tiles": [node] }
				terrain_tile_nodes[node] = node_name
				
				# TODO: create arcs (temporary arcs, will be simplified before exporting to python)
		
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
		var a_parcourir = river_nodes.difference(Set.new(catchments)).elements()
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

func add_building(coords: Vector2i, tile_name: String):
	CONSTRUCTION_TILEMAP.set_cell(coords, 0, tileset.get_atlas_coords(tile_name))
	var building_type = tile_name.split("_")[0] # e.g. wwtw or fwtw
	tiles[coords] = tile_name
	var neighbors_of_same_type = []
	for neighbor in CONSTRUCTION_TILEMAP.get_surrounding_cells(coords):
		if neighbor in tile_nodes and tile_nodes[neighbor].split("_")[0] == building_type:
			neighbors_of_same_type.append(neighbor)
	
	# Find a node name that is not already in use
	var i = 0
	var node_name = building_type + "_%s" % i
	while node_name in nodes:
		i += 1
		node_name = building_type + "_%s" % i
	
	if len(neighbors_of_same_type) == 0: # create new node
		nodes[node_name] = {
			"tiles": [coords],
			"attributes": default_attributes[building_type]
		}
		tile_nodes[coords] = node_name
	if len(neighbors_of_same_type) == 1: # append tile to existing node
		var neighbor = neighbors_of_same_type[0]
		nodes[tile_nodes[neighbor]]["tiles"].append(coords)
		tile_nodes[coords] = tile_nodes[neighbor] 
	if len(neighbors_of_same_type) > 1: # merge the neighbor nodes and append
		var all_tiles = [] # merge the tiles of all the neighbor nodes of same type
		for neighbor in neighbors_of_same_type:
			all_tiles.append_array(nodes[tile_nodes[neighbor]]["tiles"])
			tile_nodes[neighbor] = node_name
			# TODO : renommer tous les arcs dans le dictionnaire arcs
		nodes[node_name] = {
			"tiles": all_tiles,
			"attributes": default_attributes[building_type]
		}
		tile_nodes[coords] = node_name

func add_arc_if_possible(node_from: String, node_to: String):
	if node_from != node_to:
		var arc_name = "%s_to_%s" % [node_from, node_to]
		var arc_name_reversed = "%s_to_%s" % [node_to, node_from]
		if arc_name not in arcs and arc_name_reversed not in arcs: # if the arc does not already exist
			var attributes = {}
			var arc_type = "%s_to_%s" % [node_from.split("_")[0], node_to.split("_")[0]]
			if arc_type in default_attributes:
				attributes = default_attributes[arc_type]
				
			arcs[arc_name] = {
				"from": node_from,
				"to": node_to,
				"attributes": attributes
			}
			arcs_from.get_or_add(arc_name, []).append(node_from)
			arcs_to.get_or_add(arc_name, []).append(node_to)
			
			print("Created arc %s:" % arc_name, arcs[arc_name])
			return true
	return false

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
	
	for arc in arcs:
		var arc_tilemap = TileMapLayer.new()
		arc_tilemap.tile_set=OVERLAY_TILEMAP.tile_set
		arc_tilemap.position=OVERLAY_TILEMAP.position
		arc_tilemap.material=OVERLAY_TILEMAP.material
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
	
	add_building(Vector2i(2,-1), "wwtw_main")
	
	
	# TODO : save dicts in json file to be able to save game progression
	load_tilemaps_from_tile_dicts()

enum State { IDLE, CREATE_ARC, CREATE_BUILDING }
var show_arcs = false
var current_state = { "type": State.IDLE }
var hovered_cell = null

func _input(event):
	var mouse_pos = TERRAIN_TILEMAP.get_local_mouse_position()
	var new_hovered_cell = TERRAIN_TILEMAP.local_to_map(mouse_pos)
	
	if current_state["type"] == State.CREATE_BUILDING:
		# The terrain is available if there is no building on the terrain and the terrain is not a river
		var terrain_available = new_hovered_cell in terrain_tiles and new_hovered_cell not in tile_nodes and \
				not (new_hovered_cell in terrain_tiles and terrain_tiles[new_hovered_cell].split("_")[0] in ["river", "catchment", "outlet"])
		
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

	if current_state["type"] == State.CREATE_ARC:
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
		
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
			and new_hovered_cell in tile_nodes:
			if current_state["attributes"]["from"] == null: # first click
				current_state["attributes"]["from"] = tile_nodes[new_hovered_cell]
			elif current_state["attributes"]["to"] == null: # second click
				current_state["attributes"]["to"] = tile_nodes[new_hovered_cell]
				add_arc_if_possible(current_state["attributes"]["from"], current_state["attributes"]["to"])
				if show_arcs:
					display_arcs()
				current_state = { "type": State.IDLE }
				OVERLAY_TILEMAP.clear()
	
	hovered_cell = new_hovered_cell

func _on_create_arc_pressed() -> void:
	current_state = {
		"type": State.CREATE_ARC,
		"attributes": {
			"from": null,
			"to": null
		}
	}

func _on_residential_1_pressed() -> void:
	current_state = {
		"type": State.CREATE_BUILDING,
		"attributes": { "tile_name": "residential_1" }
	}

func _on_show_arcs_toggled(toggled_on: bool) -> void:
	show_arcs = toggled_on
	if show_arcs:
		display_arcs()
	else:
		clear_arcs()
	
	
		
	#var data_json = JSON.stringify({"nodes": nodes, "arcs": arcs})
#
	#var file = FileAccess.open("user://data.json", FileAccess.WRITE)
#
	#if file != null:
		#file.store_string(data_json)
		#file = null  # Explicitly close the file
	#else:
		#print("Error opening file for writing")
		#return
#
	## Wait a bit to ensure file is written
	#await get_tree().process_frame
#
	## Now execute the Python script
	#var json_file = OS.get_user_data_dir() + "/data.json"
	#var output_image = OS.get_user_data_dir() + "/plot.png"
	#var python_script = ProjectSettings.globalize_path("res://scripts/process_data.py")
#
	#var output = []
	#var exit_code = OS.execute("python", [python_script, json_file, output_image], output)
#
	#if exit_code != 0:
		#print("Error generating plot: ", output)
		#return
	#
	#print("Plot generated successfully")
	#
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
