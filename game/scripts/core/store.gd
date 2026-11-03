class_name Store
extends Node
## Store — buying coin packs and no-ads passes. Which way depends on the platform and the admin console:
##   test mode           : POST /purchase/test (free, booked as TEST) — until the stores are live.
##   Android + Play      : Google Play Billing (our TinkerPush plugin, billing-ktx 8) -> the purchase token is
##                         sent to POST /purchase/google, which verifies it with Google and credits.
##   Web (PWA) + Stripe  : POST /purchase/stripe returns a Checkout URL; coins arrive by webhook.
##   iOS                 : App Store, once the Apple account exists (server returns 501 until then).
## buy() returns {"ok", "error", "pending"}; the wallet updates itself when the server credits.

signal purchased(product_id: String)

var _billing: Object = null  # the TinkerPush Android plugin (push + Play Billing)
var _pending := {}  # purchase token -> product id (awaiting server verification)
var _connected := false
var _last_error := ""


func _ready() -> void:
	if Engine.has_singleton("TinkerPush") and Engine.get_singleton("TinkerPush").has_method("billingBuy"):
		_billing = Engine.get_singleton("TinkerPush")
		_billing.billing_connected.connect(func() -> void: _connected = true)
		_billing.billing_disconnected.connect(func() -> void: _connected = false)
		_billing.billing_purchase.connect(_on_purchase)
		_billing.billing_error.connect(func(code: int, msg: String) -> void: _last_error = msg if code != 1 else "")
		_billing.billingConnect()


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
				_billing.billingConnect()
				await get_tree().create_timer(2.0).timeout
			_last_error = ""
			_billing.billingBuy(product_id)
			await get_tree().create_timer(0.8).timeout
			if _last_error != "":
				return {"ok": false, "error": "Google Play: " + _last_error}
			return {"ok": true, "pending": true}
		"stripe":
			var r: Dictionary = await App.wallet.post("/purchase/stripe", {"product": product_id})
			if r["ok"] and str(r.get("url", "")) != "":
				OS.shell_open(str(r["url"]))
				return {"ok": true, "pending": true}
			return r
	return {"ok": false, "error": "Purchases aren't available on this device yet."}


## Play reports a completed purchase: the server verifies the token with Google, consumes it and
## credits the wallet (idempotent per order, so a re-sent token is never credited twice).
func _on_purchase(product_id: String, token: String) -> void:
	if _pending.has(token):
		return
	_pending[token] = product_id
	var r: Dictionary = await App.wallet.post("/purchase/google", {"product": product_id, "token": token})
	_pending.erase(token)
	if r["ok"]:
		purchased.emit(product_id)
