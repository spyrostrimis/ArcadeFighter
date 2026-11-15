class_name SelectScreen
extends Node2D
## Character select: player picks a fighter, then picks the CPU opponent.
## 2 players (Game.p2_cpu false): both pick at the same time, each with their own cursor.
## Online: each player moves their own cursor (shown live on both screens);
## when both have picked, the host sends "start" and both go to the VS splash.

signal finished(action: String)

var cursor := [0, 1]
var stage := 0        # 0 = P1 picking, 1 = picking CPU, 2 = VS splash
var t := 0
var vs_t := 0
var pals := {}
var online := false
var local2 := false   # local 2 players
var me := 0
var picked := [false, false]
var _auto_t := -1


func _ready() -> void:
	for c in Game.CHARACTERS:
		pals[c] = Puppet.palette(c)
		pals[c + "_alt"] = Puppet.palette(c, true)
	cursor[0] = Game.CHARACTERS.find(Game.p1_char)
	cursor[1] = Game.CHARACTERS.find(Game.p2_char)
	local2 = not online and not Game.p2_cpu
	if online:
		me = Net.local_slot
		stage = 0
		if Game.opt.has("autopick"):
			_auto_t = 40


func _send_sel() -> void:
	Net.send_ctl({"t": "sel", "cur": cursor[me], "picked": picked[me]})


func _online_tick() -> void:
	if t == 1 or t % 30 == 0:
		_send_sel()   # also repairs a cursor update the other side missed
	for m in Net.take_ctl():
		match String(m.get("t", "")):
			"sel":
				if stage != 2:
					cursor[1 - me] = clampi(int(m.get("cur", 0)), 0, Game.CHARACTERS.size() - 1)
					picked[1 - me] = bool(m.get("picked", false))
			"start":
				if me == 1 and stage != 2:
					_start_from(m)
	if _auto_t > 0:
		_auto_t -= 1
		if _auto_t == 0:
			var i := Game.CHARACTERS.find(String(Game.opt["autopick"]))
			cursor[me] = maxi(0, i)
			picked[me] = true
			_send_sel()
	if me == 0 and stage != 2 and picked[0] and picked[1]:
		Net.match_id = (Net.match_id + 1) & 0xff
		var msg := {"t": "start", "p1": Game.CHARACTERS[cursor[0]], "p2": Game.CHARACTERS[cursor[1]],
				"m": Net.match_id, "delay": Net.delay}
		Net.send_ctl(msg)
		_start_from(msg)


func _start_from(m: Dictionary) -> void:
	Game.p1_char = String(m["p1"])
	Game.p2_char = String(m["p2"])
	cursor[0] = Game.CHARACTERS.find(Game.p1_char)
	cursor[1] = Game.CHARACTERS.find(Game.p2_char)
	Net.match_id = int(m["m"])
	Net.delay = int(m["delay"])
	picked = [true, true]
	stage = 2
	vs_t = 0
	Sfx.play("confirm")


func _physics_process(_delta: float) -> void:
	t += 1
	if online:
		_online_tick()
	if stage == 2:
		vs_t += 1
		if vs_t >= 110:
			finished.emit("online_fight" if online else "fight")
			return
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or stage == 2:
		return
	if online:
		_online_input(event)
		return
	if local2:
		_local2_input(event)
		return
	var n := Game.CHARACTERS.size()
	if event.is_action_pressed("p1_left"):
		cursor[stage] = (cursor[stage] + n - 1) % n
		Sfx.play("select")
	elif event.is_action_pressed("p1_right"):
		cursor[stage] = (cursor[stage] + 1) % n
		Sfx.play("select")
	elif event.is_action_pressed("menu_ok") or event.is_action_pressed("p1_lp") or event.is_action_pressed("p1_lk"):
		Sfx.play("confirm")
		if stage == 0:
			Game.p1_char = Game.CHARACTERS[cursor[0]]
			stage = 1
		else:
			Game.p2_char = Game.CHARACTERS[cursor[1]]
			Game.p1_cpu = false
			Game.p2_cpu = true
			stage = 2
	elif event.is_action_pressed("menu_back"):
		Sfx.play("back")
		if stage == 1:
			stage = 0
		else:
			finished.emit("title")


