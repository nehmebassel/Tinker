class_name SandboxSetup
extends Control
## SandboxSetup — the editor's "Next" step (M5): name the level, pick the goal, choose which parts
## the PLAYER gets (and how many), and the slot limit. "Solve it to publish" opens the level as a
## player would see it; publishing is only offered once the author has solved it (the server
## replays that solution before accepting the level).

var index: int = -1
var draft: Dictionary
var _title: LineEdit
var _goal_btns: Dictionary = {}
var _counts: Dictionary = {}  # part -> Label
var _slots_lbl: Label
var _status: Label

const GOAL_LABELS := {"basket": "Ball in basket", "candle": "Light the candle", "cheese": "Mouse gets cheese", "pop": "Pop a balloon"}


static func open(parent: Node, p_index: int) -> SandboxSetup:
	var s := SandboxSetup.new()
	s.name = "SandboxSetup"
	s.index = p_index
	parent.add_child(s)
	return s


func _ready() -> void:
	draft = App.sandbox_store.drafts[index].duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.05, 0.14, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 28
	scroll.offset_right = -28
	scroll.offset_top = 60
	scroll.offset_bottom = -40
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var panel := PanelContainer.new()
	var st := UiKit.style(UiKit.PANEL, 32)
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 24
	st.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)

	v.add_child(UiKit.label("Level setup", 50, UiKit.PANEL_TXT))
	v.add_child(UiKit.label("Name", 32, Color(UiKit.PANEL_TXT, 0.8)))
	_title = LineEdit.new()
	_title.text = str(draft.get("title", ""))
	_title.max_length = 40
	_title.custom_minimum_size.y = 90
	_title.add_theme_font_size_override("font_size", 34)
	v.add_child(_title)

	v.add_child(UiKit.label("Goal", 32, Color(UiKit.PANEL_TXT, 0.8)))
	var gg := GridContainer.new()
	gg.columns = 2
	gg.add_theme_constant_override("h_separation", 14)
	gg.add_theme_constant_override("v_separation", 14)
	v.add_child(gg)
	for g in SandboxStore.GOALS:
		var b := UiKit.button(GOAL_LABELS[g], UiKit.MUTED, UiKit.PANEL_TXT, 90)
		b.name = "Goal_" + g
		b.add_theme_font_size_override("font_size", 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			draft["goal"] = {"type": g, "count": 1} if g == "basket" else {"type": g}
			_paint_goals())
		gg.add_child(b)
		_goal_btns[g] = b
	_paint_goals()

	v.add_child(UiKit.label("Parts the player gets", 32, Color(UiKit.PANEL_TXT, 0.8)))
	var pg := GridContainer.new()
	pg.columns = 2
	pg.add_theme_constant_override("h_separation", 24)
	pg.add_theme_constant_override("v_separation", 10)
	v.add_child(pg)
	PartRegistry.ensure_loaded()
	for id in PartRegistry.defs.keys():
		pg.add_child(_counter_row(id))

	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 14)
	sr.add_child(UiKit.label("Slots (parts the player may place)", 30, Color(UiKit.PANEL_TXT, 0.8)))
	var sm := _small("−", func() -> void: _set_slots(int(draft["slots"]) - 1))
	sr.add_child(sm)
	_slots_lbl = UiKit.label("", 36, UiKit.PANEL_TXT)
	_slots_lbl.custom_minimum_size.x = 50
	_slots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sr.add_child(_slots_lbl)
	sr.add_child(_small("+", func() -> void: _set_slots(int(draft["slots"]) + 1)))
	v.add_child(sr)
	_set_slots(int(draft.get("slots", 1)))

	_status = UiKit.label("", 28, Color("ffd43b"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var back := UiKit.button("Keep building", UiKit.MUTED, UiKit.PANEL_TXT, 110)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		_store()
		queue_free())
	row.add_child(back)
	var go := UiKit.button("Solve it to publish", UiKit.GO, UiKit.INK, 110)
	go.name = "SolveToPublish"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_solve)
	row.add_child(go)


func _small(t: String, cb: Callable) -> Button:
	var b := UiKit.button(t, UiKit.MUTED, UiKit.PANEL_TXT, 70)
	b.add_theme_font_size_override("font_size", 40)
	b.pressed.connect(cb)
	return b


func _counter_row(id: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var n := UiKit.label(str(PartRegistry.get_def(id).get("name", id)), 28, UiKit.PANEL_TXT)
	n.custom_minimum_size.x = 170
	h.add_child(n)
	h.add_child(_small("−", func() -> void: _set_count(id, _count(id) - 1)))
	var l := UiKit.label(str(_count(id)), 34, UiKit.PANEL_TXT)
	l.custom_minimum_size.x = 40
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counts[id] = l
	h.add_child(l)
	h.add_child(_small("+", func() -> void: _set_count(id, _count(id) + 1)))
	return h


func _count(id: String) -> int:
	for t in draft["tray"]:
		if t["part"] == id:
			return int(t["count"])
	return 0


func _set_count(id: String, c: int) -> void:
	c = clampi(c, 0, 5)
	var tray: Array = []
	var found := false
	for t in draft["tray"]:
		if t["part"] == id:
			found = true
			if c > 0:
				tray.append({"part": id, "count": c})
		else:
			tray.append(t)
	if not found and c > 0:
		tray.append({"part": id, "count": c})
	draft["tray"] = tray
	_counts[id].text = str(c)
	_set_slots(int(draft["slots"]))


func _set_slots(n: int) -> void:
	var total := 0
	for t in draft["tray"]:
		total += int(t["count"])
	draft["slots"] = clampi(n, 1, maxi(1, total))
	_slots_lbl.text = str(draft["slots"])


func _paint_goals() -> void:
	var g := str(draft.get("goal", {}).get("type", "basket"))
	for k in _goal_btns:
		var on: bool = k == g
		for st in ["normal", "hover", "pressed"]:
			_goal_btns[k].add_theme_stylebox_override(st, UiKit.style(UiKit.GO if on else UiKit.MUTED))
		_goal_btns[k].add_theme_color_override("font_color", UiKit.INK if on else UiKit.PANEL_TXT)


func _store() -> void:
	draft["title"] = _title.text.strip_edges() if _title.text.strip_edges() != "" else "My machine"
	var cur: Dictionary = App.sandbox_store.drafts[index]
	if cur.get("goal") != draft.get("goal") or cur.get("tray") != draft.get("tray") or int(cur.get("slots", 0)) != int(draft["slots"]):
		draft["solution"] = []
		draft["published_id"] = ""
	App.sandbox_store.put(index, draft)


func _solve() -> void:
	_store()
	var p := SandboxStore.problem(draft)
	if p != "":
		_status.text = p
		return
	App.open_sandbox_level("verify", index)
