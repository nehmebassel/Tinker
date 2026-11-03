class_name Audio
extends Node
## Audio — music and sound effects for every screen. A child of App (App.audio).
##
##   Buses: "Music" and "SFX" are declared in res://default_bus_layout.tres. They MUST exist at startup:
##          the web build plays sounds as Web Audio samples routed through a bus graph built at boot,
##          and buses added at run time are never connected to the output (the web build was silent).
##          _make_bus() below only covers a missing layout file. Volumes from Settings (music_volume / sfx_volume, 0..1),
##          changed on the Settings screen — nothing hard-coded.
##   Music: three loops (menu / build / run), crossfaded. play_music("build").
##   SFX:   sfx("place"), one-shots from a small player pool, plus named loops (fan, motor) that the
##          SoundWatcher switches on and off while a machine runs.
##   Every button in the game taps (node_added hook), unless it carries meta "no_tap".
##
## Audio never touches the simulation: it is fed by observers, so replays stay bit-identical.
## Assets: res://assets/audio — music by Lyria (Vertex AI), effects by ElevenLabs (see docs/DESIGN.md).

const DIR := "res://assets/audio/"
const MUSIC := {"menu": "music_menu.ogg", "map": "music_map.ogg", "build": "music_build.ogg", "run": "music_run.ogg"}
const SFX := ["ui_tap", "pick", "place", "rotate", "play", "rewind", "impact_wood", "impact_metal",
	"spring", "pop", "switch", "candle", "mouse", "cat", "goal", "fail", "basket", "pulley", "deny"]
const LOOPS := {"fan": "fan_loop", "motor": "motor_loop"}
const POOL := 10
const FADE_S := 0.8
const MUSIC_DB := -6.0  # music sits under the effects at equal slider positions

var _streams: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_now := ""
var _music_cur := 0
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _loops: Dictionary = {}  # name -> AudioStreamPlayer
var _tween: Tween
var history: PackedStringArray = []  # every effect played, newest last (tests read it; capped)


func _ready() -> void:
	name = "Audio"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("Music")
	_make_bus("SFX")
	for k in MUSIC:
		var s: AudioStream = load(DIR + MUSIC[k])
		if s is AudioStreamOggVorbis:
			s.loop = true
		_streams["m_" + k] = s
	for k in SFX:
		_streams[k] = load(DIR + k + ".ogg")
	for k in LOOPS:
		var s: AudioStream = load(DIR + LOOPS[k] + ".ogg")
		if s is AudioStreamOggVorbis:
			s.loop = true
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		p.volume_db = -8.0
		add_child(p)
		_loops[k] = p
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)


func _make_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus)
	AudioServer.set_bus_send(i, "Master")


## Slider value 0..1 -> bus volume. 0 mutes the bus.
func apply_volumes() -> void:
	var s: Settings = get_parent().settings  # App (parent); no global identifier in headless scripts
	_set_bus("Music", s.music_volume)
	_set_bus("SFX", s.sfx_volume)


func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(v, 0.001, 1.0)))


# ------------------------------------------------------------------ music

func play_music(track: String) -> void:
	if track == _music_now or not _streams.has("m_" + track):
		return
	_music_now = track
	var old := _music[_music_cur]
	_music_cur = 1 - _music_cur
	var new := _music[_music_cur]
	new.stream = _streams["m_" + track]
	new.volume_db = -40.0
	new.play()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(new, "volume_db", MUSIC_DB, FADE_S)
	_tween.tween_property(old, "volume_db", -60.0, FADE_S)
	_tween.chain().tween_callback(old.stop)


func current_music() -> String:
	return _music_now


# ------------------------------------------------------------------ effects

## One-shot. `gain_db` for quieter/louder variants, `pitch` for variety (impacts vary per part).
func sfx(sound: String, gain_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStream = _streams.get(sound)
	if s == null:
		return
	history.append(sound)
	if history.size() > 200:
		history.remove_at(0)
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = gain_db
	p.pitch_scale = pitch
	p.play()


## Short vibration for touch feedback (phones and phone browsers; iOS Safari has no vibration API).
## Off when the player turned Vibration off in Settings.
func buzz(ms: int) -> void:
	if not get_parent().settings.haptics:
		return
	if OS.has_feature("mobile") or OS.has_feature("web"):
		Input.vibrate_handheld(ms)


func set_loop(loop: String, on: bool) -> void:
	var p: AudioStreamPlayer = _loops.get(loop)
	if p == null:
		return
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


func stop_loops() -> void:
	for k in _loops:
		_loops[k].stop()


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(func() -> void:
			if not n.get_meta("no_tap", false):
				sfx("ui_tap", -4.0))

