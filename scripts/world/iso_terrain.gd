class_name IsoTerrain
extends TileMapLayer
## Isometric ground layer built from the PixelLab terrain atlas.
##
## Cells are 64x32 (true 2:1 diamonds). Each terrain texture is 64x64: its top
## face is an exact 64x32 diamond centred at (32, 38) with ~10 px of earth side
## below (see assets/tiles/terrain/terrain.json). `texture_origin` shifts the
## texture so that top face sits exactly on the cell diamond.

enum Terrain { GRASS, GRASS_FLOWERS, DIRT, COBBLESTONE }

const ATLAS := preload("res://assets/tiles/terrain/terrain_atlas.png")
const TEXTURE_SIZE := Vector2i(64, 64)
const TOP_FACE_CENTER := Vector2i(32, 38)
const SOURCE_ID := 0


func _init() -> void:
	tile_set = _build_tile_set()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func _build_tile_set() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Iso.TILE_SIZE

	var src := TileSetAtlasSource.new()
	src.texture = ATLAS
	src.texture_region_size = TEXTURE_SIZE
	# Texture is drawn centred on the cell, then moved by -texture_origin.
	var origin := TOP_FACE_CENTER - TEXTURE_SIZE / 2
	for i in Terrain.size():
		var coords := Vector2i(i, 0)
		src.create_tile(coords)
		src.get_tile_data(coords, 0).texture_origin = origin
	ts.add_source(src, SOURCE_ID)
	return ts


func set_terrain(cell: Vector2i, terrain: Terrain) -> void:
	set_cell(cell, SOURCE_ID, Vector2i(terrain, 0))


## Fills a small deterministic test map: grass field, two dirt paths along the
## grid axes and a cobblestone plaza in the middle.
func build_test_map(size: int = 16) -> void:
	clear()
	var mid := size / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in size:
		for x in size:
			var cell := Vector2i(x, y)
			var t := Terrain.GRASS
			if rng.randf() < 0.18:
				t = Terrain.GRASS_FLOWERS
			if x == mid or y == mid:
				t = Terrain.DIRT
			if absi(x - mid) <= 1 and absi(y - mid) <= 1:
				t = Terrain.COBBLESTONE
			set_terrain(cell, t)


func cell_center(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))
