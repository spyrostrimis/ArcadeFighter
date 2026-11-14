class_name FightScreen
extends Node2D
## A match: runs the sim at 60 fps, feeds it local/CPU input, draws world + HUD.
## Online, the sim is driven by a Rollback session instead: sim events arrive
## through its callback (deduplicated across re-simulated frames), pause is
## off, and after the match both players choose rematch / change fighter / leave.

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

# online
const POST_ITEMS := ["REMATCH", "CHANGE FIGHTER", "LEAVE ROOM"]
const POST_CODES := ["rematch", "select", "quit"]
var online := false
var rb: Rollback
var me := 0
var brain: CpuBrain
var post_cursor := 0
var my_choice := ""
var their_choice := ""
var stall_run := 0
var esc_t := 0
var _done_t := -1


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


func setup_online(c1: String, c2: String) -> void:
	setup(c1, c2, false, false, Game.cpu_level, 0)
	online = true
	me = Net.local_slot
	hud.online_local = me
	rb = Rollback.new(sim, me, Net.delay, Net.match_id, Net.send_game, _on_rb_event, Time.get_ticks_msec())
	Net.session = rb
	Net.log_line("match %d start: %s vs %s, slot %d, delay %d" % [Net.match_id, c1, c2, me, Net.delay])
	if Game.opt.has("autoplay"):
		brain = CpuBrain.new(me, int(Game.opt.get("cpu", 2)), 1000 + me * 77 + Net.match_id)


func _exit_tree() -> void:
	if online and Net.session == rb:
		Net.session = null


func _on_rb_event(e: Dictionary, _fr: int) -> void:
	_event(e)


func _online_tick() -> void:
	if Net.room == null:
		return
	var li := 0
	if brain != null:
		li = brain.get_input(sim)
	elif esc_t == 0:
		li = Inp.read_local("p1")
	rb.tick(li, Time.get_ticks_msec())
	if rb.error != "":
		Net.last_error = rb.error
		Net.log_line("session error: " + rb.error)
		Net.leave()
		if Game.opt.has("autoplay"):
			Game.auto_report({"error": rb.error})
			get_tree().quit(1)
		finished.emit("online_error")
		return
	fx.tick()
	hud.tick()
	if _shake > 0:
		_shake -= 1
	if _flash > 0:
		_flash -= 1
	if esc_t > 0:
		esc_t -= 1
	stall_run = stall_run + 1 if rb.stalled else 0
	for m in Net.take_ctl():
		match String(m.get("t", "")):
			"post":
				their_choice = String(m.get("c", ""))
			"start":
				if me == 1:
					Game.p1_char = String(m["p1"])
					Game.p2_char = String(m["p2"])
					Net.match_id = int(m["m"])
					Net.delay = int(m["delay"])
					finished.emit("online_fight")
					return
			"goto":
				if me == 1:
					finished.emit("online_select")
					return
	if sim.phase != MatchSim.MATCH_OVER:
		return
	if brain != null and my_choice == "" and sim.pf > 150:
		_auto_post()
	if my_choice == "done" and their_choice == "done":
		if _done_t < 0:
			_done_t = 30
		_done_t -= 1
		if _done_t == 0:
			Net.leave()
			get_tree().quit(0)
		return
	if me == 0 and my_choice != "" and their_choice != "" and my_choice != "done":
		if my_choice == "rematch" and their_choice == "rematch":
			Net.match_id = (Net.match_id + 1) & 0xff
			Net.send_ctl({"t": "start", "p1": Game.p1_char, "p2": Game.p2_char, "m": Net.match_id, "delay": Net.delay})
			finished.emit("online_fight")
		elif their_choice != "quit":
			Net.send_ctl({"t": "goto", "s": "select"})
			finished.emit("online_select")


func _choose(code: String) -> void:
	my_choice = code
	Net.send_ctl({"t": "post", "c": code})
	Net.log_line("post-match choice: " + code)
	if code == "quit":
		Net.leave()
		finished.emit("online")


## --autoplay: report this match's sync stats, then rematch until --matches.
func _auto_post() -> void:
	var keys := rb.check_log.keys()
	keys.sort()
	var last := {}
	for k in keys.slice(maxi(0, keys.size() - 8)):
		last[str(k)] = rb.check_log[k]
	Game.auto_report({"match": Net.match_id, "slot": me, "p1": Game.p1_char, "p2": Game.p2_char,
			"winner": sim.match_winner, "frames": rb.frame, "checks_matched": rb.checks_matched,
			"desync": rb.desync_frame, "rollbacks": rb.rollbacks, "rb_frames": rb.rb_frames,
			"max_depth": rb.max_depth, "stalls": rb.stalls, "waits": rb.waits, "rtt_ms": int(rb.rtt_ms),
			"delay": rb.delay, "checks": last})
	Game.auto_matches += 1
	if Game.auto_matches < int(Game.opt.get("matches", 1)):
		_choose("select" if Game.opt.has("reselect") and Game.auto_matches == 1 else "rematch")
	else:
		Game.opt["auto_done"] = "1"
		_choose("done")