func _local2_input(event: InputEvent) -> void:
	var n := Game.CHARACTERS.size()
	for s in 2:
		var p := "p%d_" % (s + 1)
		if not picked[s] and (event.is_action_pressed(p + "left") or event.is_action_pressed(p + "right")):
			var d := -1 if event.is_action_pressed(p + "left") else 1
			cursor[s] = (cursor[s] + n + d) % n
			Sfx.play("select")
			return
		var ok := event.is_action_pressed(p + "lp") or event.is_action_pressed(p + "lk")
		if s == 0:
			ok = ok or event.is_action_pressed("menu_ok")
		if not picked[s] and ok:
			picked[s] = true
			Sfx.play("confirm")
			if picked[0] and picked[1]:
				Game.p1_char = Game.CHARACTERS[cursor[0]]
				Game.p2_char = Game.CHARACTERS[cursor[1]]
				Game.p1_cpu = false
				Game.p2_cpu = false
				stage = 2
				vs_t = 0
			return
		if picked[s] and (event.is_action_pressed(p + "mp") or event.is_action_pressed(p + "mk")):
			picked[s] = false
			Sfx.play("back")
			return
	if event.is_action_pressed("menu_back"):
		Sfx.play("back")
		if picked[0] or picked[1]:
			picked = [false, false]
		else:
			finished.emit("title")


func _online_input(event: InputEvent) -> void:
	var n := Game.CHARACTERS.size()
	if not picked[me] and (event.is_action_pressed("p1_left") or event.is_action_pressed("p1_right")):
		var d := -1 if event.is_action_pressed("p1_left") else 1
		cursor[me] = (cursor[me] + n + d) % n
		Sfx.play("select")
		_send_sel()
	elif not picked[me] and (event.is_action_pressed("menu_ok") or event.is_action_pressed("p1_lp") or event.is_action_pressed("p1_lk")):
		picked[me] = true
		Sfx.play("confirm")
		_send_sel()
	elif event.is_action_pressed("menu_back"):
		Sfx.play("back")
		if picked[me]:
			picked[me] = false
			_send_sel()
		else:
			Net.leave()
			finished.emit("online")


func _pal(slot: int) -> Dictionary:
	var c: String = Game.CHARACTERS[cursor[slot]]
	if slot == 1 and cursor[0] == cursor[1]:
		return pals[c + "_alt"]
	return pals[c]


