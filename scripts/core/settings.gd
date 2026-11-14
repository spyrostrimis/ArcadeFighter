extends Node
## Player settings, saved to user://settings.cfg: volumes, keyboard keys per player,
## match rules, window, and development helpers (FPS, hitboxes, input display,
## training health, CPU dummy). Loads after Game (which sets up the default keys).

const PATH := "user://settings.cfg"
const BUTTON_ACTIONS := ["up", "down", "left", "right", "lp", "mp", "hp", "lk", "mk", "hk"]
const TIME_OPTS := [30, 60, 99, 0]     # 0 = no time limit
const DUMMY_OPTS := ["FIGHT", "STAND", "CROUCH", "JUMP", "BLOCK", "LOW BLOCK"]
## Keys that menus/pause/debug need; they can't be given to a fighter action.
const RESERVED := [KEY_ESCAPE, KEY_BACKSPACE, KEY_P, KEY_F2, KEY_F3, KEY_F11]

const DEFAULTS := {
	"master": 8, "music": 6, "sfx": 8,         # 0..10
	"wins": 2, "time": 99,                      # rounds to win (1..3), round seconds (TIME_OPTS)
	"fullscreen": false, "scale": 4,            # window = 384x216 * scale
	"show_fps": false, "show_boxes": false, "input_display": false,
	"training": false, "dummy": 0,             # dummy: index in DUMMY_OPTS (what a CPU opponent does)
}

var v := DEFAULTS.duplicate()
var keys := {}            # "p1_up" -> physical keycode (only keyboard; gamepads keep their defaults)
var default_keys := {}
var path := PATH          # tests point this somewhere else
var _fps_layer: CanvasLayer


func _ready() -> void:
	for p in ["p1", "p2"]:
		for a in BUTTON_ACTIONS:
			var act: String = p + "_" + a
			default_keys[act] = _key_of(act)
	keys = default_keys.duplicate()
	_load()
	if Game.opt.has("set"):   # e.g. -- --set=input_display:1,dummy:4 (this run only)
		for pair in String(Game.opt["set"]).split(",", false):
			var kv := pair.split(":")
			if kv.size() == 2 and DEFAULTS.has(kv[0]):
				v[kv[0]] = (kv[1] == "1") if DEFAULTS[kv[0]] is bool else int(kv[1])
	apply_all()
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 100
	var n := Node2D.new()
	n.set_script(_FpsDraw)
	_fps_layer.add_child(n)
	add_child(_fps_layer)


## Match options for offline matches (online always uses the defaults, both sides must agree).
func match_opts() -> Dictionary:
	return {"wins": int(v["wins"]), "time": int(v["time"]), "training": bool(v["training"])}


func set_value(k: String, value: Variant) -> void:
	v[k] = value
	match k:
		"master", "music", "sfx":
			_apply_audio()
		"fullscreen", "scale":
			_apply_window()


## Back to defaults without saving (tests use this so a player's saved keys don't matter).
func use_defaults(save_path := "") -> void:
	if save_path != "":
		path = save_path
	v = DEFAULTS.duplicate()
	keys = default_keys.duplicate()
	apply_all()


func toggle_fullscreen() -> void:
	set_value("fullscreen", not v["fullscreen"])
	save()


# --- keys ---------------------------------------------------------------------

func _key_of(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			return int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return 0


## Binds a key to an action. If another fighter action had that key, the two swap keys.
func bind_key(action: String, keycode: int) -> void:
	var old: int = keys.get(action, 0)
	for other in keys:
		if other != action and keys[other] == keycode:
			keys[other] = old
			_apply_key(other)
	keys[action] = keycode
	_apply_key(action)


func reset_keys(prefix: String) -> void:
	var taken := {}
	for act in default_keys:
		if String(act).begins_with(prefix):
			keys[act] = default_keys[act]
			taken[keys[act]] = true
	# the other player may hold one of these keys after a swap: give them their own default back
	for act in keys:
		if not String(act).begins_with(prefix) and taken.has(keys[act]):
			var d: int = default_keys[act]
			keys[act] = 0 if keys.values().has(d) else d
	for act in keys:
		_apply_key(act)


func _apply_key(action: String) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	var k: int = keys.get(action, 0)
	if k != 0:
		var e := InputEventKey.new()
		e.physical_keycode = k as Key
		InputMap.action_add_event(action, e)


static func key_name(keycode: int) -> String:
	if keycode == 0:
		return "---"
	var s := OS.get_keycode_string(keycode as Key).to_upper()
	s = s.replace("KP ", "NUM ").replace("KP", "NUM")
	var out := ""
	for ch in s:
		out += ch if PixelFont.GLYPHS.has(ch) else "?"
	return out


# --- apply / save -------------------------------------------------------------

func apply_all() -> void:
	_apply_audio()
	_apply_window()
	for act in keys:
		_apply_key(act)


func _bus_vol(bus: String, level: int) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, level <= 0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level, 1) / 10.0))


func _apply_audio() -> void:
	_bus_vol("Master", int(v["master"]))
	_bus_vol("Music", int(v["music"]))
	_bus_vol("SFX", int(v["sfx"]))


func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	if v["fullscreen"]:
		w.mode = Window.MODE_FULLSCREEN
		return
	if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED
	var size := Vector2i(384, 216) * int(v["scale"])
	var scr := DisplayServer.screen_get_usable_rect(w.current_screen)
	size = size.min(scr.size)
	if w.size != size:
		w.size = size
		w.position = scr.position + (scr.size - size) / 2


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	for k in DEFAULTS:
		v[k] = cf.get_value("settings", k, DEFAULTS[k])
	Game.cpu_level = clampi(int(cf.get_value("settings", "cpu_level", Game.cpu_level)), 0, 2)
	for act in default_keys:
		keys[act] = int(cf.get_value("keys", act, default_keys[act]))


func save() -> void:
	var cf := ConfigFile.new()
	for k in v:
		cf.set_value("settings", k, v[k])
	cf.set_value("settings", "cpu_level", Game.cpu_level)
	for act in keys:
		cf.set_value("keys", act, keys[act])
	cf.save(path)


## Bottom-right FPS counter, drawn above every screen when "SHOW FPS" is on.
const _FpsDraw := preload("res://scripts/core/fps_draw.gd")
