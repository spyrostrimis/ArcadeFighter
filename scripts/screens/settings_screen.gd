class_name SettingsScreen
extends Node2D
## Settings menu (title -> SETTINGS). Up/down choose, left/right change a value,
## Enter opens a page or runs an item, Esc goes back. Changes apply at once and are
## saved to user://settings.cfg when leaving the screen.
## P1 KEYS / P2 KEYS: Enter on an action, then press the new key (Esc cancels).
## A key that another action already had is swapped onto that action.

signal finished(action: String)

const ROW_H := 11
const TOP := 30
const VISIBLE := 14
const KEY_LABELS := ["UP", "DOWN", "LEFT", "RIGHT", "LIGHT PUNCH", "MEDIUM PUNCH", "HEAVY PUNCH",
		"LIGHT KICK", "MEDIUM KICK", "HEAVY KICK"]
const LEVELS := ["EASY", "NORMAL", "HARD"]

## Main page rows: [type, key, label, extra]. Types: head, vol, opt, bool, page, act.
var MAIN := [
	["head", "", "AUDIO"],
	["vol", "master", "MASTER VOLUME"],
	["vol", "music", "MUSIC VOLUME"],
	["vol", "sfx", "SOUND VOLUME"],
	["head", "", "CONTROLS"],
	["page", "p1", "PLAYER 1 KEYS"],
	["page", "p2", "PLAYER 2 KEYS"],
	["head", "", "MATCH (VS CPU AND 2 PLAYERS)"],
	["opt", "wins", "ROUNDS", [1, 2, 3]],
	["opt", "time", "ROUND TIME", Settings.TIME_OPTS],
	["opt", "cpu_level", "CPU LEVEL", [0, 1, 2]],
	["head", "", "VIDEO"],
	["bool", "fullscreen", "FULLSCREEN"],
	["opt", "scale", "WINDOW SIZE", [2, 3, 4, 5]],
	["head", "", "DEVELOPMENT"],
	["bool", "show_fps", "SHOW FPS"],
	["bool", "show_boxes", "SHOW HITBOXES (F2)"],
	["bool", "input_display", "SHOW INPUTS (F3)"],
	["bool", "training", "TRAINING HEALTH"],
	["opt", "dummy", "CPU DUMMY", [0, 1, 2, 3, 4, 5]],
	["act", "reset_all", "RESET ALL SETTINGS"],
	["act", "back", "BACK"],
]

const HINTS := {
	"master": "OVERALL VOLUME",
	"music": "MENU AND FIGHT MUSIC",
	"sfx": "HITS, VOICES AND MENU SOUNDS",
	"p1": "CHANGE PLAYER 1 KEYBOARD KEYS",
	"p2": "CHANGE PLAYER 2 KEYBOARD KEYS",
	"wins": "ROUNDS NEEDED TO WIN THE MATCH",
	"time": "SECONDS PER ROUND",
	"show_fps": "FRAMES PER SECOND, BOTTOM RIGHT",
	"show_boxes": "HURT BOXES AND HIT BOXES IN FIGHTS",
	"input_display": "INPUT HISTORY PER PLAYER IN FIGHTS",
	"training": "NO KO: HEALTH REFILLS AFTER EACH COMBO",
	"dummy": "WHAT THE CPU OPPONENT DOES",
	"reset_all": "VOLUMES, KEYS AND OPTIONS BACK TO DEFAULT",
}

var page := ""          # "" = main, "p1"/"p2" = key binding page
var cursor := 1
var scroll := 0
var waiting := ""       # action waiting for a key press
var t := 0
var flash := ""         # short message after an action
var flash_t := 0


func _rows() -> Array:
	if page == "":
		return MAIN
	var r := []
	for i in Settings.BUTTON_ACTIONS.size():
		r.append(["key", page + "_" + Settings.BUTTON_ACTIONS[i], KEY_LABELS[i]])
	r.append(["act", "reset_keys", "RESET TO DEFAULT"])
	r.append(["act", "back", "BACK"])
	return r


func _physics_process(_delta: float) -> void:
	t += 1
	if flash_t > 0:
		flash_t -= 1
	queue_redraw()


