extends Control
## Launcher: the first scene of the exe / APK. Brings the game content up to
## date, then starts the game in the same process (no restart).
##
## 1. Reads its own build_info.json (the "base": engine, project settings,
##    autoloads, launcher) BEFORE any pack is mounted.
## 2. Mounts the last downloaded content pack, if it fits this base and is newer
##    (so the latest content also works offline).
## 3. Asks GitHub for the latest release. If newer:
##      same base_id  -> downloads game-<platform>.pck (verified by SHA-256),
##                       mounts it with ProjectSettings.load_resource_pack and
##                       continues: no restart, no reinstall.
##      other base_id -> the engine-level part changed, a full update is needed:
##                       Windows downloads the new exe, swaps it and restarts
##                       once; Android offers to download the new APK.
## 4. Starts the game (main menu). Any network problem -> just plays.
##
## Command-line (after `--`), mainly for tests: --check-updates (check in
## non-exported runs), --no-update-check, --update-base-url=URL (instead of
## https://github.com),
## --update-platform=windows|android, --update-exe-path=PATH, --no-restart.

const GAME_SCENE := "res://scenes/main_menu.tscn"
const BUILD_INFO := "res://build_info.json"
const CONTENT_DIR := "user://content"
const CACHE_MANIFEST := "user://content/manifest.json"
const WINDOWS_ZIP := "IsoRPG-windows.zip"
const WINDOWS_EXE := "IsoRPG.exe"
const ANDROID_APK := "IsoRPG.apk"

var base_version := "0.0.0"
var base_id := ""
var content_version := ""
var result := {"status": "starting", "action": "none"}

var _service: UpdateService
var _platform := ""
var _exe_path := ""
var _restart := true
var _status: Label
var _progress: ProgressBar
var _version: Label
var _buttons: HBoxContainer
var _shot_index := 0
var _started := false


func _ready() -> void:
	_build_ui()
	_service = UpdateService.new()
	add_child(_service)
	_platform = OS.get_name().to_lower()
	_exe_path = OS.get_executable_path()
	var args := OS.get_cmdline_user_args()
	var check := OS.has_feature("template")
	for arg in args:
		if arg == "--check-updates":
			check = true
		elif arg == "--no-update-check":
			check = false
		elif arg.begins_with("--update-base-url="):
			_service.web_base = arg.trim_prefix("--update-base-url=").trim_suffix("/")
		elif arg.begins_with("--update-platform="):
			_platform = arg.trim_prefix("--update-platform=")
		elif arg.begins_with("--update-exe-path="):
			_exe_path = arg.trim_prefix("--update-exe-path=")
		elif arg == "--no-restart":
			_restart = false
	if "--autotest" in args and not "--check-updates" in args:
		check = false
	_run(check)


func _run(check: bool) -> void:
	var info := _read_json(BUILD_INFO)
	base_version = str(info.get("version", ProjectSettings.get_setting("application/config/version", "0.0.0")))
	base_id = str(info.get("base_id", ""))
	content_version = base_version
	if _platform == "windows" and FileAccess.file_exists(_exe_path + ".old"):
		DirAccess.remove_absolute(_exe_path + ".old")
	_mount_cached_content()
	_show_version()

	if check:
		await _check_online()
	if result.status == "starting":
		result.status = "skipped" if not check else result.status
	if result.get("blocked", false):
		return  # waiting for the player (Android full update screen)
	await _start_game()


# ------------------------------------------------------------ cached content
func _mount_cached_content() -> void:
	var cache := _read_json(CACHE_MANIFEST)
	if cache.is_empty():
		_clear_cache()  # leftovers from an interrupted or superseded update
		return
	var pack := CONTENT_DIR.path_join(str(cache.get("file", "")))
	var usable: bool = cache.get("base_id", "") == base_id \
		and UpdateService.is_newer(str(cache.get("version", "0")), base_version) \
		and FileAccess.file_exists(pack) \
		and FileAccess.get_sha256(pack) == str(cache.get("sha256", ""))
	if usable and ProjectSettings.load_resource_pack(pack):
		content_version = str(cache.version)
		result.cached = content_version
		_clear_cache_except([CACHE_MANIFEST.get_file(), pack.get_file()])
		print("[Launcher] mounted cached content v%s" % content_version)
	else:
		# Older than / incompatible with this base (e.g. after a full update).
		_clear_cache()


