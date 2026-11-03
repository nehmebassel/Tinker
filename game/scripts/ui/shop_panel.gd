class_name ShopPanel
extends Control
## ShopPanel — coins, the shop and invites, as a modal over any screen (tap the coin chip).
## Sections appear only for what the admin console has switched on:
##   Free coins: daily bonus (+ streak), watch an ad.
##   Coin packs and no-ads passes (bought through the Store: Google Play / Stripe / TEST mode).
##   Invite friends: your code + link, and a field to enter a friend's code.

var _coins_lbl: Label
var _status: Label
var _body: VBoxContainer


static func open(parent: Node) -> ShopPanel:
	var old := parent.get_node_or_null("ShopPanel")
	if old:
		return old
	var s := ShopPanel.new()
	s.name = "ShopPanel"
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.name = "ShopLayer"
	parent.add_child(layer)
	layer.add_child(s)
	return s


func _ready() -> void:
	if has_node("/root/App"):
		App.modal_open += 1
		tree_exiting.connect(func() -> void: App.modal_open = maxi(0, App.modal_open - 1))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.05, 0.14, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 28
	scroll.offset_right = -28
	scroll.offset_top = 70
	scroll.offset_bottom = -40
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var panel := PanelContainer.new()
	var st := UiKit.style(UiKit.PANEL, 36)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 26
	st.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 18)
	panel.add_child(_body)
	App.wallet.changed.connect(_refresh_coins)
	_build()
	App.wallet.sync()


