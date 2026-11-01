class_name Push
extends Node
## Push — the daily reminder on both platforms, behind one API:
##   Android: the TinkerPush plugin (android/tinker_push) — FCM token, POST_NOTIFICATIONS permission.
##   Web/PWA: window.tinkerPush from /play/push.js — FCM token via the browser's Push API.
## When a token arrives it is handed to App.sync_push(), which registers it with the server.

signal token_changed(token: String)

var _plugin: Object = null
var _polling := false
var _poll_left := 0.0  # seconds of web polling left; a new request extends a poll already running


func _ready() -> void:
	if Engine.has_singleton("TinkerPush"):
		_plugin = Engine.get_singleton("TinkerPush")
		_plugin.token_received.connect(_on_token)
		_plugin.push_error.connect(func(msg: String) -> void: push_warning("TinkerPush: " + msg))
		if _plugin.hasPermission() and App.settings.push_enabled:
			_plugin.fetchToken()  # silent refresh; never prompts at startup
	elif OS.has_feature("web"):
		_poll_web(20.0)  # push.js fetches a token silently when permission was granted before


func supported() -> bool:
	if _plugin != null:
		return true
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.tinkerPush ? window.tinkerPush.status : 'unsupported'", true)) != "unsupported"
	return false


## "granted", "default" (not asked yet), "denied", "unsupported" or "error".
func status() -> String:
	if _plugin != null:
		return "granted" if _plugin.hasPermission() else "default"
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.tinkerPush ? window.tinkerPush.status : 'unsupported'", true))
	return "unsupported"


## Ask for permission if needed and get a token. Call from a player action (Settings / board button).
func request() -> void:
	if _plugin != null:
		_plugin.requestToken()
	elif OS.has_feature("web"):
		JavaScriptBridge.eval("window.tinkerPush && window.tinkerPush.prompt()", true)
		_poll_web(120.0)


func _poll_web(seconds: float) -> void:
	_poll_left = maxf(_poll_left, seconds)
	if _polling:
		return  # the running loop picks up the extended deadline
	_polling = true
	while _poll_left > 0.0:
		var t := str(JavaScriptBridge.eval("window.tinkerPush ? window.tinkerPush.token : ''", true))
		if t != "" and t != "null":
			_on_token(t)
			break
		await get_tree().create_timer(1.0).timeout
		_poll_left -= 1.0
	_poll_left = 0.0
	_polling = false


func _on_token(t: String) -> void:
	if t == App.fcm_token:
		return
	App.fcm_token = t
	token_changed.emit(t)
	App.sync_push()
