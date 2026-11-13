class_name OnlineScreen
extends Node2D
## Online menu: HOST ROOM shows a room code, JOIN ROOM types one in.
## Shows live status while connecting, ESC cancels, failures say why.

signal finished(action: String)

enum { MENU, ENTRY, CONNECTING, ERROR }

const ITEMS := ["HOST ROOM", "JOIN ROOM", "INPUT DELAY", "BACK"]
const GREY := Color("a0a0c0")

var mode := MENU
var cursor := 0
var t := 0
var mode_t := 0
var typed := ""
var hint := ""
var hint_t := 0
var error_msg := ""
var copied := false
var _auto_join := ""
var bg: Texture2D


func _ready() -> void:
	bg = load("res://assets/stages/bedroom.png")
	if error_msg != "":
		_set_mode(ERROR)
		return
	# Test hooks: -- --host [--room=CODE] [--codefile=PATH]   /   -- --join=CODE|@PATH
	var o: Dictionary = Game.opt
	if o.has("host") and not Game.auto_started:
		Game.auto_started = true
		_host()
	elif o.has("join") and not Game.auto_started:
		Game.auto_started = true
		_auto_join = String(o["join"])
		_set_mode(CONNECTING)


func _set_mode(m: int) -> void:
	mode = m
	mode_t = 0


func _host() -> void:
	Net.host(String(Game.opt.get("room", "")))
	copied = false
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(Net.room.code)
		copied = true
	if Game.opt.has("codefile"):
		var f := FileAccess.open(String(Game.opt["codefile"]), FileAccess.WRITE)
		if f != null:
			f.store_string(Net.room.code)
	_set_mode(CONNECTING)


func _join(code: String) -> void:
	var r := NetRoom.normalize(code)
	if not r[0]:
		_hint(r[1])
		return
	Net.join(r[1])
	_set_mode(CONNECTING)


func _hint(s: String) -> void:
	hint = s
	hint_t = 150
	Sfx.play("back")


func _physics_process(_delta: float) -> void:
	t += 1
	mode_t += 1
	if hint_t > 0:
		hint_t -= 1
	if _auto_join != "" and Net.room == null:
		var code := _auto_join
		if code.begins_with("@"):
			code = FileAccess.get_file_as_string(code.substr(1)).strip_edges() if FileAccess.file_exists(code.substr(1)) else ""
		if code != "":
			_auto_join = ""
			_join(code)
	if mode == CONNECTING and Net.room != null:
		if Net.room.state == NetRoom.CONNECTED:
			Sfx.play("confirm")
			finished.emit("online_select")
			return
		if Net.room.state == NetRoom.FAILED:
			error_msg = Net.room.error
			Net.leave()
			_set_mode(ERROR)
			if Game.opt.has("autoplay"):
				Game.auto_report({"error": error_msg})
				get_tree().quit(1)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() and mode != ENTRY:
		return
	match mode:
		MENU:
			_menu_input(event)
		ENTRY:
			_entry_input(event)
		CONNECTING:
			if event.is_action_pressed("menu_back"):
				Sfx.play("back")
				Net.leave()
				_auto_join = ""
				_set_mode(MENU)
		ERROR:
			if mode_t > 20 and event.is_pressed() and (event is InputEventKey or event is InputEventJoypadButton):
				Sfx.play("select")
				error_msg = ""
				_set_mode(MENU)
				get_viewport().set_input_as_handled()