func _build() -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_body.add_child(head)
	var coin := Control.new()
	coin.custom_minimum_size = Vector2(80, 80)
	coin.draw.connect(func() -> void: CoinChip.draw_coin(coin, coin.size / 2.0, 30))
	head.add_child(coin)
	_coins_lbl = UiKit.label("", 52, UiKit.PANEL_TXT)
	_coins_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_coins_lbl)
	var x := UiKit.button("Close", UiKit.MUTED, UiKit.PANEL_TXT, 96)
	x.name = "ShopClose"
	x.add_theme_font_size_override("font_size", 28)
	x.pressed.connect(close)
	head.add_child(x)
	_refresh_coins()
	_status = UiKit.label("", 28, Color("ffd43b"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)
	var eco := App.economy

	# Free coins.
	var free := []
	if eco.on("daily_bonus"):
		var b := _row_button("Daily bonus", "Come back every day: the streak makes it bigger (day %d)." % maxi(1, App.wallet.streak), "Claimed" if App.wallet.bonus_today else "Claim", not App.wallet.bonus_today)
		b.name = "ClaimBonus"
		b.pressed.connect(func() -> void:
			var r: Dictionary = await App.wallet.claim_bonus()
			_say(("+%d coins!" % int(r.get("coins_added", 0))) if r["ok"] else str(r["error"]))
			_build())
		free.append(b.get_meta("row"))
	if eco.on("rewarded_ads") and eco.on("coins"):
		var n := App.wallet.ads_left_today
		var b := _row_button("Watch an ad", "+%d coins · %d left today" % [eco.num("ad_reward_coins"), n], "Watch", n > 0)
		b.name = "WatchAdCoins"
		b.pressed.connect(func() -> void:
			b.disabled = true
			if await App.ads.show_rewarded("coins"):
				var r: Dictionary = await App.wallet.ad_reward("coins", App.ads.last_provider)
				_say(("+%d coins!" % int(r.get("coins_added", 0))) if r["ok"] else str(r["error"]))
			else:
				_say("No reward: the ad was closed early.")
			_build())
		free.append(b.get_meta("row"))
	if not free.is_empty():
		_section("Free coins", free)

	# Shop.
	if App.store.available():
		var test := App.store.method() == "test"
		var coins_rows := []
		var noads_rows := []
		for p in eco.products():
			var once := bool(p.get("once", false)) and App.wallet.bought.has(str(p["id"]))
			var price := "$%.2f" % float(p.get("price_usd", 0))
			var sub := ""
			if int(p.get("coins", 0)) > 0:
				sub = "%d coins" % int(p["coins"])
			if int(p.get("no_ads_days", 0)) > 0:
				sub += (" + " if sub != "" else "") + ("no ads, forever" if int(p["no_ads_days"]) > 3650 else "no ads for %d days" % int(p["no_ads_days"]))
			if str(p.get("badge", "")) != "":
				sub += "  ·  " + str(p["badge"])
			var b := _row_button(str(p.get("title", p["id"])), sub, "Owned" if once else ("TEST " + price if test else price), not once)
			b.name = "Buy_" + str(p["id"])
			b.pressed.connect(_buy.bind(str(p["id"]), b))
			if int(p.get("coins", 0)) > 0:
				coins_rows.append(b.get_meta("row"))
			else:
				noads_rows.append(b.get_meta("row"))
		if not coins_rows.is_empty():
			_section("Coins", coins_rows)
		if not noads_rows.is_empty():
			var title := "No ads" + (" (active)" if App.wallet.no_ads else "")
			_section(title, noads_rows)
		if test:
			var t := UiKit.label("Test mode: nothing is charged; purchases are marked TEST.", 24, Color(UiKit.PANEL_TXT, 0.6))
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_body.add_child(t)
	elif eco.on("purchases"):
		var t := UiKit.label("The shop isn't available on this device yet.", 26, Color(UiKit.PANEL_TXT, 0.6))
		_body.add_child(t)

	# Invites.
	if eco.on("referrals"):
		var rows := []
		var code := App.wallet.ref_code
		var mine := _row_button("Your invite code: " + (code if code != "" else "…"),
			"Your friend gets %d coins; you get %d when they solve their first level." % [eco.num("referral_invitee"), eco.num("referral_inviter")], "Share", code != "")
		mine.name = "ShareInvite"
		mine.pressed.connect(func() -> void:
			var link := App.wallet.invite_link()
			DisplayServer.clipboard_set(link)
			if OS.has_feature("web"):
				JavaScriptBridge.eval("if(navigator.share){navigator.share({title:'Tinker',text:'Build silly machines with me! Use my code %s',url:'%s'}).catch(function(){});}" % [code, link], true)
			_say("Invite link copied: " + link))
		rows.append(mine.get_meta("row"))
		var enter := HBoxContainer.new()
		enter.add_theme_constant_override("separation", 12)
		var field := LineEdit.new()
		field.name = "InviteCode"
		field.placeholder_text = "Friend's code"
		field.max_length = 8
		field.custom_minimum_size = Vector2(0, 90)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_font_size_override("font_size", 34)
		enter.add_child(field)
		var go := UiKit.button("Use code", UiKit.GO, UiKit.INK, 90)
		go.add_theme_font_size_override("font_size", 28)
		go.pressed.connect(func() -> void:
			var r: Dictionary = await App.wallet.claim_referral(field.text.strip_edges().to_upper())
			_say(("+%d coins! Welcome." % int(r.get("coins_added", 0))) if r["ok"] else str(r["error"]))
			if r["ok"]:
				_build())
		enter.add_child(go)
		rows.append(enter)
		_section("Invite friends", rows)


func _buy(id: String, b: Button) -> void:
	b.disabled = true
	_say("Working…")
	var r: Dictionary = await App.store.buy(id)
	if r["ok"]:
		_say("Opening checkout…" if r.get("pending", false) and App.store.method() == "stripe" else ("Done! Thank you." if not r.get("pending", false) else "Finishing with Google Play…"))
		App.audio.sfx("goal")
	else:
		_say(str(r["error"]))
	_build()


func _section(title: String, rows: Array) -> void:
	var l := UiKit.label(title, 36, Color(UiKit.PANEL_TXT, 0.85))
	_body.add_child(l)
	for r in rows:
		_body.add_child(r)


## A card: title + subtitle on the left, an action button on the right. Returns the button
## (the card is in its "row" meta).
func _row_button(title: String, sub: String, action: String, enabled: bool) -> Button:
	var p := PanelContainer.new()
	var st := UiKit.style(Color("fffdf7"), 24)
	st.content_margin_top = 14
	st.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var t := UiKit.label(title, 32)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	if sub != "":
		var s := UiKit.label(sub, 24, Color(UiKit.INK, 0.65))
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	var b := UiKit.button(action, UiKit.GO if enabled else Color("c9c2b6"), UiKit.INK, 88)
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size.x = 200
	b.disabled = not enabled
	h.add_child(b)
	b.set_meta("row", p)
	return b


func _refresh_coins() -> void:
	if _coins_lbl:
		_coins_lbl.text = "%d coins" % App.wallet.coins


func _say(t: String) -> void:
	_status.text = t


func close() -> void:
	get_parent().queue_free()
