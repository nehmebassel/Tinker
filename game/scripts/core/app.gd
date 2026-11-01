extends Node
## App — autoload: navigation between the world select and the level screen, plus the save.
## The level screen reads `level_number` when it starts; 0 means "use the --level= path or default".

const WORLD_SELECT := "res://scenes/world_select.tscn"
const LEVEL := "res://scenes/level.tscn"
const BOARD := "res://scenes/board.tscn"
const SETTINGS := "res://scenes/settings.tscn"

var save: SaveData
var settings: Settings
var daily_store: DailyStore
var api: Api
var push: Push
var level_number: int = 0
## The Daily currently open: {"date": String, "day": int, "level": Dictionary} or {} for campaign play.
var daily: Dictionary = {}
var board_date: String = ""
var _nav_gen := 0  # bumped by every navigation; a slow async navigation checks it before switching
var flow_test: bool = false
var daily_test: String = ""  # --daily-flow=<solution.json>: CI test of the whole daily loop


func _ready() -> void:
	save = SaveData.load_or_new()
	settings = Settings.load_or_new()
	daily_store = DailyStore.load_or_new()
	api = Api.new(settings)
	add_child(api)
	push = Push.new()
	push.name = "Push"
	add_child(push)
	for a in OS.get_cmdline_user_args():
		if a == "--reset-save":
			save.reset()
		elif a == "--flow":
			flow_test = true
		elif a.begins_with("--server="):
			settings.server_url = a.trim_prefix("--server=")
			settings.save()
		elif a.begins_with("--daily-flow="):
			daily_test = a.trim_prefix("--daily-flow=")
		elif a.begins_with("--shot-ws="):
			_shot_ws(a.trim_prefix("--shot-ws="))
	if flow_test:
		save.reset()
		_run_flow()
	elif daily_test != "":
		_run_daily_flow.call_deferred()


## Scene changes are deferred so the input event that triggered them (a button release) finishes
## before its scene is freed.
func open_level(number: int) -> void:
	_nav_gen += 1
	level_number = number
	get_tree().change_scene_to_file.call_deferred(LEVEL)


func open_world_select() -> void:
	_nav_gen += 1
	level_number = 0
	daily = {}
	get_tree().change_scene_to_file.call_deferred(WORLD_SELECT)


func open_settings() -> void:
	_nav_gen += 1
	get_tree().change_scene_to_file.call_deferred(SETTINGS)


func open_board(date: String) -> void:
	_nav_gen += 1
	board_date = date
	get_tree().change_scene_to_file.call_deferred(BOARD)


## Fetch today's Daily and open it — or its board when today's single submission is already used.
## Returns "" on success, else an error message for the caller to show.
func open_daily() -> String:
	var today := DailyStore.today_utc()
	if daily_store.is_submitted(today):
		open_board(today)
		return ""
	_nav_gen += 1
	var my_gen := _nav_gen
	var r: Dictionary = await api.get_json("/daily/" + today)
	if my_gen != _nav_gen:
		return ""  # the player went somewhere else while this was loading: don't yank them away
	if not r["ok"]:
		return "Daily unavailable: " + str(r["error"])
	var body: Dictionary = r["body"]
	var lv: Dictionary = body["level"]
	if LevelData.validate(lv) != "":
		return "Daily level is invalid"
	daily = {"date": today, "day": int(body.get("day", 0)), "level": lv}
	level_number = 0
	get_tree().change_scene_to_file.call_deferred(LEVEL)
	return ""


## FCM registration token, set by the platform push plugin when it obtains one (Android/iOS builds).
## Empty on desktop and in tests, in which case push sync is a no-op.
var fcm_token: String = ""


## Tells the server this device's token and whether the daily reminder is on.
func sync_push() -> void:
	if fcm_token == "" or settings.base_url() == "":
		return
	await api.post_json("/push/register", {"device_id": settings.device_id, "token": fcm_token, "enabled": settings.push_enabled})


## Submits today's solution (once). Returns the server's answer.
func submit_daily(placements: Array, solve_ms: int) -> Dictionary:
	var date: String = daily.get("date", "")
	var sol := []
	for p in placements:
		sol.append({"part": p.part, "x": p.cell.x, "y": p.cell.y, "rot": p.rot})
	var body := {"device_id": settings.device_id, "date": date, "solution": sol,
		"elapsed_ms": solve_ms, "country": Settings.country(), "name": settings.name}
	var r: Dictionary = await api.post_json("/score", body)
	if r["ok"] or r["status"] == 409:
		var b: Dictionary = r["body"] if r["body"] is Dictionary else {}
		var e: Dictionary = b.get("entry", b)
		daily_store.record_submission(date, int(e.get("parts", sol.size())), int(e.get("ms", body["elapsed_ms"])), int(b.get("rank", 0)))
	return r


func has_next(number: int) -> bool:
	return not Campaign.entry(number + 1).is_empty()


func _shot_ws(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0)


