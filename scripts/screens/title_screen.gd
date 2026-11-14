class_name TitleScreen
extends Node2D
## Title + main menu.

signal finished(action: String)

const ITEMS := ["VS CPU", "2 PLAYERS", "ONLINE", "CPU LEVEL", "QUIT"]
const ENABLED := [true, true, true, true, true]
const LEVELS := ["EASY", "NORMAL", "HARD"]

var cursor := 0
var t := 0
var bg: Texture2D
var pals := {}


func _ready() -> void:
	bg = load("res://assets/stages/bedroom.png")
	pals["ced"] = Puppet.palette("ced")
	pals["kros"] = Puppet.palette("kros")


func _physics_process(_delta: float) -> void:
	t += 1
	queue_redraw()
	if t > 60 * 25:
		finished.emit("demo")   # attract mode


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("p1_up"):
		cursor = (cursor + ITEMS.size() - 1) % ITEMS.size()
		Sfx.play("select")
		t = mini(t, 600)
	elif event.is_action_pressed("p1_down"):
		cursor = (cursor + 1) % ITEMS.size()
		Sfx.play("select")
		t = mini(t, 600)
	elif ITEMS[cursor] == "CPU LEVEL" and (event.is_action_pressed("p1_left") or event.is_action_pressed("p1_right")):
		var d := -1 if event.is_action_pressed("p1_left") else 1
		Game.cpu_level = clampi(Game.cpu_level + d, 0, 2)
		Sfx.play("select")
	elif event.is_action_pressed("menu_ok"):
		match ITEMS[cursor]:
			"VS CPU":
				Sfx.play("confirm")
				Game.p2_cpu = true
				finished.emit("select")
			"2 PLAYERS":
				Sfx.play("confirm")
				Game.p2_cpu = false
				finished.emit("select")
			"ONLINE":
				Sfx.play("confirm")
				finished.emit("online")
			"CPU LEVEL":
				Game.cpu_level = (Game.cpu_level + 1) % 3
				Sfx.play("select")
			"QUIT":
				get_tree().quit()
			_:
				Sfx.play("back")
	elif event.is_action_pressed("menu_back"):
		get_tree().quit()


func _draw() -> void:
	draw_texture(bg, Vector2(-64, 0))
	draw_rect(Rect2(0, 0, 384, 216), Color(0.05, 0.0, 0.08, 0.55))
	# fighters
	draw_set_transform(Vector2(92, 200), 0.0, Vector2(1, 1))
	Puppet.draw(self, "ced", pals["ced"], Poses.idle("ced", t), 0.0)
	draw_set_transform(Vector2(292, 200), 0.0, Vector2(-1, 1))
	Puppet.draw(self, "kros", pals["kros"], Poses.idle("kros", t + 30), sin(t * 0.07) * 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# logo
	PixelFont.draw_centered(self, "ARCADE", 192, 14, 4, Hud.ROUND_GRAD, Hud.DARK, 1, true, 2)
	PixelFont.draw_centered(self, "FIGHTER", 192, 46, 5, Hud.FIGHT_GRAD, Hud.DARK, 1, true, 2)
	# menu
	var y := 96
	draw_rect(Rect2(132, y - 6, 120, ITEMS.size() * 14 + 8), Color(0, 0, 0, 0.6))
	for i in ITEMS.size():
		var label: String = ITEMS[i]
		if label == "CPU LEVEL":
			label = "CPU: < %s >" % LEVELS[Game.cpu_level]
		var col: Variant = [Color.WHITE, Color("c0c8ff")]
		if not ENABLED[i]:
			col = Color("6a6a80")
			label += " (SOON)" if i != cursor else ""
		if i == cursor:
			col = Hud.FIGHT_GRAD if ENABLED[i] else Color("9a9ab0")
			if (t / 15) % 2 == 0:
				PixelFont.draw(self, ">", Vector2(138, y + i * 14), 1, Hud.FIGHT_GRAD, Hud.DARK)
		PixelFont.draw_centered(self, label, 194, y + i * 14, 1, col, Hud.DARK, 0, true)
	if not ENABLED[cursor]:
		PixelFont.draw_centered(self, "COMING SOON", 192, y + ITEMS.size() * 14 + 6, 1, Color("ff8060"), Hud.DARK)
	var keys := "ARROWS MOVE  A S D PUNCH  Z X C KICK"
	if ITEMS[cursor] == "2 PLAYERS":
		keys = "2P: IJKL MOVE  NUM 4 5 6 PUNCH  NUM 1 2 3 KICK"
	PixelFont.draw(self, keys, Vector2(4, 207), 1, Color("a0a0c0"), Hud.DARK)
