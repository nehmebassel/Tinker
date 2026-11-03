extends Node
## App — autoload: navigation between the world select and the level screen, plus the save.
## The level screen reads `level_number` when it starts; 0 means "use the --level= path or default".

const WORLD_SELECT := "res://scenes/world_select.tscn"
const LEVEL := "res://scenes/level.tscn"
const BOARD := "res://scenes/board.tscn"
const SETTINGS := "res://scenes/settings.tscn"
const SANDBOX := "res://scenes/sandbox.tscn"

var save: SaveData
var settings: Settings
var daily_store: DailyStore
var api: Api
var push: Push
var audio: Audio
var tries: Tries
var sandbox_store: SandboxStore
var economy := Economy.new()  # admin-console rules from GET /config (empty = everything paid off)
var wallet: Wallet
var ads: Ads
var store: Store

signal economy_changed

const PRESENCE_S := 60.0  # heartbeat while the game is open: "online now" in the admin console
## Sandbox context for the level screen: {} for campaign/daily, else
## {"mode": "edit"|"verify", "index": draft} or {"mode": "shared", "code", "level", "author_parts"}.
var sandbox: Dictionary = {}
var map_last_node: int = -1  # level the map's marble sat on when the map was last shown (session only)
var level_number: int = 0
## The Daily currently open: {"date": String, "day": int, "level": Dictionary} or {} for campaign play.
var daily: Dictionary = {}
var board_date: String = ""
var _nav_gen := 0  # bumped by every navigation; a slow async navigation checks it before switching
var flow_test: bool = false
var daily_test: String = ""
var sandbox_test: String = ""  # "publish:<file to write the code>" or "play:<code>" (CI, two installs)  # --daily-flow=<solution.json>: CI test of the whole daily loop


## Any touch / click / scroll: animate at full rate for a moment (FramePacer), so dragging stays smooth.
func _input(_event: InputEvent) -> void:
	FramePacer.busy(600)


func _ready() -> void:
	save = SaveData.load_or_new()
	settings = Settings.load_or_new()
	settings.apply_battery_saver()
	daily_store = DailyStore.load_or_new()
	api = Api.new(settings)
	add_child(api)
	push = Push.new()
	push.name = "Push"
	add_child(push)
	audio = Audio.new()
	add_child(audio)
	tries = Tries.load_or_new()
	sandbox_store = SandboxStore.load_or_new()
	wallet = Wallet.new()
	wallet.name = "Wallet"
	add_child(wallet)
	ads = Ads.new()
	ads.name = "Ads"
	add_child(ads)
	store = Store.new()
	store.name = "Store"
	add_child(store)
	_fetch_rules.call_deferred()
	_start_presence.call_deferred()
	for a in OS.get_cmdline_user_args():
		if a == "--reset-save":
			save.reset()
			tries.reset()
		elif a == "--flow":
			flow_test = true
		elif a.begins_with("--server="):
			settings.server_url = a.trim_prefix("--server=")
			settings.save()
		elif a.begins_with("--daily-flow="):
			daily_test = a.trim_prefix("--daily-flow=")
		elif a.begins_with("--sandbox-publish="):
			sandbox_test = "publish:" + a.trim_prefix("--sandbox-publish=")
		elif a.begins_with("--sandbox-play="):
			sandbox_test = "play:" + a.trim_prefix("--sandbox-play=")
		elif a.begins_with("--shot-ws="):
			_shot_ws(a.trim_prefix("--shot-ws="))
		elif a.begins_with("--perf-probe="):
			_perf_probe(a.trim_prefix("--perf-probe="))
	if OS.has_feature("web") and not flow_test and daily_test == "" and sandbox_test == "":
		_open_link_level.call_deferred()
		_web_link_extras.call_deferred()
	_report_push_open.call_deferred()
	if flow_test:
		save.reset()
		tries.reset()
		_run_flow()
	elif sandbox_test != "":
		_run_sandbox_flow.call_deferred()
	elif daily_test != "":
		_run_daily_flow.call_deferred()


## Browser build opened from a share link (/l/CODE -> /play/?level=CODE): go straight to that level.
func _open_link_level() -> void:
	var code := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('level') || ''", true))
	if code == "" or code == "null":
		return
	await get_tree().process_frame
	var err: String = await open_shared(code)
	if err != "":
		push_warning(err)


