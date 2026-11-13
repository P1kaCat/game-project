class_name RuneRing
extends Control
## Pixel rune glyphs circling an ellipse and drifting upward (the exile ritual
## of the opening cinematic). Drawn pixel by pixel, no textures, no shaders.
## Positions are in the parent's pixels; `intensity` 0..1 fades it in / out.

var center := Vector2.ZERO
var radius := Vector2(80, 24)
var count := 18
var speed := 0.25          # turns per second (radians * TAU)
var rise := 10.0           # px/s upward drift of each glyph
var color := Color(0.92, 0.95, 1.0)
var intensity := 0.0:
	set(v):
		intensity = v
		queue_redraw()

var _t := 0.0
var _glyphs: Array = []    # each: Array of Vector2i pixels (3x5 cell)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 1307
	for i in 12:
		var g := []
		for y in 5:
			for x in 3:
				if rng.randf() < 0.45 or (x == 1 and (y == 0 or y == 4)):
					g.append(Vector2i(x, y))
		_glyphs.append(g)


func _process(delta: float) -> void:
	_t += delta
	if intensity > 0.0:
		queue_redraw()


func _draw() -> void:
	if intensity <= 0.0:
		return
	for i in count:
		var a := TAU * float(i) / count + _t * speed * TAU
		var lift := fposmod(_t * rise + i * 7.3, 34.0)
		var p := center + Vector2(cos(a) * radius.x, sin(a) * radius.y - lift)
		# glyphs behind the circle (top half) are dimmer; all fade as they rise
		var depth := 0.55 + 0.45 * (sin(a) * 0.5 + 0.5)
		var alpha := intensity * depth * (1.0 - lift / 34.0)
		var c := Color(color, alpha)
		var g: Array = _glyphs[i % _glyphs.size()]
		for px: Vector2i in g:
			draw_rect(Rect2(p.round() + Vector2(px), Vector2.ONE), c)
