class_name BoardView
extends VBoxContainer
## BoardView — the leaderboard itself, used by the map's slide-in drawer and the after-Daily board
## screen (2026-11-03, Bassel: "make the board a real board"). Tabs: Today / Yesterday (the Daily,
## fewest parts then fastest) and Campaign (most levels solved, then fewest parts). World / country
## scope for the Daily. Podium colours for the top 3, the player's own row highlighted and, when
## outside the visible top, pinned at the bottom.

const C_CARD := Color("fffdf7")
const C_ME := Color("ffe9a8")
const MEDALS := [Color("f2c94c"), Color("c9d1d9"), Color("d9915a")]

var tab := "today"
var scope := "global"
var loaded := false
var me_rank := 0
var _list: VBoxContainer
var _status: Label
var _pinned: Control
var _tabs: Dictionary = {}
var _scopes: Dictionary = {}
var _gen := 0


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	add_child(tabs)
	for t in [["today", "Today"], ["yesterday", "Yesterday"], ["campaign", "Campaign"]]:
		var b := UiKit.button(t[1], UiKit.MUTED, UiKit.PANEL_TXT, 88)
		b.name = "Tab_" + t[0]
		b.add_theme_font_size_override("font_size", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: load_tab(t[0], scope))
		tabs.add_child(b)
		_tabs[t[0]] = b
	var sc := HBoxContainer.new()
	sc.add_theme_constant_override("separation", 12)
	add_child(sc)
	for s in [["global", "World"], ["country", Settings.country()]]:
		var b := UiKit.button(s[1], UiKit.MUTED, UiKit.PANEL_TXT, 64)
		b.add_theme_font_size_override("font_size", 26)
		b.custom_minimum_size.x = 160
		b.pressed.connect(func() -> void: load_tab(tab, s[0]))
		sc.add_child(b)
		_scopes[s[0]] = b
	_status = UiKit.label("", 28, Color(UiKit.PANEL_TXT, 0.75))
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_pinned = VBoxContainer.new()
	add_child(_pinned)


func _paint() -> void:
	for k in _tabs:
		_paint_btn(_tabs[k], k == tab)
	for k in _scopes:
		_paint_btn(_scopes[k], k == scope)
		_scopes[k].visible = tab != "campaign"


static func _paint_btn(b: Button, on: bool) -> void:
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, UiKit.style(UiKit.GO if on else UiKit.MUTED))
	b.add_theme_color_override("font_color", UiKit.INK if on else UiKit.PANEL_TXT)


func load_tab(t: String, s: String = "global") -> void:
	tab = t
	scope = s
	loaded = false
	_paint()
	_status.text = "Loading…"
	for c in _list.get_children():
		c.queue_free()
	for c in _pinned.get_children():
		c.queue_free()
	_gen += 1
	var my_gen := _gen
	var q := ""
	if t == "campaign":
		q = "/board-campaign?device_id=" + App.settings.device_id
	else:
		var date := DailyStore.today_utc()
		if t == "yesterday":
			date = Time.get_date_string_from_unix_time(Time.get_unix_time_from_system() - 86400)
		if t.begins_with("date:"):
			date = t.trim_prefix("date:")
		q = "/board/%s?scope=%s&device_id=%s" % [date, s, App.settings.device_id]
		if s == "country":
			q += "&country=" + Settings.country()
	var r: Dictionary = await App.api.get_json(q)
	if my_gen != _gen or not is_inside_tree():
		return
	loaded = true
	if not r["ok"]:
		_status.text = "Board unavailable: " + str(r["error"])
		return
	var b: Dictionary = r["body"]
	var rows: Array = b.get("rows", [])
	if rows.is_empty():
		_status.text = "No one on this board yet. Be the first!"
	else:
		_status.text = "%d player%s" % [rows.size(), "" if rows.size() == 1 else "s"] if rows.size() < 100 else "Top 100"
	var me_in := false
	for row in rows:
		me_in = me_in or bool(row.get("is_me", false))
		_list.add_child(_row(row))
	var me: Variant = b.get("me")
	me_rank = int(me["rank"]) if me is Dictionary else 0
	if me is Dictionary and not me_in:
		_pinned.add_child(_row(me))


func _row(row: Dictionary) -> Control:
	var is_me := bool(row.get("is_me", false))
	var rank := int(row.get("rank", 0))
	var p := PanelContainer.new()
	var st := UiKit.style(C_ME if is_me else C_CARD, 22)
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	st.content_margin_left = 14
	st.content_margin_right = 18
	if not is_me:
		st.set_border_width_all(3)
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	# Rank badge: medal for the podium, plain number below.
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(76, 76)
	badge.draw.connect(func() -> void:
		var c := badge.size / 2.0
		if rank >= 1 and rank <= 3:
			badge.draw_circle(c, 34, UiKit.INK)
			badge.draw_circle(c, 29, MEDALS[rank - 1])
			badge.draw_arc(c, 22, 0, TAU, 32, Color(1, 1, 1, 0.5), 3.0)
		var f := ThemeDB.fallback_font
		var s := str(rank)
		var fs := 34 if rank < 100 else 26
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		badge.draw_string(f, c + Vector2(-w / 2.0, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiKit.INK))
	h.add_child(badge)
	var who := str(row.get("name", ""))
	if who == "":
		who = "Player " + str(row.get("player", "")).substr(0, 4)
	if is_me:
		who += " (you)"
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	var n := UiKit.label(who, 34)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(n)
	var cc := str(row.get("country", ""))
	var sub := UiKit.label(cc if cc != "ZZ" else "", 24, Color(UiKit.INK, 0.6))
	col.add_child(sub)
	var stat := VBoxContainer.new()
	stat.add_theme_constant_override("separation", 0)
	h.add_child(stat)
	if row.has("solved"):
		stat.add_child(_stat_label("%d levels" % int(row["solved"]), 32))
		stat.add_child(_stat_label("%d parts" % int(row.get("parts", 0)), 24))
	else:
		var parts := int(row.get("parts", 0))
		stat.add_child(_stat_label("%d part%s" % [parts, "" if parts == 1 else "s"], 32))
		stat.add_child(_stat_label(fmt_ms(int(row.get("ms", 0))), 24))
	return p


static func _stat_label(t: String, size: int) -> Label:
	var l := UiKit.label(t, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func fmt_ms(ms: int) -> String:
	var t := ms / 1000
	return "%d:%02d" % [t / 60, t % 60] if t >= 60 else "%.1f s" % (ms / 1000.0)
