class_name UpdateService
extends Node
## GitHub Releases client used by the launcher (part of the "base": see
## tools/release/set_version.py). No credentials: the repository is public.
##
## Release assets published by .github/workflows/release.yml:
##   manifest.json        {version, base_id, packs: {windows|android: {name, sha256, size}}}
##   game-windows.pck     game content (hot-loaded by the launcher, no restart)
##   game-android.pck
##   IsoRPG-windows.zip   full Windows build (only needed when the base changes)
##   IsoRPG.apk           full Android build (only needed when the base changes)

const REPO := "P1kaCat/game-project"
const USER_AGENT := "IsoRPG-launcher"

## Root of the GitHub website. Releases are read through its public download
## links (served by GitHub's CDN), NOT through api.github.com: the anonymous
## API is limited to 60 requests/hour per IP, which shared IPs (mobile
## carriers, offices, cloud machines) exhaust quickly.
var web_base := "https://github.com"

var _active: HTTPRequest
var _expected_size := 0


## Latest release as {version, page_url, manifest, assets: {name: {url, size}}},
## or {} on error. Reads releases/latest/download/manifest.json, which already
## holds the version, base_id and pack checksums; asset URLs follow from the
## version tag.
func fetch_latest_release(timeout := 10.0) -> Dictionary:
	var manifest := await fetch_json("%s/%s/releases/latest/download/manifest.json" % [web_base, REPO], timeout)
	if not manifest.has("version"):
		return {}
	var version := str(manifest.version)
	var dl := "%s/%s/releases/download/v%s/" % [web_base, REPO, version]
	var assets := {}
	for name in ["manifest.json", "IsoRPG-windows.zip", "IsoRPG.apk"]:
		assets[name] = {"url": dl + name, "size": 0}
	for key in manifest.get("packs", {}):
		var p: Dictionary = manifest.packs[key]
		assets[str(p.get("name", ""))] = {"url": dl + str(p.get("name", "")), "size": int(p.get("size", 0))}
	return {
		"version": version,
		"page_url": "%s/%s/releases/tag/v%s" % [web_base, REPO, version],
		"manifest": manifest,
		"assets": assets,
	}


## Small JSON asset (the manifest). {} on error.
func fetch_json(url: String, timeout := 10.0) -> Dictionary:
	var res := await _http_get(url, timeout, ["Accept: application/json"])
	if res.is_empty():
		return {}
	var data = JSON.parse_string(res.body.get_string_from_utf8())
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Downloads `url` to the absolute path `dest`. Returns true on HTTP 200.
func download(url: String, dest: String, expected_size := 0) -> bool:
	_expected_size = expected_size
	_active = HTTPRequest.new()
	_active.download_file = dest
	_active.use_threads = true
	_active.download_chunk_size = 262144
	add_child(_active)
	var ok := _active.request(url, PackedStringArray(["User-Agent: " + USER_AGENT])) == OK
	if ok:
		var r: Array = await _active.request_completed
		ok = r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200
	_active.queue_free()
	_active = null
	return ok


## 0..1 while downloading, -1 when unknown.
func progress() -> float:
	if _active == null:
		return -1.0
	var total := _active.get_body_size()
	if total <= 0:
		total = _expected_size
	return clampf(float(_active.get_downloaded_bytes()) / total, 0.0, 1.0) if total > 0 else -1.0


func _http_get(url: String, timeout: float, extra_headers: Array = []) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT])
	headers.append_array(PackedStringArray(extra_headers))
	if http.request(url, headers) != OK:
		http.queue_free()
		return {}
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		print("[Launcher] GET %s -> result %d, HTTP %d" % [url, r[0], r[1]])
		return {}
	return {"body": r[3]}


## True when version `a` (X.Y.Z) is newer than `b`.
static func is_newer(a: String, b: String) -> bool:
	var pa := _parse(a)
	var pb := _parse(b)
	for i in 3:
		if pa[i] != pb[i]:
			return pa[i] > pb[i]
	return false


static func _parse(v: String) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	var parts := v.strip_edges().trim_prefix("v").split("-")[0].split(".")
	for i in mini(3, parts.size()):
		out[i] = parts[i].to_int()
	return out


## Replaces the running Windows executable with the one inside `zip_path`
## (renaming a running exe is allowed on Windows; the .old copy is deleted on
## the next start). Returns "" on success or an error message.
static func swap_windows_exe(zip_path: String, exe_path: String, exe_name: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "Archive invalide."
	var entry := ""
	for f in zip.get_files():
		if f.get_file() == exe_name:
			entry = f
	var bytes := zip.read_file(entry) if entry != "" else PackedByteArray()
	zip.close()
	if bytes.size() < 1024 or bytes[0] != 0x4D or bytes[1] != 0x5A:  # "MZ"
		return "Exécutable introuvable dans l'archive."
	var new_path := exe_path + ".new"
	var old_path := exe_path + ".old"
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		return "Écriture impossible dans le dossier du jeu."
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(old_path):
		DirAccess.remove_absolute(old_path)
	if DirAccess.rename_absolute(exe_path, old_path) != OK:
		DirAccess.remove_absolute(new_path)
		return "Impossible de remplacer le jeu."
	if DirAccess.rename_absolute(new_path, exe_path) != OK:
		DirAccess.rename_absolute(old_path, exe_path)
		return "Impossible de remplacer le jeu."
	return ""


static func is_dir_writable(dir: String) -> bool:
	var probe := dir.path_join(".update_write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true