func _move(d: int) -> void:
	var rows := _rows()
	var n := rows.size()
	for _i in n:
		cursor = (cursor + d + n) % n
		if rows[cursor][0] != "head":
			break
	_scroll_to_cursor()
	Sfx.play("select")


func _scroll_to_cursor() -> void:
	var rows := _rows()
	var top := cursor - 1 if cursor > 0 and rows[cursor - 1][0] == "head" else cursor
	if top < scroll:
		scroll = top
	elif cursor >= scroll + VISIBLE:
		scroll = cursor - VISIBLE + 1
	scroll = clampi(scroll, 0, maxi(0, rows.size() - VISIBLE))


func _val(k: String) -> Variant:
	return Game.cpu_level if k == "cpu_level" else Settings.v[k]


func _set_val(k: String, val: Variant) -> void:
	if k == "cpu_level":
		Game.cpu_level = val
	else:
		Settings.set_value(k, val)


func _change(row: Array, d: int) -> void:
	var k: String = row[1]
	match row[0]:
		"vol":
			_set_val(k, clampi(int(_val(k)) + d, 0, 10))
		"bool":
			_set_val(k, not bool(_val(k)))
		"opt":
			var opts: Array = row[3]
			var i := opts.find(_val(k))
			_set_val(k, opts[clampi(i + d, 0, opts.size() - 1)] if i >= 0 else opts[0])
		_:
			return
	Sfx.play("select")


func _unhandled_input(event: InputEvent) -> void:
	if waiting != "":
		_capture(event)
		return
	var rows := _rows()
	var row: Array = rows[cursor]
	if event.is_action_pressed("p1_up", true):
		_move(-1)
	elif event.is_action_pressed("p1_down", true):
		_move(1)
	elif event.is_action_pressed("p1_left", true):
		_change(row, -1)
	elif event.is_action_pressed("p1_right", true):
		_change(row, 1)
	elif event.is_action_pressed("menu_ok") and not event.is_echo():
		_ok(row)
	elif event.is_action_pressed("menu_back") and not event.is_echo():
		_back()


func _ok(row: Array) -> void:
	match row[0]:
		"bool":
			_change(row, 1)
		"opt":
			# Enter steps forward and wraps around
			var opts: Array = row[3]
			_set_val(row[1], opts[(opts.find(_val(row[1])) + 1) % opts.size()])
			Sfx.play("select")
		"page":
			page = row[1]
			cursor = 0
			scroll = 0
			Sfx.play("confirm")
		"key":
			waiting = row[1]
			Sfx.play("confirm")
		"act":
			match row[1]:
				"back":
					_back()
				"reset_keys":
					Settings.reset_keys(page)
					_say("KEYS RESET")
				"reset_all":
					Settings.v = Settings.DEFAULTS.duplicate()
					Game.cpu_level = 1
					Settings.reset_keys("p1")
					Settings.reset_keys("p2")
					Settings.apply_all()
					_say("ALL SETTINGS RESET")


func _say(msg: String) -> void:
	flash = msg
	flash_t = 90
	Sfx.play("confirm")


func _back() -> void:
	Sfx.play("back")
	if page != "":
		cursor = 5 if page == "p1" else 6
		page = ""
		_scroll_to_cursor()
		return
	Settings.save()
	finished.emit("title")


