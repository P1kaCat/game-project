class_name IsoTerrain
extends TileMapLayer
## Walkable isometric ground. Builds the test map and a collision boundary along
## the map's outer diamond so the player cannot walk off the ground.

const Terrain := TerrainTileSet.Terrain

var map_size := 0


func _init() -> void:
	tile_set = TerrainTileSet.get_tile_set()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_terrain(cell: Vector2i, terrain: int) -> void:
	set_cell(cell, TerrainTileSet.SOURCE_ID, Vector2i(terrain, 0), TerrainTileSet.GROUND)


## Deterministic test map: grass field, two dirt paths along the grid axes and a
## cobblestone plaza in the middle. Also (re)builds the edge collision.
func build_test_map(size: int = 16) -> void:
	clear()
	map_size = size
	var mid := size / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in size:
		for x in size:
			var t: int = Terrain.GRASS
			if rng.randf() < 0.18:
				t = Terrain.GRASS_FLOWERS
			if x == mid or y == mid:
				t = Terrain.DIRT
			if absi(x - mid) <= 1 and absi(y - mid) <= 1:
				t = Terrain.COBBLESTONE
			set_terrain(Vector2i(x, y), t)
	_build_boundary()


func cell_center(cell: Vector2i) -> Vector2:
	return to_global(map_to_local(cell))


func cell_at(world_pos: Vector2) -> Vector2i:
	return local_to_map(to_local(world_pos))


func is_ground(cell: Vector2i) -> bool:
	return get_cell_source_id(cell) != -1


## Outer corners of the (square, diamond-shaped) map in local coordinates.
func map_corners() -> PackedVector2Array:
	var hx := Iso.TILE_SIZE.x / 2.0
	var hy := Iso.TILE_SIZE.y / 2.0
	var last := map_size - 1
	return PackedVector2Array([
		map_to_local(Vector2i(0, 0)) + Vector2(0, -hy),        # top
		map_to_local(Vector2i(last, 0)) + Vector2(hx, 0),      # right
		map_to_local(Vector2i(last, last)) + Vector2(0, hy),   # bottom
		map_to_local(Vector2i(0, last)) + Vector2(-hx, 0),     # left
	])


func _build_boundary() -> void:
	var old := get_node_or_null(^"Boundary")
	if old:
		old.free()
	var body := StaticBody2D.new()
	body.name = "Boundary"
	add_child(body)
	var c := map_corners()
	for i in c.size():
		var seg := SegmentShape2D.new()
		seg.a = c[i]
		seg.b = c[(i + 1) % c.size()]
		var shape := CollisionShape2D.new()
		shape.shape = seg
		body.add_child(shape)