# ------------------------------------------------------------------ campaign flow test (CI)
## World select -> tap level 1 -> solve it through the touch path -> Next -> level 2 -> back ->
## world select shows 1 solved and 2 unlocked, and the save file has level 1. Exit 0 on success.

var _flow_ok := true


func _flow_assert(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	_flow_ok = _flow_ok and cond


func _tap(control: Control) -> void:
	var xf := get_viewport().get_final_transform()
	var p := xf * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.position = p
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().process_frame


func _wait_scene(name: String, frames: int = 120) -> Node:
	for i in frames:
		var cs := get_tree().current_scene
		if cs != null and cs.name == name:
			await get_tree().process_frame
			return cs
		await get_tree().process_frame
	return null


func _run_flow() -> void:
	await get_tree().process_frame
	var ws := await _wait_scene("WorldSelect")
	_flow_assert(ws != null, "world select is the main scene")
	var b1: Button = ws.find_child("Level1", true, false)
	var b2: Button = ws.find_child("Level2", true, false)
	_flow_assert(b1 != null and not b1.disabled, "level 1 unlocked")
	_flow_assert(b2 != null and b2.disabled, "level 2 locked at start")
	await _tap(b1)
	var ls := await _wait_scene("LevelScreen")
	_flow_assert(ls != null and ls.level_number == 1, "tapping level 1 opens level 1")
	# Let the level screen's own smoke routine solve it, but keep the process alive.
	var outcome: Dictionary = await ls.run_smoke_steps()
	_flow_assert(outcome.get("result", "") == "goal", "level 1 solved through the touch path")
	_flow_assert(save.is_solved(1), "save records level 1")
	_flow_assert(ls.next_btn.visible, "Next button shown")
	await _tap(ls.next_btn)
	var ls2 := await _wait_scene("LevelScreen")
	_flow_assert(ls2 != null and ls2 != ls and ls2.level_number == 2, "Next opens level 2")
	await _tap(ls2.back_btn)
	var ws2 := await _wait_scene("WorldSelect")
	var b1b: Button = ws2.find_child("Level1", true, false)
	var b2b: Button = ws2.find_child("Level2", true, false)
	_flow_assert(b2b != null and not b2b.disabled, "level 2 unlocked after solving 1")
	_flow_assert(b1b != null and b1b.get_child_count() > 0, "level 1 shows its best")
	var reloaded := SaveData.load_or_new()
	_flow_assert(reloaded.is_solved(1) and int(reloaded.best(1)["best_parts"]) == 1, "save file persisted (1 part)")
	print("FLOW %s" % ("PASS" if _flow_ok else "FAIL"))
	get_tree().quit(0 if _flow_ok else 1)


# ------------------------------------------------------------------ daily loop test (CI / staging)
## Needs a running backend (--server=) whose today's daily is a ONE-part level, and the reference
## solution file. World select -> Daily -> drag the part in through the touch path -> PLAY -> solved
## -> Submit -> board shows this device at rank >= 1 -> reopening Daily goes straight to the board.

func _run_daily_flow() -> void:
	daily_store.days = {}
	daily_store.save()
	var f := FileAccess.open(daily_test, FileAccess.READ)
	var sol: Array = JSON.parse_string(f.get_as_text()) if f else []
	_flow_assert(sol.size() == 1, "reference solution has one part")
	var ws := await _wait_scene("WorldSelect")
	var db: Button = ws.find_child("DailyButton", true, false)
	_flow_assert(db != null, "Daily button on the world select")
	await _tap(db)
	var ls := await _wait_scene("LevelScreen")
	_flow_assert(ls != null and not ls.daily.is_empty(), "Daily opens the level screen in daily mode")
	if ls == null:
		_finish_daily_flow()
		return
	var ref: Array[Placement] = [Placement.from_dict(sol[0])]
	ls.level.reference_solution = ref
	var outcome: Dictionary = await ls.run_smoke_steps()
	_flow_assert(outcome.get("result", "") == "goal", "daily solved through the touch path")
	_flow_assert(ls.submit_btn.visible, "Submit offered after solving")
	await _tap(ls.submit_btn)
	var bs := await _wait_scene("BoardScreen", 900)
	_flow_assert(bs != null, "submission opens the board")
	if bs:
		for i in 300:
			if bs.loaded:
				break
			await get_tree().process_frame
		_flow_assert(bs.me_rank >= 1, "board shows this device ranked (rank %d)" % bs.me_rank)
	_flow_assert(daily_store.is_submitted(DailyStore.today_utc()), "submission recorded locally")
	_flow_assert(daily_store.streak() == 1, "streak is 1")
	open_world_select()
	var ws2 := await _wait_scene("WorldSelect")
	await _tap(ws2.find_child("DailyButton", true, false))
	var bs2 := await _wait_scene("BoardScreen", 300)
	_flow_assert(bs2 != null, "second tap on Daily goes straight to the board (one submission only)")
	_finish_daily_flow()


func _finish_daily_flow() -> void:
	print("DAILY %s" % ("PASS" if _flow_ok else "FAIL"))
	get_tree().quit(0 if _flow_ok else 1)