func _physics_process(_delta: float) -> void:
	if online:
		_online_tick()
		return
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
	if online:
		_online_input(event)
		return
	if demo and event.is_pressed() and not event.is_echo() and (event is InputEventKey or event is InputEventJoypadButton):
		finished.emit("title")
		return
	if event.is_action_pressed("menu_pause") and sim.phase != MatchSim.MATCH_OVER:
		paused = not paused
		Sfx.play("select")
		get_viewport().set_input_as_handled()
	elif paused and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_Q:
		finished.emit("title")


func _online_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var post_open := sim.phase == MatchSim.MATCH_OVER and sim.pf > 90 and my_choice == "" and brain == null
	if post_open:
		if event.is_action_pressed("p1_up") or event.is_action_pressed("p1_down"):
			var d := -1 if event.is_action_pressed("p1_up") else 1
			post_cursor = (post_cursor + POST_ITEMS.size() + d) % POST_ITEMS.size()
			Sfx.play("select")
		elif event.is_action_pressed("menu_ok"):
			Sfx.play("confirm")
			_choose(POST_CODES[post_cursor])
		return
	# No pause online: ESC twice leaves the room.
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if esc_t > 0:
			Sfx.play("back")
			Net.leave()
			finished.emit("online")
		else:
			esc_t = 120
			Sfx.play("select")
		get_viewport().set_input_as_handled()


func _handle_events() -> void:
	for e in sim.events:
		_event(e)


func _event(e: Dictionary) -> void:
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
			if cpus[0] == null and cpus[1] == null:
				human = -1   # local 2 players: someone always wins
			if online:
				human = me
			if human >= 0 and w != human:
				Sfx.play("lose")
			else:
				Sfx.play("win")


func _draw_overlay() -> void:
	if _flash > 0:
		overlay.draw_rect(Rect2(0, 0, 384, 216), Color(1, 1, 1, _flash / 8.0))
	if online:
		_draw_online()
	if paused:
		overlay.draw_rect(Rect2(0, 0, 384, 216), Color(0, 0, 0, 0.6))
		PixelFont.draw_centered(overlay, "PAUSED", 192, 80, 3, Hud.ROUND_GRAD, Hud.DARK, 1, true, 2)
		PixelFont.draw_centered(overlay, "ESC  RESUME", 192, 116, 1, Color.WHITE, Hud.DARK)
		PixelFont.draw_centered(overlay, "Q    QUIT TO TITLE", 192, 128, 1, Color.WHITE, Hud.DARK)
		PixelFont.draw_centered(overlay, "F2   SHOW HITBOXES", 192, 140, 1, Color("a0a8c0"), Hud.DARK)


func _draw_online() -> void:
	var grey := Color("a0a8c0")
	var depth := rb.last_depth if rb.rollbacks > 0 else 0
	PixelFont.draw(overlay, "PING %d  ROLLBACK %dF  DELAY %d" % [int(rb.rtt_ms), depth, rb.delay],
			Vector2(4, 207), 1, grey, Hud.DARK)
	var tx := 4 if me == 0 else 380 - PixelFont.width("YOU", 1, true)
	PixelFont.draw(overlay, "YOU", Vector2(tx, 38), 1, Hud.FIGHT_GRAD, Hud.DARK, 0, true)
	if rb.desync_frame >= 0:
		PixelFont.draw_centered(overlay, "DESYNC DETECTED", 192, 196, 1, Color("ff6050"), Hud.DARK)
	if stall_run > 30:
		PixelFont.draw_centered(overlay, "WAITING FOR OPPONENT...", 192, 120, 1, Color.WHITE, Hud.DARK)
	if esc_t > 0:
		PixelFont.draw_centered(overlay, "PRESS ESC AGAIN TO LEAVE THE ROOM", 192, 150, 1, Color.WHITE, Hud.DARK)
	if sim.phase != MatchSim.MATCH_OVER or sim.pf <= 90:
		return
	var y := 128
	overlay.draw_rect(Rect2(116, y - 6, 152, POST_ITEMS.size() * 12 + 22), Color(0, 0, 0, 0.65))
	for i in POST_ITEMS.size():
		var sel := i == post_cursor and my_choice == ""
		var col: Variant = Hud.FIGHT_GRAD if sel else [Color.WHITE, Color("c0c8ff")]
		if my_choice != "" and POST_CODES[i] != my_choice:
			col = Color("6a6a80")
		if sel and (sim.frame / 15) % 2 == 0:
			PixelFont.draw(overlay, ">", Vector2(122, y + i * 12), 1, Hud.FIGHT_GRAD, Hud.DARK)
		PixelFont.draw_centered(overlay, POST_ITEMS[i], 194, y + i * 12, 1, col, Hud.DARK, 0, true)
	var line := ""
	if their_choice == "rematch":
		line = "OPPONENT WANTS A REMATCH"
	elif their_choice == "select":
		line = "OPPONENT WANTS TO CHANGE FIGHTER"
	elif my_choice != "":
		line = "WAITING FOR OPPONENT..."
	if line != "":
		PixelFont.draw_centered(overlay, line, 192, y + POST_ITEMS.size() * 12 + 4, 1, Color("80d0ff"), Hud.DARK)
