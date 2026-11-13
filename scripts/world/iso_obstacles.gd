class_name IsoObstacles
extends TileMapLayer
## Solid, raised terrain blocks (one step high) that y-sort with characters.
## Lives under the y-sorted Entities node; collision comes from the TileSet's
## RAISED alternative tiles.

const Terrain := TerrainTileSet.Terrain


func _init() -> void:
	tile_set = TerrainTileSet.get_tile_set()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled = true


func place_block(cell: Vector2i, terrain: int) -> void:
	set_cell(cell, TerrainTileSet.SOURCE_ID, Vector2i(terrain, 0), TerrainTileSet.RAISED)


func is_blocked(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) != -1


## A few blocks around the plaza to exercise collision and depth sorting.
func build_test_blocks() -> void:
	clear()
	for c: Vector2i in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5)]:
		place_block(c, Terrain.GRASS)
	for c: Vector2i in [Vector2i(11, 12), Vector2i(12, 11)]:
		place_block(c, Terrain.COBBLESTONE)
	place_block(Vector2i(12, 4), Terrain.DIRT)
