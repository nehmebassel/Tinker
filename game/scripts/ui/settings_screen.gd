extends Control
## SettingsScreen — everything configurable lives here (no values hard-coded in scripts):
## server URL (with a connection test), board name, daily reminder, and the device id (read-only).

var _url: LineEdit
var _name: LineEdit
var _push: Button
var _status: Label


func _ready() -> void:
	name = "SettingsScreen"
	UiKit.background(self)
	UiKit.top_bar(self, "Settings", func() -> void: App.open_world_select())
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 200
	v.offset_left = 32
	v.offset_right = -32
	v.add_theme_constant_override("separation", 20)
	add_child(v)

	v.add_child(UiKit.label("Server", 36))
	_url = _edit(App.settings.server_url, "https://…")
	v.add_child(_url)
	var test := UiKit.button("Test connection", UiKit.MUTED, UiKit.PANEL_TXT, 100)
	test.pressed.connect(_test)
	v.add_child(test)

	v.add_child(UiKit.label("Name on boards", 36))
	_name = _edit(App.settings.name, "optional")
	_name.max_length = 24
	v.add_child(_name)

	_push = UiKit.button("", UiKit.GO, UiKit.INK, 100)
	_push.name = "ReminderToggle"
	_push.toggle_mode = true
	_push.button_pressed = App.settings.push_enabled
	_push.toggled.connect(func(_on: bool) -> void: _paint_push())
	v.add_child(_push)
	_paint_push()

	var save := UiKit.button("Save", UiKit.GO, UiKit.INK, 120)
	save.name = "SaveButton"
	save.pressed.connect(_save)
	v.add_child(save)

	_status = UiKit.label("", 30)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.add_child(UiKit.label("Device %s · %s" % [App.settings.device_id.substr(0, 8), Settings.country()], 26, Color(UiKit.INK, 0.6)))


func _paint_push() -> void:
	var on := _push.button_pressed
	_push.text = "Daily reminder: " + ("On" if on else "Off")
	var st := UiKit.style(UiKit.GO if on else Color("c9c2b6"))
	for k in ["normal", "hover", "pressed"]:
		_push.add_theme_stylebox_override(k, st)


func _edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size.y = 96
	e.add_theme_font_size_override("font_size", 34)
	return e


func _save() -> void:
	App.settings.server_url = _url.text.strip_edges()
	App.settings.name = _name.text.strip_edges().substr(0, 24)
	App.settings.push_enabled = _push.button_pressed
	App.settings.save()
	if App.settings.push_enabled and App.push.supported() and App.push.status() != "granted":
		App.push.request()  # asks the OS/browser, then registers the token
		_status.text = "Saved. Allow notifications to get the daily reminder."
	else:
		App.sync_push()
		_status.text = "Saved."
	if App.settings.push_enabled and App.push.status() == "denied":
		_status.text = "Saved, but notifications are blocked for Tinker in your phone/browser settings."


func _test() -> void:
	App.settings.server_url = _url.text.strip_edges()
	_status.text = "Testing…"
	var r: Dictionary = await App.api.get_json("/health")
	_status.text = ("Connected. Server day: %s" % r["body"].get("today", "?")) if r["ok"] else ("Failed: " + str(r["error"]))