func _menu_input(event: InputEvent) -> void:
	if event.is_action_pressed("p1_up"):
		cursor = (cursor + ITEMS.size() - 1) % ITEMS.size()
		Sfx.play("select")
	elif event.is_action_pressed("p1_down"):
		cursor = (cursor + 1) % ITEMS.size()
		Sfx.play("select")
	elif ITEMS[cursor] == "INPUT DELAY" and (event.is_action_pressed("p1_left") or event.is_action_pressed("p1_right")):
		Net.delay = clampi(Net.delay + (-1 if event.is_action_pressed("p1_left") else 1), 0, 6)
		Sfx.play("select")
	elif event.is_action_pressed("menu_ok"):
		match ITEMS[cursor]:
			"HOST ROOM":
				Sfx.play("confirm")
				_host()
			"JOIN ROOM":
				Sfx.play("confirm")
				typed = ""
				_set_mode(ENTRY)
				get_viewport().set_input_as_handled()
			"INPUT DELAY":
				Net.delay = (Net.delay + 1) % 7
				Sfx.play("select")
			"BACK":
				Sfx.play("back")
				finished.emit("title")
	elif event.is_action_pressed("menu_back"):
		Sfx.play("back")
		finished.emit("title")


func _entry_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		if event.is_action_pressed("menu_back"):
			_set_mode(MENU)
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	match k.keycode:
		KEY_ESCAPE:
			Sfx.play("back")
			_set_mode(MENU)
		KEY_BACKSPACE:
			if typed.length() > 0:
				typed = typed.substr(0, typed.length() - 1)
				Sfx.play("select")
		KEY_ENTER, KEY_KP_ENTER:
			_join(typed)
		KEY_V when k.ctrl_pressed:
			var r := NetRoom.normalize(DisplayServer.clipboard_get())
			if r[0]:
				typed = r[1]
				Sfx.play("select")
			else:
				_hint("CLIPBOARD HAS NO ROOM CODE")
		_:
			if k.unicode == 0 or k.ctrl_pressed:
				return
			var ch := String.chr(k.unicode).to_upper()
			if ch == " " or ch == "-":
				return
			if not NetRoom.CODE_CHARS.contains(ch):
				_hint("CODES NEVER USE I, O, 0 OR 1" if ch in ["I", "O", "0", "1"] else "LETTERS AND NUMBERS ONLY")
			elif typed.length() < NetRoom.CODE_LEN:
				typed += ch
				Sfx.play("select")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_texture(bg, Vector2(-64, 0))
	draw_rect(Rect2(0, 0, 384, 216), Color(0.05, 0.0, 0.08, 0.7))
	PixelFont.draw_centered(self, "ONLINE", 192, 12, 3, Hud.ROUND_GRAD, Hud.DARK, 1, true, 2)
	match mode:
		MENU:
			_draw_menu()
		ENTRY:
			_draw_entry()
		CONNECTING:
			_draw_connecting()
		ERROR:
			_draw_error()
	if hint_t > 0:
		PixelFont.draw_centered(self, hint, 192, 176, 1, Color("ff8060"), Hud.DARK)


func _draw_menu() -> void:
	var y := 70
	draw_rect(Rect2(122, y - 6, 140, ITEMS.size() * 14 + 8), Color(0, 0, 0, 0.6))
	for i in ITEMS.size():
		var label: String = ITEMS[i]
		if label == "INPUT DELAY":
			label = "INPUT DELAY < %d >" % Net.delay
		var col: Variant = [Color.WHITE, Color("c0c8ff")]
		if i == cursor:
			col = Hud.FIGHT_GRAD
			if (t / 15) % 2 == 0:
				PixelFont.draw(self, ">", Vector2(128, y + i * 14), 1, Hud.FIGHT_GRAD, Hud.DARK)
		PixelFont.draw_centered(self, label, 194, y + i * 14, 1, col, Hud.DARK, 0, true)
	var help := ["HOST A ROOM AND SEND THE CODE TO A FRIEND,", "OR JOIN WITH THE CODE THEY SENT YOU.",
			"NO IP ADDRESS OR PORT FORWARDING NEEDED."]
	if ITEMS[cursor] == "INPUT DELAY":
		help = ["FRAMES OF INPUT DELAY. HIGHER = FEWER ROLLBACKS,", "LOWER = SNAPPIER. 2 SUITS MOST CONNECTIONS.", ""]
	for i in help.size():
		PixelFont.draw_centered(self, help[i], 192, 140 + i * 10, 1, GREY, Hud.DARK)
	PixelFont.draw_centered(self, "UP/DOWN CHOOSE   ENTER OK   ESC BACK", 192, 204, 1, GREY, Hud.DARK)