func _clear_cache() -> void:
	_clear_cache_except([])


## Deletes cached files except `keep`. Failures are ignored (a pack that is
## still open can't be deleted on Windows; it is retried on the next start).
func _clear_cache_except(keep: Array) -> void:
	var dir := DirAccess.open(CONTENT_DIR)
	if dir:
		for f in dir.get_files():
			if not f in keep:
				dir.remove(f)


# ------------------------------------------------------------- online check
func _check_online() -> void:
	_set_status("Recherche de mises à jour…")
	var rel := await _service.fetch_latest_release()
	if rel.is_empty():
		result.status = "offline"
		print("[Launcher] update check failed, playing v%s" % content_version)
		return
	if not UpdateService.is_newer(rel.version, content_version):
		result.status = "up_to_date"
		print("[Launcher] up to date (v%s, latest v%s)" % [content_version, rel.version])
		return

	var manifest: Dictionary = rel.manifest
	var key := "android" if _platform == "android" else "windows"
	var pack_info: Dictionary = manifest.get("packs", {}).get(key, {})
	if manifest.get("base_id", "") == base_id and not pack_info.is_empty() \
			and rel.assets.has(str(pack_info.get("name", ""))):
		await _content_update(rel, manifest, pack_info)
	else:
		await _full_update(rel)


func _content_update(rel: Dictionary, manifest: Dictionary, pack_info: Dictionary) -> void:
	var version := str(manifest.get("version", rel.version))
	_set_status("Téléchargement de la mise à jour v%s…" % version)
	DirAccess.make_dir_recursive_absolute(CONTENT_DIR)
	var file := "game-%s.pck" % version
	var dest := ProjectSettings.globalize_path(CONTENT_DIR.path_join(file))
	var part := dest + ".part"
	var asset: Dictionary = rel.assets[pack_info.name]
	var ok := await _service.download(asset.url, part, int(pack_info.get("size", asset.size)))
	if ok and FileAccess.get_sha256(part) != str(pack_info.get("sha256", "")):
		print("[Launcher] checksum mismatch, update rejected")
		ok = false
	if not ok:
		DirAccess.remove_absolute(part)
		result.status = "download_failed"
		_set_status("Mise à jour impossible, lancement de la version actuelle…")
		await get_tree().create_timer(1.0).timeout
		return
	DirAccess.remove_absolute(dest)
	DirAccess.rename_absolute(part, dest)
	if not ProjectSettings.load_resource_pack(dest):
		result.status = "mount_failed"
		return
	var f := FileAccess.open(CACHE_MANIFEST, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": version, "base_id": base_id, "file": file,
		"sha256": str(pack_info.sha256)}))
	f.close()
	# The new pack overrides every file of an older mounted one; old packs are
	# only deleted from disk (best effort), never unmounted mid-run.
	_clear_cache_except([CACHE_MANIFEST.get_file(), file])
	content_version = version
	result.status = "updated"
	result.action = "content"
	print("[Launcher] content updated to v%s (no restart)" % version)
	_show_version()
	_set_status("Mise à jour v%s installée !" % version)
	await get_tree().create_timer(0.6).timeout


