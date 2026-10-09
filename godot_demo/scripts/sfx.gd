extends Node
## Sound effects, synthesised at start-up (no audio files to ship): gunfire, energy weapons,
## ship cannons, explosions, artillery, alarms, the jump drive, UI clicks and a low ambient hum.
##   G.sfx.play("rifle", world_pos)      positional
##   G.sfx.ui("click")                   flat (menus, banners)

const RATE := 22050
const POOL := 28
var streams := {}
var _pool: Array = []
var _next := 0
var _last := {}                    # name -> time last played (keeps a full-auto squad from clipping)
var _flat: AudioStreamPlayer
var _amb: AudioStreamPlayer


func _ready() -> void:
	streams["rifle"] = _shot(0.16, 1800.0, 0.9, 0.0)
	streams["smg"] = _shot(0.11, 2400.0, 0.7, 0.0)
	streams["heavy"] = _shot(0.22, 900.0, 1.0, 0.0)
	streams["pistol"] = _shot(0.14, 1500.0, 0.8, 0.0)
	streams["shotgun"] = _shot(0.3, 700.0, 1.0, 0.0)
	streams["sniper"] = _shot(0.45, 600.0, 1.0, 0.0)
	streams["energy"] = _zap(0.18, 1400.0, 300.0)
	streams["cannon"] = _shot(0.6, 260.0, 1.0, 0.25)
	streams["ciws"] = _shot(0.07, 3000.0, 0.5, 0.0)
	streams["boom"] = _boom(1.1, 0.9)
	streams["big_boom"] = _boom(2.2, 1.0)
	streams["alarm"] = _alarm()
	streams["jump"] = _zap(1.4, 120.0, 900.0)
	streams["click"] = _zap(0.05, 1200.0, 1100.0)
	streams["door"] = _zap(0.35, 180.0, 90.0)
	streams["hum"] = _hum()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 18.0
		p.max_distance = 1400.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	_flat = AudioStreamPlayer.new()
	add_child(_flat)
	_amb = AudioStreamPlayer.new()
	_amb.stream = streams["hum"]
	_amb.volume_db = -22.0
	add_child(_amb)


## Quitting mid-sound would leave the audio server holding the clips (leaked at exit):
## stop every player and let go of the streams first.
func _exit_tree() -> void:
	silence()


## Stop everything and let go of the streams (before quitting: playbacks still mixing at exit leak).
func silence() -> void:
	for p in _pool + [_flat, _amb]:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	streams.clear()


func play(name_: String, at: Vector3, vol_db: float = 0.0, big: bool = false) -> void:
	if not streams.has(name_):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name_, 0)) < 35:
		return
	_last[name_] = now
	var p: AudioStreamPlayer3D = _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = streams[name_]
	p.global_position = at
	p.volume_db = vol_db
	p.unit_size = 60.0 if big else 18.0
	p.max_distance = 6000.0 if big else 1400.0
	p.pitch_scale = randf_range(0.93, 1.07)
	p.play()


func ui(name_: String, vol_db: float = -6.0) -> void:
	if streams.has(name_):
		_flat.stream = streams[name_]
		_flat.volume_db = vol_db
		_flat.play()


func ambience(on: bool) -> void:
	if on and not _amb.playing:
		_amb.play()
	elif not on:
		_amb.stop()


# ------------------------------------------------------------------ synthesis

func _wav(data: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w


## A gunshot: a crack of filtered noise with a falling body tone and a quick decay.
func _shot(len_s: float, tone: float, crack: float, rumble: float) -> AudioStreamWAV:
	var n := int(len_s * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * (6.0 / len_s))
		var nz := randf_range(-1.0, 1.0)
		lp = lerpf(lp, nz, clampf(tone / RATE * 6.0, 0.02, 1.0))
		ph += TAU * (tone * 0.12 * (1.0 - t / len_s * 0.6)) / RATE
		var low := sin(ph) * 0.5 + sin(ph * 0.5) * rumble
		d[i] = (lp * crack + low * 0.6) * env * (1.0 if i > 20 else float(i) / 20.0)
	return _wav(d)


func _zap(len_s: float, f0: float, f1: float) -> AudioStreamWAV:
	var n := int(len_s * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * lerpf(f0, f1, k) / RATE
		d[i] = (sin(ph) * 0.6 + sin(ph * 2.01) * 0.2) * (1.0 - k) * minf(1.0, float(i) / 60.0) * 0.8
	return _wav(d)


func _boom(len_s: float, vol: float) -> AudioStreamWAV:
	var n := int(len_s * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.08)
		lp2 = lerpf(lp2, lp, 0.1)
		d[i] = (lp2 * 3.0 + lp * 0.6) * exp(-t * 3.2 / len_s) * vol * minf(1.0, float(i) / 40.0)
	return _wav(d)


func _alarm() -> AudioStreamWAV:
	var n := int(1.2 * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * (520.0 + 260.0 * sin(k * TAU)) / RATE
		d[i] = sign(sin(ph)) * 0.18 * (1.0 if k < 0.9 else (1.0 - k) * 10.0)
	return _wav(d)


func _hum() -> AudioStreamWAV:
	var n := int(4.0 * RATE)
	var d := PackedFloat32Array()
	d.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.01)
		d[i] = sin(TAU * 55.0 * t) * 0.25 + sin(TAU * 82.5 * t) * 0.12 + lp * 0.8
	return _wav(d, true)