func _draw_code_boxes(code: String, y: int, cursor_blink: bool) -> void:
	var n := NetRoom.CODE_LEN
	var x0 := 192 - (n * 28 - 4) / 2
	for i in n:
		var x := x0 + i * 28
		draw_rect(Rect2(x, y, 24, 30), Color("0a0a20"))
		draw_rect(Rect2(x, y, 24, 30), Color("e0a040"), false, 1.0)
		if i < code.length():
			PixelFont.draw_centered(self, code[i], x + 12, y + 5, 3, Hud.FIGHT_GRAD, Hud.DARK, 0, true)
		elif i == code.length() and cursor_blink and (t / 15) % 2 == 0:
			draw_rect(Rect2(x + 6, y + 24, 12, 2), Color.WHITE)


func _draw_entry() -> void:
	PixelFont.draw_centered(self, "ENTER ROOM CODE", 192, 50, 2, [Color.WHITE, Color("c0c8ff")], Hud.DARK, 0, true)
	_draw_code_boxes(typed, 76, true)
	PixelFont.draw_centered(self, "ASK THE HOST FOR THE CODE ON THEIR SCREEN", 192, 124, 1, GREY, Hud.DARK)
	PixelFont.draw_centered(self, "TYPE CODE   ENTER JOIN   CTRL+V PASTE   ESC BACK", 192, 204, 1, GREY, Hud.DARK)


func _draw_connecting() -> void:
	var r := Net.room
	var status := "READING ROOM CODE..." if r == null else r.status
	if r != null and r.is_host:
		PixelFont.draw_centered(self, "YOUR ROOM CODE", 192, 46, 1, [Color.WHITE, Color("c0c8ff")], Hud.DARK, 0, true)
		_draw_code_boxes(r.code, 58, false)
		PixelFont.draw_centered(self, "SEND THIS CODE TO YOUR OPPONENT", 192, 98, 1, GREY, Hud.DARK)
		if copied:
			PixelFont.draw_centered(self, "(COPIED TO CLIPBOARD)", 192, 109, 1, Color("80d080"), Hud.DARK)
	elif r != null:
		PixelFont.draw_centered(self, "JOINING ROOM", 192, 46, 1, [Color.WHITE, Color("c0c8ff")], Hud.DARK, 0, true)
		_draw_code_boxes(r.code, 58, false)
	var dots := ".".repeat((t / 20) % 4)
	PixelFont.draw_centered(self, status.trim_suffix("...") + (dots if status.ends_with("...") else ""), 192, 132, 1,
			Hud.FIGHT_GRAD, Hud.DARK, 0, true)
	if r != null and r.state == NetRoom.WAITING and r.is_host:
		PixelFont.draw_centered(self, "WAITING %dS" % (mode_t / 60), 192, 146, 1, GREY, Hud.DARK)
	PixelFont.draw_centered(self, "ESC CANCEL", 192, 204, 1, GREY, Hud.DARK)


func _draw_error() -> void:
	PixelFont.draw_centered(self, "CONNECTION FAILED", 192, 56, 2, Hud.KO_GRAD, Hud.DARK, 0, true)
	var lines := wrap_text(error_msg, 52)
	for i in lines.size():
		PixelFont.draw_centered(self, lines[i], 192, 90 + i * 11, 1, Color.WHITE, Hud.DARK)
	if mode_t > 20:
		PixelFont.draw_centered(self, "PRESS ANY KEY", 192, 204, 1, GREY, Hud.DARK)


static func wrap_text(s: String, max_chars: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for w in s.split(" ", false):
		if line != "" and line.length() + 1 + w.length() > max_chars:
			out.append(line)
			line = w
		else:
			line = w if line == "" else line + " " + w
	if line != "":
		out.append(line)
	return out
