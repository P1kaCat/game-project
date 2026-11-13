class_name TerrainTileSet
extends RefCounted
## Builds (once) the isometric TileSet for the PixelLab terrain atlas.
##
## Cells are 64x32 (true 2:1 diamonds). Each terrain texture is 64x64: its top
## face is an exact 64x32 diamond centred at (32, 38) with ~10 px of earth side
## below (assets/tiles/terrain/terrain.json).
##
## Every terrain has two variants in the same atlas source:
##   alternative 0 = GROUND : top face drawn on the cell, no collision
##   alternative 1 = RAISED : same art lifted by its side height (a 1-step
##                            block), with a diamond collision polygon
## so solid obstacles reuse the existing art instead of needing new sprites.

enum Terrain { GRASS, GRASS_FLOWERS, DIRT, COBBLESTONE }

const GROUND := 0
const RAISED := 1
const SOURCE_ID := 0
const SOLID_PHYSICS_LAYER := 0

const ATLAS := preload("res://assets/tiles/terrain/terrain_atlas.png")
const TEXTURE_SIZE := Vector2i(64, 64)
const TOP_FACE_CENTER := Vector2i(32, 38)
## Visible earth side below the top face; lifting by this much makes a block.
const STEP_HEIGHT := 10

static var _cached: TileSet


static func get_tile_set() -> TileSet:
	if _cached == null:
		_cached = _build()
	return _cached


static func _build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Iso.TILE_SIZE
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(SOLID_PHYSICS_LAYER, 1)

	var half := Vector2(Iso.TILE_SIZE) / 2.0
	var diamond := PackedVector2Array([
		Vector2(0, -half.y), Vector2(half.x, 0), Vector2(0, half.y), Vector2(-half.x, 0)])

	var src := TileSetAtlasSource.new()
	src.texture = ATLAS
	src.texture_region_size = TEXTURE_SIZE
	ts.add_source(src, SOURCE_ID)
	# Textures are drawn centred on the cell, then moved by -texture_origin.
	var origin := TOP_FACE_CENTER - TEXTURE_SIZE / 2
	for i in Terrain.size():
		var coords := Vector2i(i, 0)
		src.create_tile(coords)
		src.get_tile_data(coords, GROUND).texture_origin = origin
		var alt := src.create_alternative_tile(coords, RAISED)
		var raised := src.get_tile_data(coords, alt)
		raised.texture_origin = origin + Vector2i(0, STEP_HEIGHT)
		raised.add_collision_polygon(SOLID_PHYSICS_LAYER)
		raised.set_collision_polygon_points(SOLID_PHYSICS_LAYER, 0, diamond)
	return ts
