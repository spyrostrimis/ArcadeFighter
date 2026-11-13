class_name SelectScreen
extends Node2D
## Character select: player picks a fighter, then picks the CPU opponent.

signal finished(action: String)

var cursor := [0, 1]
var stage := 0        # 0 = P1 picking, 1 = picking CPU, 2 = VS splash
var t := 0
var vs_t := 0
var pals := {}


func _ready() -> void:
	for c in Game.CHARACTERS:
		pals[c] = Puppet.palette(c)
		pals[c + "_alt"] = Puppet.palette(c, true)
	cursor[0] = Game.CHARACTERS.find(Game.p1_char)
	cursor[1] = Game.CHARACTERS.find(Game.p2_char)


func _physics_process(_delta: float) -> void:
	t += 1
	if stage == 2:
		vs_t += 1
		if vs_t >= 110:
			finished.emit("fight")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or stage == 2:
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
	PixelFont.draw_centered(self, "SELECT YOUR FIGHTER" if stage == 0 else "SELECT OPPONENT", 192, 8, 2,
			Hud.ROUND_GRAD, Hud.DARK, 1, true, 1)
	# full-body previews
	var c0: String = Game.CHARACTERS[cursor[0]]
	draw_set_transform(Vector2(66, 196), 0.0, Vector2(1, 1))
	Puppet.draw(self, c0, _pal(0), Poses.idle(c0, t), sin(t * 0.07) * 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	PixelFont.draw_centered(self, String(CharData.get_data(c0)["name"]), 66, 48, 1, Hud.NAME_GRAD, Hud.DARK, 0, true)
	PixelFont.draw_centered(self, "1P", 66, 30, 2, [Color("ff9070"), Color("e83818")], Hud.DARK, 0, true)
	if stage == 1:
		var c1: String = Game.CHARACTERS[cursor[1]]
		draw_set_transform(Vector2(318, 196), 0.0, Vector2(-1, 1))
		Puppet.draw(self, c1, _pal(1), Poses.idle(c1, t + 20), sin(t * 0.07) * 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		PixelFont.draw_centered(self, String(CharData.get_data(c1)["name"]), 318, 48, 1, Hud.NAME_GRAD, Hud.DARK, 0, true)
		PixelFont.draw_centered(self, "CPU", 318, 30, 2, [Color("a0d0ff"), Color("3068e0")], Hud.DARK, 0, true)
	# portrait cards
	for i in Game.CHARACTERS.size():
		var c: String = Game.CHARACTERS[i]
		var x0 := 192 - 68 + i * 72
		var y0 := 60
		var pal: Dictionary = pals[c]
		draw_rect(Rect2(x0 - 1, y0 - 1, 66, 76), Color("0a0a20"))
		draw_rect(Rect2(x0, y0, 64, 74), Color("e0a040"))
		draw_rect(Rect2(x0 + 2, y0 + 2, 60, 70), Color("7a1c18") if i == 0 else Color("2a1840"))
		draw_rect(Rect2(x0 + 2, y0 + 50, 60, 12), pal["top"])
		Puppet.draw_portrait(self, c, pal, Vector2(x0 + 32, y0 + 30), 2.4, i == 1, false)
		draw_rect(Rect2(x0 + 2, y0 + 62, 60, 10), Color("0a0a20"))
		PixelFont.draw_centered(self, String(CharData.get_data(c)["name"]), x0 + 32, y0 + 64, 1, Hud.NAME_GRAD, null, 0, true)
		# cursors
		var blink := (t / 8) % 2 == 0
		if cursor[0] == i and (stage == 0 and blink or stage == 1):
			draw_rect(Rect2(x0 - 3, y0 - 3, 70, 80), Color("ff3020"), false, 2.0)
			PixelFont.draw(self, "1P", Vector2(x0 - 2, y0 - 12), 1, [Color("ff9070"), Color("e83818")], Hud.DARK, 0, true)
		if stage == 1 and cursor[1] == i and blink:
			draw_rect(Rect2(x0 - 5, y0 - 5, 74, 84), Color("40a0ff"), false, 2.0)
			PixelFont.draw(self, "CPU", Vector2(x0 + 46, y0 - 12), 1, [Color("a0d0ff"), Color("3068e0")], Hud.DARK, 0, true)
	PixelFont.draw_centered(self, "LEFT/RIGHT CHOOSE   ENTER OR A CONFIRM   ESC BACK", 192, 204, 1, Color("a0a0c0"), Hud.DARK)


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
