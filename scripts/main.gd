extends Node
## Screen manager (title -> select -> fight) plus test hooks:
##   -- --demo                 CPU vs CPU fight straight away
##   -- --screen=title|select  open a screen directly
##   -- --p1=ced --p2=kros     characters for --demo
##   -- --shot=prefix --shot_at=60,300   save screenshots at those frames, then quit
## Online test hooks (see docs/online.md):
##   -- --host [--room=CODE] [--codefile=PATH]   host a room straight away
##   -- --join=CODE | --join=@PATH               join (code read from a file)
##   -- --autopick=ced   --autoplay   --matches=2   --result=PATH   --quit_after=SECONDS

var current: Node
var frames := 0
var shot_frames: Array = []


func _ready() -> void:
	var o: Dictionary = Game.opt
	if o.has("shot_at"):
		for s in String(o["shot_at"]).split(","):
			shot_frames.append(int(s))
	if o.has("p1"):
		Game.p1_char = o["p1"]
	if o.has("p2"):
		Game.p2_char = o["p2"]
	Net.lost.connect(_on_net_lost)
	if o.has("host") or o.has("join"):
		_goto(OnlineScreen.new())
	elif o.has("demo"):
		_fight(true)
	elif o.get("screen", "") == "select":
		_goto(SelectScreen.new())
	elif o.get("screen", "") == "fight":
		_fight(false)
	else:
		_title()


func _goto(n: Node) -> void:
	if current != null:
		current.queue_free()
	current = n
	add_child(n)
	if n.has_signal("finished"):
		n.connect("finished", _on_finished)


func _title() -> void:
	_goto(TitleScreen.new())


func _fight(demo: bool) -> void:
	var fs := FightScreen.new()
	var chars := Game.CHARACTERS
	var c1 := Game.p1_char
	var c2 := Game.p2_char
	if demo and not Game.opt.has("p1"):
		c1 = chars[randi() % chars.size()]
		c2 = chars[randi() % chars.size()]
	fs.setup(c1, c2, demo, demo or Game.p2_cpu, Game.cpu_level, randi())
	_goto(fs)


func _online(error := "") -> void:
	var s := OnlineScreen.new()
	s.error_msg = error
	_goto(s)


func _on_net_lost(reason: String) -> void:
	if Game.opt.has("autoplay"):
		if not Game.opt.has("auto_done"):   # the other side finishing first is fine
			Game.auto_report({"lost": reason})
		get_tree().quit(0 if Game.opt.has("auto_done") else 1)
		return
	_online(reason)


func _on_finished(action: String) -> void:
	match action:
		"online":
			_online()
		"online_error":
			_online(Net.last_error)
		"online_select":
			var ss := SelectScreen.new()
			ss.online = true
			_goto(ss)
		"online_fight":
			var fs := FightScreen.new()
			fs.setup_online(Game.p1_char, Game.p2_char)
			_goto(fs)
		"title":
			_title()
		"select":
			_goto(SelectScreen.new())
		"fight":
			_fight(false)
		"demo":
			_fight(true)


func _physics_process(_delta: float) -> void:
	frames += 1
	if Game.opt.has("inputtest"):
		# scripted key presses for automated checks of the human input path
		var script := {200: ["p1_right", true], 240: ["p1_right", false], 250: ["p1_hp", true], 254: ["p1_hp", false],
			290: ["p1_down", true], 292: ["p1_hk", true], 296: ["p1_hk", false], 330: ["p1_down", false],
			340: ["p1_up", true], 344: ["p1_up", false], 362: ["p1_mk", true], 366: ["p1_mk", false]}
		if script.has(frames):
			var a: Array = script[frames]
			if a[1]:
				Input.action_press(a[0])
			else:
				Input.action_release(a[0])
	if Game.opt.has("quit_after") and frames > int(Game.opt["quit_after"]) * 60:
		Game.auto_report({"error": "quit_after timeout"})
		get_tree().quit(2)
	if shot_frames.is_empty():
		return
	if frames in shot_frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var prefix: String = Game.opt.get("shot", "user://shot")
		img.save_png("%s_%d.png" % [prefix, frames])
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
		img.save_png("%s_%d_x3.png" % [prefix, frames])
	if frames > shot_frames.max() and not Game.opt.has("autoplay"):
		get_tree().quit()
