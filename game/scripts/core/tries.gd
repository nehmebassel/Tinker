class_name Tries
extends RefCounted
## Tries — limited runs (M6, changed 2026-11-03): `limit` runs per window of `window_hours`, the window
## starting at the first run after a refill. Pressing RUN costs one try (stopping early used to be
## free); solving a level refills them when the economy switch refill_tries_on_new_level is on.
## When none are left, RUN waits until the window ends (or the player gets tries with an ad / coins).
##
## Rules come from the backend (GET /config: TRIES_LIMIT, TRIES_WINDOW_HOURS, set in Cloud Run) and
## are cached here; offline the project settings tinker/tries_limit and tinker/tries_window_hours
## (editable in the Godot editor) are the fallback. Stored in user://tries.json.
## `now` is passed in (unix seconds) so the logic is testable without waiting hours.

const PATH := "user://tries.json"

var limit: int = 3
var window_hours: float = 6.0
var used: int = 0
var window_start: int = 0  # unix seconds of the first failure in the current window, 0 = full
var _path := PATH


static func load_or_new(path: String = PATH) -> Tries:
	var t := Tries.new()
	t._path = path
	t.limit = int(ProjectSettings.get_setting("tinker/tries_limit", 3))
	t.window_hours = float(ProjectSettings.get_setting("tinker/tries_window_hours", 6.0))
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			t.used = int(d.get("used", 0))
			t.window_start = int(d.get("window_start", 0))
			t.limit = int(d.get("limit", t.limit))
			t.window_hours = float(d.get("window_hours", t.window_hours))
	return t


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"used": used, "window_start": window_start, "limit": limit, "window_hours": window_hours}))


## Rules from the server. Saved so the next offline launch uses them too.
func set_rules(p_limit: int, p_hours: float) -> void:
	limit = maxi(1, p_limit)
	window_hours = maxf(0.01, p_hours)
	save()


func _refresh(now: int) -> void:
	if window_start > 0 and now >= window_start + int(window_hours * 3600.0):
		used = 0
		window_start = 0
		save()


func left(now: int) -> int:
	_refresh(now)
	return maxi(0, limit - used)


## Record one run (RUN pressed). Returns tries left.
func use(now: int) -> int:
	_refresh(now)
	if window_start == 0:
		window_start = now
	used = mini(limit, used + 1)
	save()
	return left(now)


## Seconds until the tries refill (0 when none are used).
func seconds_to_refill(now: int) -> int:
	_refresh(now)
	if window_start == 0:
		return 0
	return maxi(0, window_start + int(window_hours * 3600.0) - now)


static func fmt_wait(secs: int) -> String:
	var h := secs / 3600
	var m := (secs % 3600) / 60
	var s := secs % 60
	return "%d:%02d:%02d" % [h, m, s] if h > 0 else "%d:%02d" % [m, s]


## Bought / earned extra tries (coins, a rewarded ad): give back `n` used tries.
func add(n: int, now: int) -> void:
	_refresh(now)
	used = maxi(0, used - n)
	if used == 0:
		window_start = 0
	save()


## A new level was reached (economy feature refill_tries_on_new_level): start it with full tries.
func refill() -> void:
	reset()


func reset() -> void:
	used = 0
	window_start = 0
	save()
