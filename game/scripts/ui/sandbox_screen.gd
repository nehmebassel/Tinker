extends Control
## SandboxScreen — M5 home: build your own levels, publish them as a link, play and remix others'.
##   New level        -> editor (every part, unlimited) -> Next: goal / player parts / slots ->
##                       solve it yourself -> Publish -> code + link (/l/CODE opens it in a browser)
##   Play a code      -> any published level by its 8-letter code (or the link)
##   My levels        -> drafts and published levels on this device: Edit, Play, Copy link, Delete
##   Community        -> newest published levels (GET /levels/recent)

var _code: LineEdit
var _status: Label
var _mine: VBoxContainer
var _community: VBoxContainer


func _ready() -> void:
	App.audio.play_music("map")
	UiKit.background(self)
	UiKit.top_bar(self, "Sandbox", func() -> void: App.open_world_select())
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 190
	scroll.offset_left = 28
	scroll.offset_right = -28
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 20)
	scroll.add_child(v)

	var new_btn := UiKit.button("+  New level", UiKit.GO, UiKit.INK, 130)
	new_btn.name = "NewLevel"
	new_btn.pressed.connect(func() -> void:
		var idx := App.sandbox_store.add(SandboxStore.new_draft())
		App.open_sandbox_level("edit", idx))
	v.add_child(new_btn)

	v.add_child(UiKit.label("Play a code or link", 34))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_code = LineEdit.new()
	_code.name = "CodeField"
	_code.placeholder_text = "e.g. k3x9ab2q"
	_code.custom_minimum_size.y = 100
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.add_theme_font_size_override("font_size", 36)
	row.add_child(_code)
	var play := UiKit.button("Play", UiKit.ACCENT, UiKit.INK, 100)
	play.custom_minimum_size.x = 180
	play.pressed.connect(_play_code)
	row.add_child(play)
	_status = UiKit.label("", 28, Color(UiKit.INK, 0.75))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)

	v.add_child(UiKit.label("My levels", 40))
	_mine = VBoxContainer.new()
	_mine.add_theme_constant_override("separation", 12)
	v.add_child(_mine)
	_fill_mine()

	v.add_child(UiKit.label("Community", 40))
	_community = VBoxContainer.new()
	_community.add_theme_constant_override("separation", 12)
	v.add_child(_community)
	var pad := Control.new()
	pad.custom_minimum_size.y = 60
	v.add_child(pad)
	_fill_community()


func _play_code() -> void:
	var t := _code.text.strip_edges()
	# Accept a pasted link too: .../l/CODE or ...?level=CODE
	for sep in ["/l/", "level="]:
		if t.contains(sep):
			t = t.get_slice(sep, 1).get_slice("&", 0).get_slice("/", 0)
	if t.length() != 8:
		_status.text = "A level code has 8 letters and digits."
		return
	_status.text = "Loading…"
	var err: String = await App.open_shared(t)
	if err != "":
		_status.text = err


func _row(title: String, sub: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UiKit.label(title, 32)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(t)
	col.add_child(UiKit.label(sub, 24, Color(UiKit.INK, 0.6)))
	h.add_child(col)
	return h


func _small(text: String, fill: Color, cb: Callable) -> Button:
	var b := UiKit.button(text, fill, UiKit.INK if fill != UiKit.MUTED else UiKit.PANEL_TXT, 90)
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size.x = 120
	b.pressed.connect(cb)
	return b


func _fill_mine() -> void:
	for c in _mine.get_children():
		c.queue_free()
	var drafts: Array = App.sandbox_store.drafts
	if drafts.is_empty():
		_mine.add_child(UiKit.label("Nothing yet. Tap New level and build a machine.", 28, Color(UiKit.INK, 0.6)))
		return
	for i in range(drafts.size() - 1, -1, -1):
		var d: Dictionary = drafts[i]
		var code := str(d.get("published_id", ""))
		var sub := ("Published · code %s" % code) if code != "" else ("%d parts placed · draft" % d.get("fixed", []).size())
		var h := _row(str(d.get("title", "")), sub)
		var idx := i
		h.add_child(_small("Edit", UiKit.MUTED, func() -> void: App.open_sandbox_level("edit", idx)))
		if code != "":
			h.add_child(_small("Link", UiKit.GO, func() -> void:
				DisplayServer.clipboard_set(App.share_link(code))
				_status.text = "Copied: " + App.share_link(code)))
		else:
			h.add_child(_small("Test", UiKit.GO, func() -> void:
				var p := SandboxStore.problem(App.sandbox_store.drafts[idx])
				if p != "":
					_status.text = p
				else:
					App.open_sandbox_level("verify", idx)))
		h.add_child(_small("Delete", Color("ff8a8a"), func() -> void:
			App.sandbox_store.remove(idx)
			_fill_mine()))
		_mine.add_child(h)


func _fill_community() -> void:
	var loading := UiKit.label("Loading…", 28, Color(UiKit.INK, 0.6))
	_community.add_child(loading)
	var r: Dictionary = await App.api.get_json("/levels/recent?limit=20")
	if not is_instance_valid(loading):
		return
	loading.queue_free()
	if not r["ok"]:
		_community.add_child(UiKit.label("Offline: " + str(r["error"]), 26, Color(UiKit.INK, 0.6)))
		return
	var rows: Array = r["body"].get("levels", [])
	if rows.is_empty():
		_community.add_child(UiKit.label("No shared levels yet. Be the first!", 28, Color(UiKit.INK, 0.6)))
	for x in rows:
		var code := str(x.get("id", ""))
		var h := _row(str(x.get("title", "")), "%s · goal %s · %d plays · author used %d" % [code, x.get("goal", ""), int(x.get("plays", 0)), int(x.get("author_parts", 0))])
		h.add_child(_small("Play", UiKit.ACCENT, func() -> void:
			_status.text = "Loading…"
			var err: String = await App.open_shared(code)
			if err != "":
				_status.text = err))
		_community.add_child(h)
