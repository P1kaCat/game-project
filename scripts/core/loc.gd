class_name Loc
extends RefCounted
## Localization: UI strings live in res://data/i18n/<locale>.json (key -> text,
## "{name}" placeholders). Story/dialogue data files are localized by name:
## "eldric.json" -> "eldric.<locale>.json" when it exists (French is the default
## and the fallback). Adding English = adding en.json + *.en.json files.

const DEFAULT_LOCALE := "fr"

static var locale := DEFAULT_LOCALE
static var _strings := {}
static var _fallback := {}


static func set_locale(code: String) -> void:
	locale = code if FileAccess.file_exists("res://data/i18n/%s.json" % code) else DEFAULT_LOCALE
	_strings = {}


static func t(key: String, args := {}) -> String:
	if _strings.is_empty():
		_strings = _read(locale)
		_fallback = _strings if locale == DEFAULT_LOCALE else _read(DEFAULT_LOCALE)
	var s := str(_strings.get(key, _fallback.get(key, key)))
	for k in args:
		s = s.replace("{%s}" % k, str(args[k]))
	return s


## "res://data/x.json" -> "res://data/x.<locale>.json" if present.
static func localized_path(path: String) -> String:
	var loc := path.get_basename() + ".%s.json" % locale
	return loc if FileAccess.file_exists(loc) else path


static func available_locales() -> Array[String]:
	var out: Array[String] = []
	for code in ["fr", "en", "es", "de"]:
		if FileAccess.file_exists("res://data/i18n/%s.json" % code):
			out.append(code)
	return out


static func _read(code: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/%s.json" % code))
	return data if data is Dictionary else {}


## A string in a specific language (e.g. each language's own name).
static func t_in(code: String, key: String) -> String:
	return str(_read(code).get(key, key))
