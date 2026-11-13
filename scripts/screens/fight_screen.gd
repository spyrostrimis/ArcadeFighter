class_name FightScreen
extends Node2D
## A match: runs the sim at 60 fps, feeds it local/CPU input, draws world + HUD.

signal finished(action: String)

var sim: MatchSim
var cpus: Array = [null, null]
var demo := false
var world: Node2D
var views: Array[FighterView] = []
var fx: Effects
var hud: Hud
var overlay: Node2D
var paused := false
var _shake := 0
var _flash := 0
var _hi_saved := false


func setup(c1: String, c2: String, cpu1: bool, cpu2: bool, level: int, seed_value: int) -> void:
	sim = MatchSim.new(c1, c2)
	demo = cpu1 and cpu2
	if cpu1:
		cpus[0] = CpuBrain.new(0, level, seed_value)
	if cpu2:
		cpus[1] = CpuBrain.new(1, level, seed_value + 1)

	world = Node2D.new()
	add_child(world)
	var bg := Sprite2D.new()
	bg.texture = load("res://assets/stages/bedroom.png")
	bg.centered = false
	world.add_child(bg)
	var mirror := c1 == c2
	for i in 2:
		var v := FighterView.new()
		v.setup(sim, i, mirror and i == 1)
		world.add_child(v)
		views.append(v)
	fx = Effects.new()
	fx.sim = sim
	fx.z_index = 5
	world.add_child(fx)
	hud = Hud.new()
	hud.z_index = 10
	add_child(hud)
	hud.setup(sim, [views[0].pal, views[1].pal], [cpu1, cpu2], demo)
	overlay = Node2D.new()
	overlay.z_index = 20
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	_handle_events()


func _physics_process(_delta: float) -> void:
	if paused or sim == null:
		return
	var i0: int = cpus[0].get_input(sim) if cpus[0] != null else Inp.read_local("p1")
	var i1: int = cpus[1].get_input(sim) if cpus[1] != null else Inp.read_local("p2")
	sim.step(i0, i1)
	_handle_events()
	fx.tick()
	hud.tick()
	if _shake > 0:
		_shake -= 1
	if _flash > 0:
		_flash -= 1
	if sim.phase == MatchSim.MATCH_OVER:
		if not _hi_saved:
			_hi_saved = true
			Game.hi_score = maxi(Game.hi_score, sim.f[0].score)
		if demo and sim.pf > 240:
			finished.emit("title")
		elif sim.pf > 90 and Input.is_action_just_pressed("menu_ok"):
			Sfx.play("confirm")
			finished.emit("select")


func _process(_delta: float) -> void:
	if sim == null:
		return
	var sx := 0.0
	var sy := 0.0
	if _shake > 0:
		sx = (1 if _shake % 2 == 0 else -1) * mini(3, 1 + _shake / 4)
		sy = (1 if (_shake / 2) % 2 == 0 else -1) * mini(2, _shake / 5)
	world.position = Vector2(-sim.cam_x + sx, sy)
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_boxes"):
		fx.show_boxes = not fx.show_boxes
	if demo and event.is_pressed() and not event.is_echo() and (event is InputEventKey or event is InputEventJoypadButton):
		finished.emit("title")
		return
	if event.is_action_pressed("menu_pause") and sim.phase != MatchSim.MATCH_OVER:
		paused = not paused
		Sfx.play("select")
		get_viewport().set_input_as_handled()
	elif paused and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_Q:
		finished.emit("title")


func _handle_events() -> void:
	for e in sim.events:
		var t: String = e["t"]
		match t:
			"round":
				Sfx.play("round")
				hud.reset_bars()
			"fight":
				Sfx.play("fight")
			"swing":
				Sfx.play("swing%d" % e["s"], -4.0)
			"hit":
				Sfx.play("hit%d" % e["s"])
				fx.spark(e["x"], e["y"], e["s"], false)
				if e["s"] == 2:
					_shake = maxi(_shake, 10)
				hud.show_combo(e["attacker"], e["combo"])
			"block":
				Sfx.play("block")
				fx.spark(e["x"], e["y"], e["s"], true)
			"ko":
				Sfx.play("ko", 2.0)
				fx.spark(e["x"], e["y"], 2, false)
				_shake = 24
				_flash = 6
			"land":
				Sfx.play("land", -10.0)
			"thud":
				Sfx.play("thud", -2.0)
				fx.dust(sim.f[e["slot"]].x / 100.0, e["s"] == 2)
				_shake = maxi(_shake, 6)
			"jump":
				Sfx.play("swing0", -14.0, 0.7)
			"time_over":
				Sfx.play("round")
			"match_over":
				var w: int = e["w"]
				var human := 0 if cpus[0] == null else (1 if cpus[1] == null else -1)
				if human >= 0 and w != human:
					Sfx.play("lose")
				else:
					Sfx.play("win")


func _draw_overlay() -> void:
	if _flash > 0:
		overlay.draw_rect(Rect2(0, 0, 384, 216), Color(1, 1, 1, _flash / 8.0))
	if paused:
		overlay.draw_rect(Rect2(0, 0, 384, 216), Color(0, 0, 0, 0.6))
		PixelFont.draw_centered(overlay, "PAUSED", 192, 80, 3, Hud.ROUND_GRAD, Hud.DARK, 1, true, 2)
		PixelFont.draw_centered(overlay, "ESC  RESUME", 192, 116, 1, Color.WHITE, Hud.DARK)
		PixelFont.draw_centered(overlay, "Q    QUIT TO TITLE", 192, 128, 1, Color.WHITE, Hud.DARK)
		PixelFont.draw_centered(overlay, "F2   SHOW HITBOXES", 192, 140, 1, Color("a0a8c0"), Hud.DARK)