func _capture(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	var ke := event as InputEventKey
	var code := int(ke.physical_keycode if ke.physical_keycode != KEY_NONE else ke.keycode)
	if code == KEY_ESCAPE:
		waiting = ""
		Sfx.play("back")
		return
	if code in Settings.RESERVED:
		_say("THAT KEY IS RESERVED")
		Sfx.play("back")
		return
	Settings.bind_key(waiting, code)
	waiting = ""
	Sfx.play("confirm")


func _value_text(row: Array) -> String:
	var k: String = row[1]
	match row[0]:
		"vol":
			return "%d" % int(_val(k))
		"bool":
			return "ON" if _val(k) else "OFF"
		"opt":
			var val: Variant = _val(k)
			match k:
				"wins": return "BEST OF %d" % (int(val) * 2 - 1)
				"time": return "NO LIMIT" if int(val) == 0 else "%d SEC" % int(val)
				"cpu_level": return LEVELS[int(val)]
				"scale": return "X%d  %dX%d" % [val, 384 * int(val), 216 * int(val)]
				"dummy": return Settings.DUMMY_OPTS[int(val)]
			return str(val)
		"key":
			if waiting == k:
				return "PRESS A KEY" if (t / 10) % 2 == 0 else ""
			return Settings.key_name(int(Settings.keys.get(k, 0)))
		"page":
			return ">"
	return ""


func _vol_bar(n: int, x: int, y: int, sel: bool) -> void:
	for k in 10:
		var h := 3 + k / 2
		var c := (Color("ffd000") if sel else Color("60a0ff")) if k < n else Color("2a2a50")
		draw_rect(Rect2(x + k * 8, y + 7 - h, 6, h), c)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 384, 216), Color("1a0e28"))
	for i in range(-10, 30):
		var x := i * 24 + (t / 2) % 24
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 10, 0), Vector2(x - 60, 216), Vector2(x - 70, 216)]),
				Color("241438"))
	var title := "SETTINGS" if page == "" else ("PLAYER %s KEYS" % page.substr(1))
	PixelFont.draw_centered(self, title, 192, 6, 2, Hud.ROUND_GRAD, Hud.DARK, 1, true, 1)
	var rows := _rows()
	draw_rect(Rect2(40, TOP - 4, 304, VISIBLE * ROW_H + 6), Color(0, 0, 0, 0.6))
	for vi in VISIBLE:
		var i := scroll + vi
		if i >= rows.size():
			break
		var row: Array = rows[i]
		var y := TOP + vi * ROW_H
		if row[0] == "head":
			PixelFont.draw(self, row[2], Vector2(48, y), 1, Hud.ROUND_GRAD, Hud.DARK, 0, true)
			draw_rect(Rect2(48, y + 8, 288, 1), Color("4a3a70"))
			continue
		var sel := i == cursor
		var col: Variant = Hud.FIGHT_GRAD if sel else [Color.WHITE, Color("c0c8ff")]
		if sel and (t / 15) % 2 == 0:
			PixelFont.draw(self, ">", Vector2(52, y), 1, Hud.FIGHT_GRAD, Hud.DARK)
		PixelFont.draw(self, row[2], Vector2(62, y), 1, col, Hud.DARK)
		if row[0] == "vol":
			_vol_bar(int(_val(row[1])), 230, y, sel)
		var val := _value_text(row)
		if val != "":
			var vc: Variant = Color("ffe080") if sel else Color("a0d0ff")
			PixelFont.draw(self, val, Vector2(336 - PixelFont.width(val, 1), y), 1, vc, Hud.DARK)
	# scroll arrows
	var ac := Color("ffd000") if (t / 20) % 2 == 0 else Color("a08020")
	if scroll > 0:
		draw_colored_polygon(PackedVector2Array([Vector2(336, TOP - 1), Vector2(342, TOP - 1), Vector2(339, TOP - 4)]), ac)
	if scroll + VISIBLE < rows.size():
		var yb := TOP + VISIBLE * ROW_H
		draw_colored_polygon(PackedVector2Array([Vector2(336, yb - 2), Vector2(342, yb - 2), Vector2(339, yb + 1)]), ac)
	# hint line
	var hint := ""
	if flash_t > 0:
		hint = flash
	elif waiting != "":
		hint = "PRESS THE NEW KEY   ESC CANCEL"
	elif page != "":
		hint = "ENTER CHANGE KEY   ESC BACK   GAMEPADS KEEP THEIR BUTTONS"
	else:
		hint = HINTS.get(String(rows[cursor][1]), "")
	PixelFont.draw_centered(self, hint, 192, 192, 1, Color("80d0ff") if flash_t <= 0 else Color("ffe080"), Hud.DARK)
	PixelFont.draw_centered(self, "UP/DOWN CHOOSE   LEFT/RIGHT CHANGE   ESC BACK", 192, 205, 1, Color("a0a0c0"), Hud.DARK)
