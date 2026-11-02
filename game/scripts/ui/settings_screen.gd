extends Control
## SettingsScreen — everything configurable lives here (no values hard-coded in scripts):
## server URL (with a connection test), board name, daily reminder, music and sound volume, and the
## device id (read-only). Volumes apply and save as the slider moves.

var _url: LineEdit
var _name: LineEdit
var _push: Button
var _status: Label


func _ready() -> void:
	App.audio.play_music("menu")
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

	v.add_child(_volume_row("Music", "music_volume", "MusicSlider"))
	v.add_child(_volume_row("Sounds", "sfx_volume", "SoundSlider"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	v.add_child(row)
	var vib := UiKit.button("", UiKit.GO, UiKit.INK, 100)
	vib.name = "VibrationToggle"
	vib.toggle_mode = true
	vib.button_pressed = App.settings.haptics
	vib.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var paint_vib := func() -> void:
		vib.text = "Vibration: " + ("On" if vib.button_pressed else "Off")
		for k in ["normal", "hover", "pressed"]:
			vib.add_theme_stylebox_override(k, UiKit.style(UiKit.GO if vib.button_pressed else Color("c9c2b6")))
	paint_vib.call()
	vib.toggled.connect(func(on: bool) -> void:
		App.settings.haptics = on
		App.settings.save()
		paint_vib.call()
		App.audio.buzz(30))
	row.add_child(vib)
	var tut := UiKit.button("Show tutorial again", UiKit.MUTED, UiKit.PANEL_TXT, 100)
	tut.name = "TutorialReset"
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut.add_theme_font_size_override("font_size", 28)
	tut.pressed.connect(func() -> void:
		App.settings.tutorial_done = false
		App.settings.save()
		_status.text = "The tutorial will show on level 1.")
	row.add_child(tut)

	var save := UiKit.button("Save", UiKit.GO, UiKit.INK, 120)
	save.name = "SaveButton"
	save.pressed.connect(_save)
	v.add_child(save)

	_status = UiKit.label("", 30)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	v.add_child(UiKit.label("Device %s · %s" % [App.settings.device_id.substr(0, 8), Settings.country()], 26, Color(UiKit.INK, 0.6)))


func _volume_row(title: String, key: String, node_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	var l := UiKit.label(title, 34)
	l.custom_minimum_size.x = 170
	row.add_child(l)
	var sl := HSlider.new()
	sl.name = node_name
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(App.settings.get(key))
	sl.custom_minimum_size = Vector2(0, 96)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("c9c2b6")
	track.set_corner_radius_all(10)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	var fill := track.duplicate()
	fill.bg_color = UiKit.GO
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_icon_override("grabber", _knob())
	sl.add_theme_icon_override("grabber_highlight", _knob())
	var pct := UiKit.label("", 30, Color(UiKit.INK, 0.7))
	pct.custom_minimum_size.x = 90
	pct.text = "%d%%" % roundi(sl.value * 100.0)
	sl.value_changed.connect(func(val: float) -> void:
		App.settings.set(key, val)
		App.audio.apply_volumes()
		pct.text = "%d%%" % roundi(val * 100.0))
	sl.drag_ended.connect(func(_changed: bool) -> void:
		App.settings.save()
		if key == "sfx_volume":
			App.audio.sfx("place"))  # hear the new level
	row.add_child(sl)
	row.add_child(pct)
	return row


## Round ink-outlined slider knob, drawn once into a texture (touch-sized).
static func _knob() -> Texture2D:
	var d := 56
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := Vector2(d / 2.0, d / 2.0)
	for y in d:
		for x in d:
			var r := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if r <= d / 2.0 - 1.0:
				img.set_pixel(x, y, UiKit.INK if r > d / 2.0 - 7.0 else Color("fbf6ea"))
	return ImageTexture.create_from_image(img)


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
	var need_token: bool = App.push.status() != "granted" or App.fcm_token == ""
	if App.settings.push_enabled and App.push.supported() and need_token:
		# Not allowed yet: asks the OS/browser. Allowed but no token this launch (reminders were off at
		# startup, so none was fetched): fetches one silently. Either way the token is then registered.
		App.push.request()
		_status.text = "Saved." if App.push.status() == "granted" else "Saved. Allow notifications to get the daily reminder."
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
