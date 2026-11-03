class_name Store
extends Node
## Store — buying coin packs and no-ads passes. Which way depends on the platform and the admin console:
##   test mode           : POST /purchase/test (free, booked as TEST) — until the stores are live.
##   Android + Play      : Google Play Billing (GodotGooglePlayBilling plugin) -> the purchase token is
##                         sent to POST /purchase/google, which verifies it with Google and credits.
##   Web (PWA) + Stripe  : POST /purchase/stripe returns a Checkout URL; coins arrive by webhook.
##   iOS                 : App Store, once the Apple account exists (server returns 501 until then).
## buy() returns {"ok", "error", "pending"}; the wallet updates itself when the server credits.

signal purchased(product_id: String)

var _billing: Object = null
var _pending := {}  # purchase token -> product id (awaiting server verification)
var _connected := false


func _ready() -> void:
	if Engine.has_singleton("GodotGooglePlayBilling"):
		_billing = Engine.get_singleton("GodotGooglePlayBilling")
		_billing.connected.connect(func() -> void: _connected = true)
		_billing.disconnected.connect(func() -> void: _connected = false)
		_billing.purchases_updated.connect(_on_purchases)
		_billing.purchase_error.connect(func(code: int, msg: String) -> void: push_warning("billing %d %s" % [code, msg]))
		_billing.startConnection()


func method() -> String:
	var p := App.economy.payments()
	if str(p.get("mode", "test")) == "test":
		return "test"
	if OS.has_feature("android") and bool(p.get("google_play", false)) and _billing != null:
		return "google_play"
	if OS.has_feature("web") and bool(p.get("stripe", false)):
		return "stripe"
	if OS.has_feature("ios") and bool(p.get("apple", false)):
		return "apple"
	return ""


func available() -> bool:
	return App.economy.on("purchases") and method() != ""


func buy(product_id: String) -> Dictionary:
	match method():
		"test":
			var r: Dictionary = await App.wallet.post("/purchase/test", {"product": product_id})
			if r["ok"]:
				purchased.emit(product_id)
			return r
		"google_play":
			if not _connected:
				_billing.startConnection()
				await get_tree().create_timer(2.0).timeout
			var res: Dictionary = _billing.purchase(product_id)
			if int(res.get("status", 1)) != 0:
				return {"ok": false, "error": "Google Play: " + str(res.get("debug_message", "could not start the purchase"))}
			return {"ok": true, "pending": true}
		"stripe":
			var r: Dictionary = await App.wallet.post("/purchase/stripe", {"product": product_id})
			if r["ok"] and str(r.get("url", "")) != "":
				OS.shell_open(str(r["url"]))
				return {"ok": true, "pending": true}
			return r
	return {"ok": false, "error": "Purchases aren't available on this device yet."}


func _on_purchases(purchases: Array) -> void:
	for p in purchases:
		var token := str(p.get("purchase_token", ""))
		var skus: Array = p.get("products", p.get("skus", []))
		if token == "" or skus.is_empty() or _pending.has(token):
			continue
		_pending[token] = skus[0]
		var r: Dictionary = await App.wallet.post("/purchase/google", {"product": str(skus[0]), "token": token})
		_pending.erase(token)
		if r["ok"]:
			purchased.emit(str(skus[0]))