## Rules from the backend (GET /config): tries, and the economy (features, prices, ads, products) set
## in the admin console. Offline the cached tries rules stay and every paid feature stays off.
func _fetch_rules() -> void:
	if settings.base_url() == "":
		return
	var r: Dictionary = await api.get_json("/config")
	if r.get("ok", false) and r["body"] is Dictionary and r["body"].has("tries_limit"):
		tries.set_rules(int(r["body"]["tries_limit"]), float(r["body"].get("tries_window_hours", 6.0)))
		economy.set_config(r["body"].get("economy", {}))
		economy_changed.emit()
		if economy.on("coins"):
			await wallet.sync()


## Heartbeat: who is online, on which platform / OS, and who used the app on which days (admin).
func _start_presence() -> void:
	if settings.base_url() == "" or flow_test or daily_test != "" or sandbox_test != "":
		return
	while is_inside_tree():
		await api.post_json("/presence", {"device_id": settings.device_id, "name": settings.name,
			"country": Settings.country(), "platform": platform(), "os": OS.get_name() + " " + OS.get_version(),
			"model": OS.get_model_name(), "browser": _browser(), "app_version": str(ProjectSettings.get_setting("application/config/version", ""))})
		await get_tree().create_timer(PRESENCE_S).timeout


static func platform() -> String:
	if OS.has_feature("web"):
		return "web"
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	return OS.get_name().to_lower()


static func _browser() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("navigator.userAgent", true)).substr(0, 300)


## Web links: ?ref=CODE (invite: claim it for this new player), ?paid=1 (back from Stripe checkout).
func _web_link_extras() -> void:
	var ref := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('ref') || ''", true))
	var paid := str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('paid') || ''", true))
	if ref != "" and ref != "null":
		await get_tree().create_timer(3.0).timeout  # after the wallet exists
		var r: Dictionary = await wallet.claim_referral(ref.to_upper())
		_toast_any(("Invite accepted: +%d coins" % int(r.get("coins_added", 0))) if r["ok"] else "")
	if paid == "1":
		await get_tree().create_timer(3.0).timeout
		await wallet.sync()
		_toast_any("Thanks! Your purchase is in your wallet.")


