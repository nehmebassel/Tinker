class_name DailyStore
extends RefCounted
## DailyStore — user://daily.json: per date, when the clock started (first touch, unix seconds, so a
## restart cannot reset it), whether the one submission happened and its result; plus the streak.
## Streak = consecutive UTC days with a submission, ending today or yesterday. No reward attached.

const PATH := "user://daily.json"

var days: Dictionary = {}  # "YYYY-MM-DD" -> {"started": float, "submitted": bool, "parts": int, "ms": int, "rank": int}
var _path := PATH


static func load_or_new(path: String = PATH) -> DailyStore:
	var s := DailyStore.new()
	s._path = path
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var j := JSON.new()
		if f and j.parse(f.get_as_text()) == OK and j.data is Dictionary and j.data.get("days") is Dictionary:
			s.days = j.data["days"]
	return s


func save() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"days": days}, "  "))


func day(date: String) -> Dictionary:
	return days.get(date, {})


## Starts the clock on the first touch of that day's puzzle; later calls keep the original start.
func start_clock(date: String) -> void:
	var d: Dictionary = days.get(date, {})
	if not d.has("started"):
		d["started"] = Time.get_unix_time_from_system()
		days[date] = d
		save()


func elapsed_ms(date: String) -> int:
	var d: Dictionary = days.get(date, {})
	if not d.has("started"):
		return 0
	return int((Time.get_unix_time_from_system() - float(d["started"])) * 1000.0)


func is_submitted(date: String) -> bool:
	return bool(days.get(date, {}).get("submitted", false))


func record_submission(date: String, parts: int, ms: int, rank: int) -> void:
	var d: Dictionary = days.get(date, {})
	d.merge({"submitted": true, "parts": parts, "ms": ms, "rank": rank}, true)
	days[date] = d
	save()


static func today_utc() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))


static func add_days(date: String, n: int) -> String:
	var t := Time.get_unix_time_from_datetime_string(date + "T00:00:00")
	return Time.get_date_string_from_unix_time(t + n * 86400)


func streak(today: String = "") -> int:
	if today == "":
		today = today_utc()
	var d := today if is_submitted(today) else add_days(today, -1)
	var n := 0
	while is_submitted(d):
		n += 1
		d = add_days(d, -1)
	return n