func _draw() -> void:
	# background: dark purple with scrolling diagonal stripes
	draw_rect(Rect2(0, 0, 384, 216), Color("1a0e28"))
	for i in range(-10, 30):
		var x := i * 24 + (t / 2) % 24
		draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 10, 0), Vector2(x - 60, 216), Vector2(x - 70, 216)]),
				Color("241438"))
	draw_rect(Rect2(0, 186, 384, 30), Color("10081a"))
	if stage == 2:
		_draw_vs()
		return
	var title := "SELECT YOUR FIGHTER" if stage == 0 else "SELECT OPPONENT"
	if online and picked[me]:
		title = "WAITING FOR OPPONENT"
	elif local2:
		title = "SELECT YOUR FIGHTERS"
	PixelFont.draw_centered(self, title, 192, 8, 2, Hud.ROUND_GRAD, Hud.DARK, 1, true, 1)
	var tags := ["1P", "CPU"]
	if online:
		tags = ["YOU" if me == 0 else "1P", "YOU" if me == 1 else "2P"]
	elif local2:
		tags = ["1P", "2P"]
	var both := online or local2   # both cursors move at the same time
	# full-body previews
	var c0: String = Game.CHARACTERS[cursor[0]]
	draw_set_transform(Vector2(66, 196), 0.0, Vector2(1, 1))
	Puppet.draw(self, c0, _pal(0), Poses.idle(c0, t), sin(t * 0.07) * 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelFont.draw_centered(self, String(CharData.get_data(c0)["name"]), 66, 48, 1, Hud.NAME_GRAD, Hud.DARK, 0, true)
	PixelFont.draw_centered(self, tags[0], 66, 30, 2, [Color("ff9070"), Color("e83818")], Hud.DARK, 0, true)
	if both and picked[0]:
		PixelFont.draw_centered(self, "READY", 66, 60, 1, Hud.FIGHT_GRAD, Hud.DARK, 0, true)
	if stage == 1 or both:
		var c1: String = Game.CHARACTERS[cursor[1]]
		draw_set_transform(Vector2(318, 196), 0.0, Vector2(-1, 1))
		Puppet.draw(self, c1, _pal(1), Poses.idle(c1, t + 20), sin(t * 0.07) * 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		PixelFont.draw_centered(self, String(CharData.get_data(c1)["name"]), 318, 48, 1, Hud.NAME_GRAD, Hud.DARK, 0, true)
		PixelFont.draw_centered(self, tags[1], 318, 30, 2, [Color("a0d0ff"), Color("3068e0")], Hud.DARK, 0, true)
		if both and picked[1]:
			PixelFont.draw_centered(self, "READY", 318, 60, 1, Hud.FIGHT_GRAD, Hud.DARK, 0, true)
	# portrait cards: 64 px wide for two fighters, narrower so three fit between the previews
	var n := Game.CHARACTERS.size()
	var cw := 64 if n <= 2 else 58
	var gap := 8 if n <= 2 else 3
	var row_x := 192 - (n * cw + (n - 1) * gap) / 2
	for i in n:
		var c: String = Game.CHARACTERS[i]
		var x0 := row_x + i * (cw + gap)
		var y0 := 60
		var pal: Dictionary = pals[c]
		draw_rect(Rect2(x0 - 1, y0 - 1, cw + 2, 76), Color("0a0a20"))
		draw_rect(Rect2(x0, y0, cw, 74), Color("e0a040"))
		draw_rect(Rect2(x0 + 2, y0 + 2, cw - 4, 70), Color("7a1c18") if i == 0 else Color("2a1840"))
		draw_rect(Rect2(x0 + 2, y0 + 50, cw - 4, 12), pal["top"])
		Puppet.draw_portrait(self, c, pal, Vector2(x0 + cw / 2, y0 + 30), 2.4 if n <= 2 else 2.2, i == n - 1, false)
		draw_rect(Rect2(x0 + 2, y0 + 62, cw - 4, 10), Color("0a0a20"))
		var nm := String(CharData.get_data(c)["name"])
		PixelFont.draw_centered(self, nm, x0 + cw / 2, y0 + 64, 1, Hud.NAME_GRAD, null, 0,
				PixelFont.width(nm, 1, true) <= cw - 4)
		# cursors
		var blink := (t / 8) % 2 == 0
		var show0: bool = (stage == 0 and blink or stage == 1) if not both else (blink or picked[0])
		var show1: bool = (stage == 1 and blink) if not both else (blink or picked[1])
		if cursor[0] == i and show0:
			draw_rect(Rect2(x0 - 3, y0 - 3, cw + 6, 80), Color("ff3020"), false, 2.0)
			PixelFont.draw(self, tags[0], Vector2(x0 - 2, y0 - 12), 1, [Color("ff9070"), Color("e83818")], Hud.DARK, 0, true)
		if (stage == 1 or both) and cursor[1] == i and show1:
			draw_rect(Rect2(x0 - 5, y0 - 5, cw + 10, 84), Color("40a0ff"), false, 2.0)
			var tw := PixelFont.width(tags[1], 1, true)
			PixelFont.draw(self, tags[1], Vector2(x0 + cw + 2 - tw, y0 - 12), 1, [Color("a0d0ff"), Color("3068e0")], Hud.DARK, 0, true)
	var help := "LEFT/RIGHT CHOOSE   ENTER OR A CONFIRM   ESC BACK"
	if local2:
		help = "1P ARROWS + A    2P IJKL + NUM 4    ESC BACK"
	if online:
		help = "ESC CANCEL PICK" if picked[me] else "LEFT/RIGHT CHOOSE   ENTER OR A CONFIRM   ESC LEAVE ROOM"
		if Net.room != null:
			PixelFont.draw(self, "ROOM " + Net.room.code, Vector2(4, 190), 1, Color("6a6a90"), Hud.DARK)
	PixelFont.draw_centered(self, help, 192, 204, 1, Color("a0a0c0"), Hud.DARK)


func _draw_vs() -> void:
	var c0: String = Game.CHARACTERS[cursor[0]]
	var c1: String = Game.CHARACTERS[cursor[1]]
	var slide := clampf(vs_t / 20.0, 0.0, 1.0)
	draw_set_transform(Vector2(lerpf(-60, 96, slide), 196), 0.0, Vector2(1, 1))
	Puppet.draw(self, c0, _pal(0), Poses.idle(c0, t), 0.0)
	draw_set_transform(Vector2(lerpf(444, 288, slide), 196), 0.0, Vector2(-1, 1))
	Puppet.draw(self, c1, _pal(1), Poses.idle(c1, t + 20), sin(t * 0.07) * 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelFont.draw_centered(self, String(CharData.get_data(c0)["name"]), 96, 200, 2, Hud.NAME_GRAD, Hud.DARK, 1, true)
	PixelFont.draw_centered(self, String(CharData.get_data(c1)["name"]), 288, 200, 2, Hud.NAME_GRAD, Hud.DARK, 1, true)
	if vs_t > 18:
		PixelFont.draw_centered(self, "VS", 192, 70, 6, Hud.FIGHT_GRAD, Hud.DARK, 1, true, 2)
