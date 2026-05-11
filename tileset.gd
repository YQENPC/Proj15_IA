class_name Tileset

var _name_to_coords: Dictionary
var _coords_to_name: Dictionary

func _init(tiles: Array) -> void:
	_name_to_coords = {}
	_coords_to_name = {}
	
	for tile in tiles:
		var tile_name: String = tile[0]
		var atlas_coords: Vector2i = tile[1]
		
		_name_to_coords[tile_name] = atlas_coords
		_coords_to_name[atlas_coords] = tile_name

func get_tile_name(atlas_coords: Vector2i) -> String:
	return _coords_to_name.get(atlas_coords, "")

func get_atlas_coords(tile_name: String) -> Vector2i:
	return _name_to_coords.get(tile_name, Vector2i.ZERO)
