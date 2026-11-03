extends Control
## BoardScreen — after submitting the Daily: your result as a card (rank, parts, time, streak, coins
## earned) above the full leaderboard (BoardView: Today / Yesterday / Campaign, World / country).

var date := ""
var _view: BoardView
var loaded: bool:
	get:
		return _view != null and _view.loaded
var me_rank: int:
	get:
		return _view.me_rank if _view else 0


func _ready() -> void:
	App.audio.play_music("menu")
	name = "BoardScreen"
	date = App.board_date if App.board_date != "" else DailyStore.today_utc()
	UiKit.background(self)
	var h := UiKit.top_bar(self, "Daily · " + date, func() -> void: App.open_world_select())
	h.add_child(CoinChip.make(112))

	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_top = 184
	body.offset_left = 24
	body.offset_right = -24
	body.offset_bottom = -24
	body.add_theme_constant_override("separation", 18)
	add_child(body)

	var mine: Dictionary = App.daily_store.day(date)
	if mine.get("submitted", false):
		body.add_child(_result_card(mine))
		# The natural moment to offer the reminder: right after today's entry.
		if App.settings.push_enabled and App.push.supported() and App.push.status() == "default":
			var remind := UiKit.button("Remind me tomorrow", UiKit.GO, UiKit.INK, 100)
			remind.name = "RemindButton"
			remind.pressed.connect(func() -> void:
				App.push.request()
				remind.queue_free())
			body.add_child(remind)

	var panel := PanelContainer.new()
	var st := UiKit.style(UiKit.PANEL, 32)
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_view = BoardView.new()
	panel.add_child(_view)
	_view.load_tab("today" if date == DailyStore.today_utc() else "date:" + date)


## Your entry, big and clear: rank badge, parts, time, streak.
func _result_card(mine: Dictionary) -> Control:
	var p := PanelContainer.new()
	var st := UiKit.style(Color("ffe9a8"), 32)
	st.content_margin_top = 18
	st.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	p.add_child(h)
	var rank := int(mine.get("rank", 0))
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(150, 150)
	badge.draw.connect(func() -> void:
		var c := badge.size / 2.0
		badge.draw_circle(c, 70, UiKit.INK)
		badge.draw_circle(c, 63, BoardView.MEDALS[rank - 1] if rank >= 1 and rank <= 3 else Color("fffdf7"))
		var f := ThemeDB.fallback_font
		var s := "#%d" % rank if rank > 0 else "–"
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
		badge.draw_string(f, c + Vector2(-w / 2.0, 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, UiKit.INK))
	h.add_child(badge)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	v.add_child(UiKit.label("Your result", 30, Color(UiKit.INK, 0.65)))
	var parts := int(mine.get("parts", 0))
	v.add_child(UiKit.label("%d part%s  ·  %s" % [parts, "" if parts == 1 else "s", BoardView.fmt_ms(int(mine.get("ms", 0)))], 50))
	var streak := App.daily_store.streak()
	if streak > 0:
		v.add_child(UiKit.label("Daily streak: %d day%s" % [streak, "" if streak == 1 else "s"], 30, Color(UiKit.INK, 0.75)))
	return p
