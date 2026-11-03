class_name Wallet
extends Node
## Wallet — the player's coins, no-ads pass and invite code. The SERVER owns the balance (economy.js);
## this node mirrors it, caches the last known state in user://wallet.json for display offline, and
## wraps every wallet call. Each call returns {"ok", "error", ...server body}.

signal changed

const PATH := "user://wallet.json"

var coins: int = 0
var no_ads: bool = false
var ref_code: String = ""
var streak: int = 0
var bonus_today: bool = false
var ads_left_today: int = 0
var bought: Array = []
var synced: bool = false
var _path := PATH


func _ready() -> void:
	if FileAccess.file_exists(_path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if d is Dictionary:
			_apply(d)


func _apply(w: Dictionary) -> void:
	coins = int(w.get("coins", coins))
	no_ads = bool(w.get("no_ads", no_ads))
	ref_code = str(w.get("ref_code", ref_code))
	streak = int(w.get("streak", streak))
	bonus_today = bool(w.get("bonus_today", bonus_today))
	ads_left_today = int(w.get("ads_left_today", ads_left_today))
	bought = w.get("bought", bought)


func _store(w: Dictionary) -> void:
	_apply(w)
	synced = true
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(w))
	changed.emit()


func _call(path: String, body: Dictionary = {}) -> Dictionary:
	if not has_node("/root/App") or App.settings.base_url() == "":
		return {"ok": false, "error": "offline"}
	body["device_id"] = App.settings.device_id
	var r: Dictionary = await App.api.post_json(path, body)
	var b: Dictionary = r["body"] if r["body"] is Dictionary else {}
	if b.get("wallet") is Dictionary:
		_store(b["wallet"])
	var out := b.duplicate()
	out["ok"] = r["ok"]
	out["status"] = r["status"]
	out["error"] = r["error"]
	return out


func sync() -> Dictionary:
	return await _call("/wallet")


func claim_bonus() -> Dictionary:
	return await _call("/wallet/bonus")


## The server replays the solution on the shipped level before paying (no free coins for unplayed levels).
func earn_campaign(level: int, placements: Array) -> Dictionary:
	var sol := []
	for p in placements:
		sol.append({"part": p.part, "x": p.cell.x, "y": p.cell.y, "rot": p.rot})
	return await _call("/wallet/earn", {"reason": "campaign", "level": level, "solution": sol})


func earn_daily(date: String) -> Dictionary:
	return await _call("/wallet/earn", {"reason": "daily", "date": date})


## item: extra_try | refill | hint | skip. ok=false with status 402 when the balance is short.
func spend(item: String, ref: String = "") -> Dictionary:
	var key: String = {"extra_try": "extra_try_cost", "refill": "refill_cost", "hint": "hint_cost", "skip": "skip_cost"}.get(item, "")
	var body := {"item": item, "ref": ref}
	if key != "" and App.economy.cfg.has("economy"):
		body["expected_cost"] = App.economy.num(key)  # the price the player saw; the server refuses another one
	# One operation id per purchase: if the response is lost the same id is retried and the server
	# answers "already done" instead of charging twice, so the caller can still deliver what was bought.
	body["op"] = "%08x%08x" % [randi(), randi()]
	var r: Dictionary = await _call("/wallet/spend", body.duplicate())
	for attempt in 2:
		if int(r.get("status", 0)) != 0 or str(r.get("error", "")) == "offline":
			break
		await App.get_tree().create_timer(1.0 + attempt).timeout
		r = await _call("/wallet/spend", body.duplicate())
	if int(r.get("status", 0)) == 409 and r.has("cost"):
		await App._fetch_rules()
		r["error"] = "The price changed to %d coins. Tap again to buy." % int(r["cost"])
	return r


func ad_reward(reward: String, provider: String) -> Dictionary:
	return await _call("/ads/reward", {"reward": reward, "provider": provider})


func claim_referral(code: String) -> Dictionary:
	return await _call("/referral/claim", {"code": code})


func invite_link() -> String:
	return App.settings.base_url() + "/i/" + ref_code if ref_code != "" else ""


func post(path: String, body: Dictionary) -> Dictionary:
	return await _call(path, body)
