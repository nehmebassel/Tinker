class_name FramePacer
extends RefCounted
## FramePacer — battery / heat control for visual-only animation (2026-11-03, Bassel: "phone heats up").
##
## The project runs in low-processor mode: Godot only renders a frame when something changed. Decorative
## animations (map decor, flickering flames, the target marker, the pulsing RUN button) used to call
## queue_redraw() every frame, which forced 60 renders/s at full Retina resolution with nothing happening.
## They now ask FramePacer.anim() first: true at 60 Hz while the player interacts or a machine runs
## ("busy"), at IDLE_HZ otherwise. Physics, simulation and replays are untouched (visual only).
## Battery saver (Settings, on by default) uses IDLE_HZ_SAVER and caps the web canvas at 2x pixel density.

const IDLE_HZ := 30.0
const IDLE_HZ_SAVER := 12.0

static var saver := true
static var _busy_until := 0
static var _frame := -1
static var _last := -100000
static var _now := true


## Run animations at full rate for the next `ms` milliseconds (input, a running machine, a tween).
static func busy(ms: int = 400) -> void:
	_busy_until = maxi(_busy_until, Time.get_ticks_msec() + ms)


static func is_busy() -> bool:
	return Time.get_ticks_msec() < _busy_until


## Should a decorative animation redraw this frame? Same answer for every caller within one frame.
static func anim() -> bool:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		var t := Time.get_ticks_msec()
		var hz := 60.0 if t < _busy_until else (IDLE_HZ_SAVER if saver else IDLE_HZ)
		_now = t - _last >= int(1000.0 / hz) - 2
		if _now:
			_last = t
	return _now
