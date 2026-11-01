extends Control
## BoardScreen — the Daily leaderboard for App.board_date: Global / Country, top N plus my own row.
## Ranking is the server's: fewest parts, then fastest time.

var date := ""
var scope := "global"
var loaded := false
var me_rank := 0
var _list: VBoxContainer
var _status: Label
var _tabs: Dictionary = {}
var _gen := 0  # request generation: a response for an older tab press is discarded


func _ready() -> void:
	name = "BoardScreen"
	date = App.board_date if App.board_date != "" else DailyStore.today_utc()
	UiKit.background(self)
	var h := UiKit.top_bar(self, "Daily %s" % date, func() -> void: App.open_world_select())
	var streak := UiKit.label("Streak %d" % App.daily_store.streak(), 32, UiKit.PANEL_TXT)
	streak.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(streak)

	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_top = 184
	body.offset_left = 24
	body.offset_right = -24
	body.offset_bottom = -24
	body.add_theme_constant_override("separation", 16)
	add_child(body)

	var mine: Dictionary = App.daily_store.day(date)
	if mine.get("submitted", false):
		body.add_child(UiKit.label("You: %d part%s · %s" % [int(mine["parts"]), "" if int(mine["parts"]) == 1 else "s", _fmt(int(mine["ms"]))], 40))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 16)
	body.add_child(tabs)
	for s in ["global", "country"]:
		var b := UiKit.button("World" if s == "global" else Settings.country(), UiKit.MUTED, UiKit.PANEL_TXT, 96)
		b.custom_minimum_size = Vector2(240, 96)
		b.pressed.connect(_load.bind(s))
		tabs.add_child(b)
		_tabs[s] = b

	_status = UiKit.label("Loading…", 32)
	body.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_load("global")


func _load(s: String) -> void:
	scope = s
	for k in _tabs:
		_tabs[k].add_theme_stylebox_override("normal", UiKit.style(UiKit.GO if k == s else UiKit.MUTED))
	_status.text = "Loading…"
	for c in _list.get_children():
		c.queue_free()
	var q := "/board/%s?scope=%s&device_id=%s" % [date, s, App.settings.device_id]
	if s == "country":
		q += "&country=" + Settings.country()
	_gen += 1
	var my_gen := _gen
	var r: Dictionary = await App.api.get_json(q)
	if my_gen != _gen:
		return  # the player switched tabs while this was in flight
	if not r["ok"]:
		_status.text = "Board unavailable: " + str(r["error"])
		loaded = true
		return
	var b: Dictionary = r["body"]
	var rows: Array = b.get("rows", [])
	_status.text = "%d player%s" % [rows.size(), "" if rows.size() == 1 else "s"] if rows.size() < 100 else "Top 100"
	var me_in_top := false
	for row in rows:
		var is_me: bool = bool(row.get("is_me", false))
		me_in_top = me_in_top or is_me
		_list.add_child(_row(row, is_me))
	var me: Variant = b.get("me")
	me_rank = int(me["rank"]) if me is Dictionary else 0
	if me is Dictionary and not me_in_top:
		_list.add_child(UiKit.label("…", 32))
		_list.add_child(_row(me, true))
	loaded = true


func _row(row: Dictionary, is_me: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.style(UiKit.GO if is_me else Color("fffdf7"), 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	p.add_child(h)
	var rank := UiKit.label("#%d" % int(row["rank"]), 34)
	rank.custom_minimum_size.x = 120
	h.add_child(rank)
	var who := str(row.get("name", ""))
	if who == "":
		who = "Player " + str(row.get("player", "")).substr(0, 4)
	var n := UiKit.label("%s  %s" % [who, str(row.get("country", ""))], 34)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(UiKit.label("%d pt · %s" % [int(row["parts"]), _fmt(int(row["ms"]))], 34))
	return p


static func _fmt(ms: int) -> String:
	var t := ms / 1000
	return "%d:%02d" % [t / 60, t % 60] if t >= 60 else "%.1fs" % (ms / 1000.0)
