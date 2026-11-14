extends Node
## Procedural chiptune music (placeholder until real tracks exist).
## Two original looping songs, rendered once in a background thread at startup:
##   "title" - calm A minor theme for menus
##   "fight" - driving E minor theme for matches
## Music.play("fight") / Music.play("") to stop. Plays on the "Music" audio bus.

const RATE := 22050

## Song = tempo, chords (one per bar: root midi note + "m"/"" quality), lead melody
## (16 steps per bar: note like "e5"/"f#5", "." holds the previous note, "-" is a rest),
## and a drum style.
const SONGS := {
	"title": {
		"bpm": 100, "drums": "soft", "bass": "long", "arp": true,
		"chords": [[57, "m"], [53, ""], [48, ""], [55, ""], [57, "m"], [53, ""], [55, ""], [52, ""]],
		"lead": [
			"a4 . . . . . . . c5 . . . e5 . . .",
			"f5 . . . e5 . . . c5 . . . a4 . . .",
			"g4 . . . c5 . . . e5 . . . g5 . . .",
			"d5 . . . . . . . b4 . . . . . . .",
			"a5 . . . g5 . . . e5 . . . c5 . . .",
			"a4 . . . c5 . . . f5 . . . e5 . . .",
			"d5 . . . b4 . . . d5 . . . g5 . . .",
			"g#5 . . . . . . . e5 . . . - . . .",
		],
	},
	"fight": {
		"bpm": 150, "drums": "drive", "bass": "pump", "arp": false,
		"chords": [[40, "m"], [40, "m"], [36, ""], [38, ""], [40, "m"], [40, "m"], [36, ""], [35, ""]],
		"lead": [
			"e5 . . . b4 . e5 . f#5 . g5 . f#5 . e5 .",
			"d5 . e5 . b4 . . . g4 . a4 . b4 . . .",
			"c5 . . . g4 . c5 . d5 . e5 . d5 . c5 .",
			"d5 . . . a4 . d5 . e5 . f#5 . a5 . . .",
			"b5 . . . a5 . g5 . f#5 . g5 . e5 . . .",
			"g5 . f#5 . e5 . d5 . e5 . . . b4 . . .",
			"c5 . e5 . g5 . c6 . b5 . g5 . e5 . g5 .",
			"f#5 . . . d#5 . f#5 . b5 . . . - . - .",
		],
	},
}

var _streams := {}
var _player: AudioStreamPlayer
var _want := ""
var _thread: Thread
var _seed := 7


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.volume_db = -8.0
	add_child(_player)
	_thread = Thread.new()
	_thread.start(_render_all)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func play(song: String) -> void:
	if song == _want:
		return
	_want = song
	_start()


func _start() -> void:
	if _want == "" or not _streams.has(_want):
		_player.stop()
		return
	_player.stream = _streams[_want]
	_player.play()


func _render_all() -> void:
	var out := {}
	for name in SONGS:
		out[name] = _render(SONGS[name])
	call_deferred("_done", out)


func _done(out: Dictionary) -> void:
	_streams = out
	_thread.wait_to_finish()
	_thread = null
	_start()


