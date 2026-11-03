class_name Ads
extends Node
## Ads — rewarded and interstitial ads behind one call, provider chosen in the admin console:
##   house : a built-in placeholder ad (AdOverlay). Works everywhere, earns nothing; used until an ad
##           network is connected, and as the fallback when a network has no ad to show.
##   h5    : Google H5 Games Ads in the browser build (adBreak API, AdSense "ca-pub-" id from config).
##   admob : Google AdMob in the Android app. Needs the AdMob plugin + ad units (not bundled yet:
##           falls back to house until it is).
## show_rewarded() returns true only if the player watched to the end (then the server grants).

var levels_since_interstitial := 0
var _h5_loaded := false


func provider() -> String:
	var p := str(App.economy.ads().get("provider", "house"))
	if p == "h5" and not OS.has_feature("web"):
		return "house"
	if p == "admob" and not Engine.has_singleton("PoingGodotAdMob"):
		return "house"
	return p


func show_rewarded(what: String) -> bool:
	match provider():
		"h5":
			var r := await _h5_break("reward", what)
			if r != "unavailable":
				return r == "viewed"
	return await AdOverlay.play(get_tree().root, true, what)


## Between levels, every N levels, unless ads are off or the player has a no-ads pass.
func maybe_interstitial() -> void:
	levels_since_interstitial += 1
	if not App.economy.on("interstitial_ads") or App.wallet.no_ads:
		return
	if levels_since_interstitial < maxi(1, int(App.economy.ads().get("interstitial_every_levels", 4))):
		return
	levels_since_interstitial = 0
	var p := provider()
	var shown := false
	if p == "h5":
		shown = (await _h5_break("next", "")) == "viewed"
	if not shown:
		await AdOverlay.play(get_tree().root, false, "")
	App.wallet.post("/ads/impression", {"provider": p if shown else "house"})


## H5 Games Ads: inject the adsbygoogle script once, then adBreak(); the JS side writes the outcome
## into window.__tinkerAd, which we poll (JavaScriptBridge callbacks are not needed for this).
func _h5_break(type: String, name: String) -> String:
	var client := str(App.economy.ads().get("h5_client_id", ""))
	if client == "":
		return "unavailable"
	if not _h5_loaded:
		_h5_loaded = true
		var test := "on" if bool(App.economy.ads().get("h5_test_mode", true)) else "off"
		JavaScriptBridge.eval("""(function(){var s=document.createElement('script');s.async=true;
			s.src='https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=%s';
			s.setAttribute('data-ad-client','%s');s.setAttribute('data-adbreak-test','%s');s.crossOrigin='anonymous';
			document.head.appendChild(s);window.adsbygoogle=window.adsbygoogle||[];
			window.adBreak=window.adConfig=function(o){window.adsbygoogle.push(o);};
			adConfig({preloadAdBreaks:'on',sound:'on'});})()""" % [client, client, test], true)
		await get_tree().create_timer(1.5).timeout
	JavaScriptBridge.eval("window.__tinkerAd='pending';", true)
	if type == "reward":
		JavaScriptBridge.eval("""adBreak({type:'reward',name:'%s',
			beforeReward:function(show){window.__tinkerAd='ready';show();},
			adViewed:function(){window.__tinkerAd='viewed';},adDismissed:function(){window.__tinkerAd='dismissed';},
			adBreakDone:function(i){if(window.__tinkerAd==='pending'||window.__tinkerAd==='ready'){window.__tinkerAd=(i&&i.breakStatus==='viewed')?'viewed':'unavailable';}}});""" % name.c_escape(), true)
	else:
		JavaScriptBridge.eval("""adBreak({type:'next',name:'between-levels',
			adBreakDone:function(i){window.__tinkerAd=(i&&i.breakStatus==='viewed')?'viewed':'unavailable';}});""", true)
	var t := 0.0
	while t < 90.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		var s := str(JavaScriptBridge.eval("window.__tinkerAd||''", true))
		if s in ["viewed", "dismissed", "unavailable"]:
			return s
	return "unavailable"
