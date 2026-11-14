extends Node
## Procedurally generated retro sound effects (no audio files needed yet).

const RATE := 22050

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _seed := 1


func _ready() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_build()


func play(sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not _sounds.has(sname):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[sname]
	p.volume_db = -6.0 + vol_db
	p.pitch_scale = pitch
	p.play()


func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / float(0x7fffffff) * 2.0 - 1.0


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Noise burst through a one-pole low-pass whose cutoff sweeps from c0 to c1.
func _noise(len_s: float, c0: float, c1: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(len_s * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var c := lerpf(c0, c1, t)
		lp += (_rand() - lp) * c
		out[i] = lp * vol * pow(1.0 - t, decay)
	return out


## Sine/square tone sweeping f0 -> f1.
func _tone(len_s: float, f0: float, f1: float, vol: float, square := false, decay := 1.0) -> PackedFloat32Array:
	var n := int(len_s * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / n
		ph += lerpf(f0, f1, t) / RATE
		var v := sin(ph * TAU)
		if square:
			v = 1.0 if v >= 0.0 else -1.0
		out[i] = v * vol * pow(1.0 - t, decay)
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size() + offset)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := 0.0
		if i < a.size():
			v += a[i]
		if i - offset >= 0 and i - offset < b.size():
			v += b[i - offset]
		out[i] = v
	return out


func _crush(a: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	for i in a.size():
		a[i] = tanh(a[i] * drive)
	return a


func _notes(freqs: Array, note_len: float, vol: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in freqs:
		out.append_array(_tone(note_len, f, f, vol, true, 0.6))
	return out


func _build() -> void:
	_sounds["swing0"] = _make(_noise(0.09, 0.5, 0.15, 0.35, 1.5))
	_sounds["swing1"] = _make(_noise(0.13, 0.35, 0.08, 0.45, 1.3))
	_sounds["swing2"] = _make(_noise(0.19, 0.25, 0.05, 0.55, 1.1))
	_sounds["hit0"] = _make(_crush(_mix(_noise(0.08, 0.9, 0.3, 0.8, 2.0), _tone(0.08, 300, 120, 0.6)), 1.5))
	_sounds["hit1"] = _make(_crush(_mix(_noise(0.13, 0.8, 0.15, 0.9, 1.8), _tone(0.13, 220, 70, 0.8)), 2.0))
	_sounds["hit2"] = _make(_crush(_mix(_noise(0.22, 0.8, 0.06, 1.0, 1.4), _tone(0.22, 180, 45, 1.0)), 2.6))
	_sounds["block"] = _make(_mix(_tone(0.06, 1400, 900, 0.35, true, 2.0), _noise(0.05, 0.9, 0.5, 0.3, 2.0)))
	_sounds["land"] = _make(_mix(_noise(0.06, 0.2, 0.05, 0.5, 2.0), _tone(0.06, 120, 60, 0.4)))
	_sounds["thud"] = _make(_crush(_mix(_noise(0.2, 0.3, 0.03, 0.9, 1.5), _tone(0.2, 90, 40, 0.9)), 2.0))
	_sounds["ko"] = _make(_crush(_mix(_noise(0.6, 0.9, 0.02, 1.0, 1.2), _tone(0.6, 160, 30, 1.0)), 3.0))
	_sounds["select"] = _make(_tone(0.05, 880, 880, 0.25, true, 1.0))
	_sounds["confirm"] = _make(_notes([660.0, 990.0], 0.07, 0.25))
	_sounds["back"] = _make(_notes([520.0, 350.0], 0.06, 0.22))
	_sounds["round"] = _make(_notes([392.0, 523.0, 659.0], 0.09, 0.25))
	_sounds["fight"] = _make(_notes([523.0, 659.0, 784.0, 1047.0, 1047.0], 0.07, 0.3))
	_sounds["win"] = _make(_notes([523.0, 659.0, 784.0, 659.0, 784.0, 1047.0], 0.11, 0.25))
	_sounds["lose"] = _make(_notes([392.0, 349.0, 311.0, 262.0], 0.16, 0.25))