static func _midi(tok: String) -> int:
	const N := {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
	var n: int = N[tok[0]]
	var i := 1
	if tok[i] == "#":
		n += 1
		i += 1
	return 12 * (int(tok.substr(i)) + 1) + n


static func _hz(m: int) -> float:
	return 440.0 * pow(2.0, (m - 69) / 12.0)


## One note into the buffer. wave: 0 pulse 25%, 1 square, 2 triangle.
func _note(buf: PackedFloat32Array, start: int, length: int, m: int, wave: int, vol: float) -> void:
	var f := _hz(m) / RATE
	var ph := 0.0
	var rel := mini(length, int(0.03 * RATE))
	var end := mini(buf.size(), start + length)
	for i in range(start, end):
		var k := i - start
		var env := minf(1.0, k / 60.0) * (0.55 + 0.45 * exp(-k / 2500.0))
		if k > length - rel:
			env *= float(length - k) / rel
		ph = fmod(ph + f, 1.0)
		var s: float
		match wave:
			0: s = 1.0 if ph < 0.25 else -1.0
			1: s = 1.0 if ph < 0.5 else -1.0
			_: s = 4.0 * absf(ph - 0.5) - 1.0
		buf[i] += s * env * vol


func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / float(0x7fffffff) * 2.0 - 1.0


## kind: 0 kick, 1 snare, 2 hat
func _drum(buf: PackedFloat32Array, start: int, kind: int, vol: float) -> void:
	var length: int = [int(0.14 * RATE), int(0.12 * RATE), int(0.035 * RATE)][kind]
	var ph := 0.0
	var hp_prev := 0.0
	var end := mini(buf.size(), start + length)
	for i in range(start, end):
		var t := float(i - start) / length
		var s := 0.0
		match kind:
			0:
				ph += lerpf(140.0, 45.0, sqrt(t)) / RATE
				s = sin(ph * TAU) * pow(1.0 - t, 1.5)
			1:
				s = (_rand() * 0.8 + sin(i * 190.0 * TAU / RATE) * 0.3) * pow(1.0 - t, 2.0)
			2:
				var n := _rand()
				s = (n - hp_prev) * 0.5 * pow(1.0 - t, 2.0)
				hp_prev = n
		buf[i] += s * vol


func _render(song: Dictionary) -> AudioStreamWAV:
	var step := int(RATE * 60.0 / float(song["bpm"]) / 4.0)   # one 16th note
	var bars: int = song["chords"].size()
	var buf := PackedFloat32Array()
	buf.resize(step * 16 * bars)
	# lead
	var notes: Array = []   # [start step, midi]
	for b in bars:
		var toks: PackedStringArray = String(song["lead"][b]).split(" ", false)
		for s in toks.size():
			var tok: String = toks[s]
			if tok == ".":
				continue
			notes.append([b * 16 + s, -1 if tok == "-" else _midi(tok)])
	for i in notes.size():
		var s0: int = notes[i][0]
		var s1: int = notes[i + 1][0] if i + 1 < notes.size() else bars * 16
		if notes[i][1] >= 0:
			_note(buf, s0 * step, (s1 - s0) * step, notes[i][1], 0, 0.20)
	# bass + arpeggio from the chords
	for b in bars:
		var root: int = song["chords"][b][0]
		var third: int = 3 if song["chords"][b][1] == "m" else 4
		var t0 := b * 16 * step
		if song["bass"] == "pump":
			var pat := [0, 0, 12, 0, 0, 12, 0, 12]
			for k in 8:
				_note(buf, t0 + k * 2 * step, step * 2 - step / 3, root + pat[k], 1, 0.16)
		else:
			_note(buf, t0, step * 8, root - 12, 2, 0.30)
			_note(buf, t0 + step * 8, step * 8, root - 12 + 7, 2, 0.30)
		if song["arp"]:
			var arp := [0, third, 7, 12, 7, third, 0, third]
			for k in 8:
				_note(buf, t0 + k * 2 * step, step * 2, root + 12 + arp[k], 2, 0.14)
		else:
			# off-beat chord stabs
			for k in [2, 6, 10, 14]:
				for iv in [0, third, 7]:
					_note(buf, t0 + k * step, step, root + 24 + iv, 1, 0.035)
	# drums
	for b in bars:
		var t0 := b * 16 * step
		for s in 16:
			var at := t0 + s * step
			if song["drums"] == "drive":
				if s == 0 or s == 8 or (s == 10 and b % 2 == 1):
					_drum(buf, at, 0, 0.55)
				if s == 4 or s == 12:
					_drum(buf, at, 1, 0.35)
				if s % 2 == 0:
					_drum(buf, at, 2, 0.25)
			else:
				if s == 0:
					_drum(buf, at, 0, 0.35)
				if s == 8:
					_drum(buf, at, 1, 0.12)
				if s % 4 == 2:
					_drum(buf, at, 2, 0.15)
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(tanh(buf[i] * 1.2), -1.0, 1.0) * 30000.0))
	var ws := AudioStreamWAV.new()
	ws.format = AudioStreamWAV.FORMAT_16_BITS
	ws.mix_rate = RATE
	ws.stereo = false
	ws.data = data
	ws.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ws.loop_begin = 0
	ws.loop_end = buf.size()
	return ws
