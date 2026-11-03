class_name AdOverlay
extends CanvasLayer
## AdOverlay — the built-in "house" ad: what players see until an ad network (H5 Games Ads / AdMob)
## is connected in the admin console, and whenever the network has no ad to show. It is labelled
## "Ad", shows a Tinker promo with a countdown and earns nothing (booked as TEST in the ledger).
## Rewarded: closing before the countdown ends gives no reward. Interstitial: closable after 3 s.

const PROMOS := [
	["Build your own machine", "Open Sandbox, make a level with any parts, and send the link to a friend."],
	["The Daily puzzle", "Same parts for everyone, every day. Fewest parts wins. How do you rank?"],
	["Invite a friend", "When a friend joins with your code and solves a level, you both get coins."],
	["Stuck?", "A hint shows where one part goes. Coins come from levels, the Daily and the daily bonus."],
]

var rewarded := true
var _secs := 5.0
var _left := 5.0
var _done := false
var _result := false
var _close: Button
var _count: Label
var _bar: ColorRect
var _bar_bg: ColorRect


static func play(root: Node, p_rewarded: bool, _what: String) -> bool:
	var o := AdOverlay.new()
	o.rewarded = p_rewarded
	o._secs = 5.0 if p_rewarded else 3.0
	o._left = o._secs
	root.add_child(o)
	while not o._done:
		await o.get_tree().process_frame
	var r := o._result
	o.queue_free()
	return r


func _ready() -> void:
	layer = 100
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.12, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := PanelContainer.new()
	var st := UiKit.style(UiKit.BG, 36)
	st.content_margin_left = 40
	st.content_margin_right = 40
	st.content_margin_top = 32
	st.content_margin_bottom = 32
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.x = 860
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	p.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var tag := UiKit.label(" Ad ", 26, UiKit.PANEL_TXT)
	var ts := StyleBoxFlat.new()
	ts.bg_color = UiKit.MUTED
	ts.set_corner_radius_all(10)
	tag.add_theme_stylebox_override("normal", ts)
	top.add_child(tag)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_count = UiKit.label("", 28, Color(UiKit.INK, 0.7))
	top.add_child(_count)
	var promo: Array = PROMOS[randi() % PROMOS.size()]
	var art := Control.new()
	art.custom_minimum_size = Vector2(0, 260)
	art.draw.connect(func() -> void: _draw_art(art))
	v.add_child(art)
	var h := UiKit.label(promo[0], 52)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)
	var b := UiKit.label(promo[1], 32, Color(UiKit.INK, 0.8))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(UiKit.INK, 0.15)
	_bar_bg.custom_minimum_size = Vector2(0, 14)
	v.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = UiKit.GO
	_bar.size = Vector2(0, 14)
	_bar_bg.add_child(_bar)
	_close = UiKit.button("", UiKit.MUTED, UiKit.PANEL_TXT, 100)
	_close.name = "AdClose"
	_close.pressed.connect(func() -> void:
		_result = rewarded and _left <= 0.0
		_done = true)
	v.add_child(_close)
	_update()
	if has_node("/root/App"):
		App.audio.sfx("place")


func _process(delta: float) -> void:
	FramePacer.busy(200)
	if _left > 0.0:
		_left = maxf(0.0, _left - delta)
		_update()


func _update() -> void:
	_bar.size.x = _bar_bg.size.x * (1.0 - _left / _secs)
	if rewarded:
		_count.text = "Reward in %d s" % ceili(_left) if _left > 0.0 else "Reward unlocked"
		_close.text = "Close (no reward)" if _left > 0.0 else "Collect reward"
		var on := _left <= 0.0
		for k in ["normal", "hover", "pressed"]:
			_close.add_theme_stylebox_override(k, UiKit.style(UiKit.GO if on else UiKit.MUTED))
		_close.add_theme_color_override("font_color", UiKit.INK if on else UiKit.PANEL_TXT)
	else:
		_count.text = "%d s" % ceili(_left) if _left > 0.0 else ""
		_close.text = "Continue" if _left <= 0.0 else "Continue in %d" % ceili(_left)
		_close.disabled = _left > 0.0


## A small machine: a ball rolls down a ramp into a basket, endlessly.
func _draw_art(n: Control) -> void:
	var w := n.size.x
	var t := float(Time.get_ticks_msec() % 2400) / 2400.0
	var a := Vector2(w * 0.18, 60)
	var b := Vector2(w * 0.62, 190)
	n.draw_line(a, b, UiKit.INK, 14)
	n.draw_line(a, b, Color("e0b44c"), 8)
	var p := a.lerp(b, minf(t * 1.3, 1.0)) + Vector2(0, -22)
	if t * 1.3 > 1.0:
		p = b + Vector2((t * 1.3 - 1.0) * w * 0.4, (t * 1.3 - 1.0) * 120.0) + Vector2(0, -22)
	n.draw_circle(p, 22, UiKit.INK)
	n.draw_circle(p, 17, UiKit.ACCENT)
	var bx := Rect2(Vector2(w * 0.72, 170), Vector2(120, 80))
	n.draw_rect(bx, UiKit.INK)
	n.draw_rect(bx.grow(-6), Color("c98a4b"))
	n.queue_redraw()