## A notification was tapped: tell the server (open rate per campaign in the admin console).
## Web: /play/?push=<recipient id> (set by the service worker). Android: the plugin's launch data.
func _report_push_open() -> void:
	var rcpt := ""
	if OS.has_feature("web"):
		rcpt = str(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('push') || ''", true))
	elif Engine.has_singleton("TinkerPush") and Engine.get_singleton("TinkerPush").has_method("launchData"):
		rcpt = str(Engine.get_singleton("TinkerPush").launchData())
	if rcpt != "" and rcpt != "null" and settings.base_url() != "":
		await api.post_json("/push/event", {"rcpt": rcpt, "event": "opened", "device_id": settings.device_id})


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_report_push_open()  # Android: the app was brought back by tapping a notification


func _toast_any(t: String) -> void:
	if t == "":
		return
	var s := get_tree().current_scene
	if s and s.has_method("_toast"):
		s._toast(t)


## Scene changes are deferred so the input event that triggered them (a button release) finishes
## before its scene is freed.
func open_level(number: int) -> void:
	_nav_gen += 1
	level_number = number
	daily = {}
	sandbox = {}
	get_tree().change_scene_to_file.call_deferred(LEVEL)


func open_world_select() -> void:
	_nav_gen += 1
	level_number = 0
	daily = {}
	sandbox = {}
	get_tree().change_scene_to_file.call_deferred(WORLD_SELECT)


func open_sandbox() -> void:
	_nav_gen += 1
	level_number = 0
	daily = {}
	sandbox = {}
	get_tree().change_scene_to_file.call_deferred(SANDBOX)


## Sandbox editor ("edit": build the layout) or author play-test ("verify": solve it to publish).
func open_sandbox_level(mode: String, index: int) -> void:
	_nav_gen += 1
	level_number = 0
	daily = {}
	sandbox = {"mode": mode, "index": index}
	get_tree().change_scene_to_file.call_deferred(LEVEL)


## Fetch a shared level by its code and play it. Returns "" or an error message.
func open_shared(code: String) -> String:
	code = code.strip_edges().to_lower()
	_nav_gen += 1
	var my_gen := _nav_gen
	var r: Dictionary = await api.get_json("/level/" + code.uri_encode())
	if my_gen != _nav_gen:
		return ""
	if not r["ok"]:
		return "Level %s: %s" % [code, str(r["error"])]
	var lv: Dictionary = r["body"]["level"]
	if LevelData.validate(lv) != "":
		return "That level is invalid"
	level_number = 0
	daily = {}
	sandbox = {"mode": "shared", "code": code, "level": lv, "author_parts": int(r["body"].get("author_parts", 0))}
	get_tree().change_scene_to_file.call_deferred(LEVEL)
	return ""


## Public link for a published level (opens the browser build on it; see server GET /l/:id).
func share_link(code: String) -> String:
	return settings.base_url() + "/l/" + code


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
	sandbox = {}
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


## Power check (CI): with nobody touching the screen, how many frames does the current screen render
## per second? Prints "PERF rendered_per_s=… process_per_s=…" and quits. Arg: "<scene>" or "level:<file>".
func _perf_probe(what: String) -> void:
	await get_tree().process_frame
	if what.begins_with("level:"):
		open_level(int(what.trim_prefix("level:")))
	await get_tree().create_timer(4.0).timeout  # settle (map roll, music start)
	var drawn := [0]
	var cb := func() -> void: drawn[0] += 1
	RenderingServer.frame_post_draw.connect(cb)
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(5.0).timeout
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("PERF %s rendered_per_s=%.1f process_per_s=%.1f" % [what, drawn[0] / secs, (Engine.get_process_frames() - f0) / secs])
	get_tree().quit(0)


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


# ------------------------------------------------------------------ sandbox test (CI): phone A -> phone B
## A (--sandbox-publish=FILE): map -> Sandbox -> New level -> build campaign level 1's layout ->
##   Next -> player gets 1 plank, 1 slot -> Solve it -> solve -> Publish -> code written to FILE.
## B (--sandbox-play=CODE, a different install): open the code (what the share link does) -> solve
##   -> Remix opens the editor with the same layout. Prints SANDBOX PASS / FAIL.
func _run_sandbox_flow() -> void:
	var kind := sandbox_test.get_slice(":", 0)
	var arg := sandbox_test.substr(kind.length() + 1)
	var ref := LevelData.load_from_file(Campaign.path_for(1))
	if kind == "publish":
		var ws := await _wait_scene("WorldSelect")
		await _tap(ws.find_child("SandboxButton", true, false))
		var sb := await _wait_scene("SandboxScreen")
		_flow_assert(sb != null, "map -> Sandbox")
		await _tap(sb.find_child("NewLevel", true, false))
		var ed := await _wait_scene("LevelScreen")
		_flow_assert(ed != null and ed.mode == "edit", "New level opens the editor")
		for pl in ref.fixed:
			ed.placements.append(pl.duplicate_placement())
		ed.sim.set_player_parts(ed.placements)
		ed._refresh_hud()
		await _tap(ed.setup_btn)
		await get_tree().process_frame
		var su: Node = ed.hud.get_node_or_null("SandboxSetup")
		_flow_assert(su != null, "Next opens the level setup")
		su._title.text = "CI machine"
		su._set_count("plank", 1)
		su._set_slots(1)
		await _tap(su.find_child("SolveToPublish", true, false))
		var vf := await _wait_scene("LevelScreen")
		_flow_assert(vf != null and vf != ed and vf.mode == "verify", "Solve it opens the author test")
		_flow_assert(vf.level.fixed.size() == ref.fixed.size(), "test level has the built layout")
		for pl in ref.reference_solution:
			vf.placements.append(pl.duplicate_placement())
		vf.sim.set_player_parts(vf.placements)
		vf._start_run()
		var o: Dictionary = await vf.sim.finished
		await get_tree().process_frame
		_flow_assert(o["result"] == "goal" and vf.publish_btn.visible, "author solves it; Publish offered")
		await _tap(vf.publish_btn)
		for i in 600:
			if vf._published_code != "":
				break
			await get_tree().process_frame
		_flow_assert(vf._published_code.length() == 8, "published with code '%s'" % vf._published_code)
		var f := FileAccess.open(arg, FileAccess.WRITE)
		f.store_string(vf._published_code)
		f.close()
	else:
		var err: String = await open_shared(arg)
		_flow_assert(err == "", "phone B opens code %s (%s)" % [arg, err])
		var ls := await _wait_scene("LevelScreen")
		_flow_assert(ls != null and ls.mode == "shared", "shared level opened")
		for pl in ref.reference_solution:
			ls.placements.append(pl.duplicate_placement())
		ls.sim.set_player_parts(ls.placements)
		ls._start_run()
		var o: Dictionary = await ls.sim.finished
		await get_tree().process_frame
		_flow_assert(o["result"] == "goal", "phone B solves the shared level")
		_flow_assert(ls.remix_btn.visible, "Remix offered")
		await _tap(ls.remix_btn)
		var ed := await _wait_scene("LevelScreen")
		_flow_assert(ed != null and ed != ls and ed.mode == "edit" and ed.placements.size() == ref.fixed.size(), "Remix opens the editor with the layout")
	print("SANDBOX %s" % ("PASS" if _flow_ok else "FAIL"))
	get_tree().quit(0 if _flow_ok else 1)
