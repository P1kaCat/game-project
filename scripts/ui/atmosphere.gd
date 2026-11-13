class_name Atmosphere
extends RefCounted
## Cheap pixel-art atmosphere shared by the main menu and the cinematic:
## ordered-dither fog layers (no shaders, no alpha gradients: every pixel is
## either fog or not, like hand-placed dithering) and sparse drifting motes.

const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## Seamless (horizontally tiling) dithered noise: `coverage` 0..1 ~ density.
static func fog_texture(w: int, h: int, seed: int, coverage: float, color: Color, vertical_fade := true) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.018
	n.fractal_octaves = 3
	var src := n.get_seamless_image(w, h, false, false, 0.2)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		# fog thins out towards the top and bottom of the band
		var band := 1.0 if not vertical_fade else sin(PI * (y + 0.5) / h)
		for x in w:
			var v := src.get_pixel(x, y).r
			var t := clampf((v - (1.0 - coverage)) * 2.2, 0.0, 1.0) * band
			if t * 16.0 > BAYER4[(y % 4) * 4 + (x % 4)] + 0.5:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


## Soft fog: no checkerboard dithering. Noise in 2x2-pixel clusters with a
## few alpha steps (reads as mist at any screen scale).
static func soft_fog_texture(w: int, h: int, seed: int, coverage: float, color: Color) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 3
	var src := n.get_seamless_image(w / 2, h / 2, false, false, 0.2)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h / 2:
		var band := sin(PI * (y + 0.5) / (h / 2))
		for x in w / 2:
			var t := clampf((src.get_pixel(x, y).r - (1.0 - coverage)) * 2.4, 0.0, 1.0) * band
			var a := floorf(t * 4.0) / 4.0 * color.a   # 0, 25, 50, 75 % of the colour alpha
			if a <= 0.0:
				continue
			var c := Color(color, a)
			img.fill_rect(Rect2i(x * 2, y * 2, 2, 2), c)
	return ImageTexture.create_from_image(img)


## Vertical dithered gradient (transparent -> color), e.g. to fade an
## illustration's edge into the background colour.
static func dither_gradient(w: int, h: int, color: Color, horizontal := false) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var t := (float(x) + 0.5) / w if horizontal else (float(y) + 0.5) / h
			if t * 16.0 > BAYER4[(y % 4) * 4 + (x % 4)] + 0.5:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


## Hides the outer `edge` px of an image with an ordered-dither falloff so it
## melts into a flat background of any size (illustrations shown 1:1).
static func dither_edges(tex: Texture2D, edge: int) -> ImageTexture:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var d := mini(mini(x, w - 1 - x), mini(y, h - 1 - y))
			if d >= edge:
				continue
			var t := float(d) / edge
			if t * 16.0 <= BAYER4[(y % 4) * 4 + (x % 4)] + 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## Slowly drifting motes (dust, embers, ash). Add to any CanvasItem; covers `area`.
static func motes(area: Rect2, amount: int, color: Color, rising := true) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	p.texture = ImageTexture.create_from_image(img)
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = area.size / 2.0
	p.position = area.get_center()
	p.direction = Vector2(0.3, -1.0 if rising else 1.0)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.set_color(1, Color(color, 0.0))
	ramp.add_point(0.2, color)
	ramp.add_point(0.8, Color(color, color.a * 0.6))
	p.color_ramp = ramp
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return p


## A horizontally scrolling, tiling texture band (fog). Pixel-snapped.
class ScrollLayer extends Control:
	var texture: Texture2D
	var speed := 4.0      # px/s, negative = leftwards
	var bob := 0.0        # vertical sway amplitude (px)
	var _x := 0.0
	var _t := 0.0

	func _init(tex: Texture2D, px_per_s: float) -> void:
		texture = tex
		speed = px_per_s
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(delta: float) -> void:
		_x = fposmod(_x + speed * delta, texture.get_width())
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := texture.get_width()
		var y := roundf(sin(_t * 0.4) * bob)
		var x := -roundf(_x)
		while x < size.x:
			draw_texture(texture, Vector2(x, y))
			x += w
