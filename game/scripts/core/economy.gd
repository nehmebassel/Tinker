class_name Economy
extends RefCounted
## Economy — the business rules the server sends in GET /config ("economy"), all set in the admin
## console (/admin/ui): which features are on, prices, rewards, ads and products. Offline or before
## the first fetch everything paid is OFF (cfg empty), so the game never offers what it can't deliver.

var cfg: Dictionary = {}


func set_config(c: Variant) -> void:
	cfg = c if c is Dictionary else {}


func on(feature: String) -> bool:
	var f: Dictionary = cfg.get("features", {})
	if feature != "coins" and not bool(f.get("coins", false)) and feature in ["daily_bonus", "extra_tries", "hints", "skip", "referrals"]:
		return false
	return bool(f.get(feature, false))


func num(key: String, fallback: int = 0) -> int:
	return int(cfg.get("economy", {}).get(key, fallback))


func ads() -> Dictionary:
	return cfg.get("ads", {})


func payments() -> Dictionary:
	return cfg.get("payments", {})


func products() -> Array:
	return cfg.get("products", [])


func product(id: String) -> Dictionary:
	for p in products():
		if str(p.get("id", "")) == id:
			return p
	return {}
