class_name Settings
extends RefCounted
## Settings — user://settings.json. Everything a player or tester may need to change lives here and is
## edited on the in-game Settings screen; nothing is hard-coded in scripts.
##   server_url   : backend base URL. Initial value: project setting tinker/server_url (editable in the
##                  Godot editor's Project Settings), then whatever the player types in Settings.
##   device_id    : random id created on first launch; the only identity the backend ever sees.
##   name         : optional display name for boards (24 chars max).
##   push_enabled : daily reminder notification on/off.

const PATH := "user://settings.json"

var server_url: String = ""
var device_id: String = ""
var name: String = ""
var push_enabled: bool = true
var _path := PATH
var _saved_url := false  # true when the player saved a server URL in Settings


static func load_or_new(path: String = PATH) -> Settings:
	var s := Settings.new()
	s._path = path
	s.server_url = str(ProjectSettings.get_setting("tinker/server_url", ""))
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var j := JSON.new()
		if f and j.parse(f.get_as_text()) == OK and j.data is Dictionary:
			var d: Dictionary = j.data
			if str(d.get("server_url", "")) != "":
				s.server_url = str(d["server_url"])
				s._saved_url = true
			s.device_id = str(d.get("device_id", ""))
			s.name = str(d.get("name", ""))
			s.push_enabled = bool(d.get("push_enabled", true))
	# In the browser build the game is served by the backend itself (/play/), so the page's own origin
	# is the server: zero setup for testers. A value typed in Settings still wins.
	if OS.has_feature("web") and not s._saved_url:
		var origin := str(JavaScriptBridge.eval("window.location.origin", true))
		if origin.begins_with("http"):
			s.server_url = origin
	if s.device_id.length() < 16:
		s.device_id = _new_device_id()
		s.save()
	return s


static func _new_device_id() -> String:
	# Not part of any simulation: randomness here is fine.
	var bytes := Crypto.new().generate_random_bytes(18)
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"server_url": server_url, "device_id": device_id, "name": name, "push_enabled": push_enabled}, "  "))


func base_url() -> String:
	return server_url.strip_edges().trim_suffix("/")


## ISO country from the store/system locale ("en_US" -> "US"); never from location services.
static func country() -> String:
	var parts := OS.get_locale().split("_")
	if parts.size() >= 2 and parts[1].length() == 2:
		return parts[1].to_upper()
	return "ZZ"
