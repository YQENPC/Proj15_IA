extends Node2D

@onready var tilemap: TileMapLayer = $test_grid
const GRID_W := 5
const GRID_H := 5
const CELL_SIZE := 32  # set to your tilemap.cell_size.x (pixels)

func _ready():
	var grid_pixel_size = Vector2(GRID_W, GRID_H) * CELL_SIZE
	var vp_size = get_viewport_rect().size
	tilemap.position = (vp_size - grid_pixel_size) * 0.5
	
	var tile_name_to_id = {
		"land_rural": [0, Vector2i(1, 2)],
		"river": [0, Vector2i(0, 10)],
		"road": [0, Vector2i(9, 0)]
	}
	
	var grid = [
		[
			["road"],
			["road"],
			["road"],
			["land_rural"],
			["land_rural"]
		],	
		[
			["road"],
			["river"],
			["river"],
			["river"],
			["river"]
		],
		[
			["river"],
			["river"],
			["river"],
			["river"],
			["river"]
		],
		[
			["road"],
			["road"],
			["road"],
			["land_rural"],
			["land_rural"]
		],
		[
			["road"],
			["road"],
			["land_rural"],
			["land_rural"],
			["land_rural"]
		]
	]
	tilemap.clear()
	
	for y in range(grid.size()):
		var row = grid[y]
		for x in range(row.size()):
			var tile_name = row[x][0]
			if not tile_name_to_id.has(tile_name):                
				continue  # skip unknown types            
			var tile_id = tile_name_to_id[tile_name]
			tilemap.set_cell(Vector2i(x, y), tile_id[0], tile_id[1])