func _full_update(rel: Dictionary) -> void:
	result.action = "full"
	if _platform == "windows" and rel.assets.has(WINDOWS_ZIP):
		var dir := _exe_path.get_base_dir()
		if not UpdateService.is_dir_writable(dir):
			result.status = "full_update_manual"
			OS.shell_open(rel.page_url)
			return
		_set_status("Nouvelle version complète v%s : téléchargement…" % rel.version)
		var zip := ProjectSettings.globalize_path("user://update.zip")
		var asset: Dictionary = rel.assets[WINDOWS_ZIP]
		if not await _service.download(asset.url, zip, asset.size):
			result.status = "download_failed"
			return
		_set_status("Installation…")
		var err := UpdateService.swap_windows_exe(zip, _exe_path, WINDOWS_EXE)
		DirAccess.remove_absolute(zip)
		if err != "":
			result.status = "full_update_failed"
			print("[Launcher] full update failed: " + err)
			OS.shell_open(rel.page_url)
			return
		# The new exe embeds newer content; drop the cache index now and let the
		# next start remove the (possibly still mounted) old pack.
		DirAccess.remove_absolute(CACHE_MANIFEST)
		result.status = "full_updated"
		print("[Launcher] exe replaced by v%s" % rel.version)
		if _restart:
			_set_status("Redémarrage…")
			await get_tree().create_timer(0.5).timeout
			OS.create_process(_exe_path, [])
			get_tree().quit()
			result.blocked = true
		return

	if _platform == "android" and rel.assets.has(ANDROID_APK):
		result.status = "full_update_offered"
		result.blocked = true
		_set_status("La version v%s demande une nouvelle installation de l'application." % rel.version)
		_offer_choice("Télécharger", func() -> void:
			OS.shell_open(rel.assets[ANDROID_APK].url)
			_set_status("Ouvre le fichier IsoRPG.apk téléchargé pour installer."),
			"Jouer v%s" % content_version)
		if "--autotest" in OS.get_cmdline_user_args():  # test hook: pick "Jouer"
			await get_tree().create_timer(1.0).timeout
			result.blocked = false
		return

	result.status = "full_update_manual"
	OS.shell_open(rel.page_url)


# ---------------------------------------------------------------- start game
func _start_game() -> void:
	if _started:
		return
	_started = true
	_set_status("Lancement…")
	Engine.set_meta(&"content_version", content_version)
	Engine.set_meta(&"launcher_result", result)
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME_SCENE)


# ------------------------------------------------------------------------ UI
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(240, 0)
	center.add_child(box)

	var icon := TextureRect.new()
	icon.texture = load("res://icon.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.custom_minimum_size = Vector2(64, 64)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)
	var title := Label.new()
	title.text = "Asthya"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	box.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 8)
	box.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.show_percentage = false
	_progress.modulate.a = 0.0
	box.add_child(_progress)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 10)
	box.add_child(_buttons)

	_version = Label.new()
	_version.add_theme_font_size_override("font_size", 8)
	_version.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	_version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_version.position += Vector2(-6, -4)
	_version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_version)


func _process(_delta: float) -> void:
	var p := _service.progress() if _service else -1.0
	_progress.modulate.a = 1.0 if p >= 0.0 else 0.0
	if p >= 0.0:
		_progress.value = p * 100.0


func _set_status(text: String) -> void:
	_status.text = text
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--launcher-shots="):
			shots = a.trim_prefix("--launcher-shots=")
	if shots != "":  # test hook: screenshot of each launcher step
		await get_tree().process_frame
		await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute(shots)
		get_viewport().get_texture().get_image().save_png("%s/launcher_%02d.png" % [shots, _shot_index])
		_shot_index += 1


func _show_version() -> void:
	_version.text = "v%s" % content_version


func _offer_choice(primary: String, on_primary: Callable, secondary: String) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var a := _make_button(primary)
	a.pressed.connect(on_primary)
	var b := _make_button(secondary)
	b.pressed.connect(func() -> void:
		result.blocked = false
		_start_game())
	_buttons.add_child(a)
	_buttons.add_child(b)


static func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 8)
	b.custom_minimum_size = Vector2(80, 20)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.2, 0.24, 0.3) if state != "pressed" else Color(0.55, 0.47, 0.25)
		sb.border_color = Color(0.95, 0.85, 0.55)
		sb.set_border_width_all(1)
		sb.set_content_margin_all(3)
		b.add_theme_stylebox_override(state, sb)
	return b


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if typeof(data) == TYPE_DICTIONARY else {}
