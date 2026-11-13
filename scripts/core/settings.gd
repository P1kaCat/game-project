class_name Settings
extends RefCounted
## Player settings, persisted in user://settings.cfg (ConfigFile). Static so
## any scene can read them; apply() pushes them to the engine (audio buses,
## window mode, pixel scale, UI scale, language).

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"audio/master": 0.8,
	"audio/music": 0.7,
	"audio/sfx": 0.8,
	"display/fullscreen": false,
	"display/zoom": "normal",
	"display/ui_scale": "normal",
	"gameplay/text_speed": "normal",
	"gameplay/camera_smoothing": "normal",
	"touch/joystick_size": 18.0,
	"touch/joystick_opacity": 0.8,
	"lang/locale": "fr",
}
const CHOICES := {
	"display/zoom": ["close", "normal", "wide"],
	"display/ui_scale": ["normal", "large"],
	"gameplay/text_speed": ["slow", "normal", "fast", "instant"],
	"gameplay/camera_smoothing": ["off", "low", "normal", "high"],
}
const ZOOM_HEIGHT := {"close": 220, "normal": 270, "wide": 320}
const TEXT_CPS := {"slow": 25.0, "normal": 45.0, "fast": 80.0, "instant": 10000.0}
const CAMERA_FOLLOW := {"off": 40.0, "low": 16.0, "normal": 10.0, "high": 6.0}

static var _values := {}
static var _loaded := false


static func get_value(key: String) -> Variant:
	_ensure_loaded()
	return _values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	_values[key] = _sanitize(key, value)


static func load_settings() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key in DEFAULTS:
			var parts: PackedStringArray = key.split("/")
			if cfg.has_section_key(parts[0], parts[1]):
				_values[key] = _sanitize(key, cfg.get_value(parts[0], parts[1]))
	_loaded = true


static func save_settings() -> Error:
	_ensure_loaded()
	var cfg := ConfigFile.new()
	for key in _values:
		var parts: PackedStringArray = key.split("/")
		cfg.set_value(parts[0], parts[1], _values[key])
	return cfg.save(PATH)


## Rejects wrong types / unknown choices / out-of-range numbers (bad or old files).
static func _sanitize(key: String, v: Variant) -> Variant:
	var d: Variant = DEFAULTS.get(key)
	if d == null:
		return v
	if typeof(d) == TYPE_FLOAT:
		if typeof(v) not in [TYPE_FLOAT, TYPE_INT]:
			return d
		return clampf(float(v), 14.0, 26.0) if key == "touch/joystick_size" \
			else clampf(float(v), 0.25 if key == "touch/joystick_opacity" else 0.0, 1.0)
	if typeof(d) == TYPE_BOOL:
		return v if typeof(v) == TYPE_BOOL else d
	if CHOICES.has(key):
		return v if v in CHOICES[key] else d
	return str(v)


static func _ensure_loaded() -> void:
	if not _loaded:
		load_settings()


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func text_cps() -> float:
	return TEXT_CPS[get_value("gameplay/text_speed")]


static func camera_follow_speed() -> float:
	return CAMERA_FOLLOW[get_value("gameplay/camera_smoothing")]


## Pushes settings to the engine. Safe to call any time.
static func apply() -> void:
	_ensure_loaded()
	Audio.ensure_buses()
	_set_bus("Master", get_value("audio/master"))
	_set_bus("Music", get_value("audio/music"))
	_set_bus("SFX", get_value("audio/sfx"))
	if not is_mobile() and DisplayServer.get_name() != "headless":
		var fs: bool = get_value("display/fullscreen")
		var mode := DisplayServer.window_get_mode()
		var is_fs := mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
	var tree := Engine.get_main_loop() as SceneTree
	var scaler: Node = tree.root.get_node_or_null(^"PixelScaler") if tree else null
	if scaler:
		scaler.set("target_height", ZOOM_HEIGHT[get_value("display/zoom")])
		scaler.call("_apply")
	UITheme.set_ui_scale(1.25 if get_value("display/ui_scale") == "large" else 1.0)
	if Loc.locale != get_value("lang/locale"):
		Loc.set_locale(get_value("lang/locale"))


static func _set_bus(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_mute(i, linear <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))
