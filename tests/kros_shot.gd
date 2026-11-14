extends SceneTree
## Visual check of KROS's sprites: the round intro (he throws off his cape), then KROS (P2)
## walks in and does st_mk, then st_hk, on an idle CED. Saves a screenshot every 4 frames of
## the intro and every 2 frames of each move. --skin=kros / kros_nocape forces one costume
## (no toss). Run (not headless):
## godot --path . --script res://tests/kros_shot.gd -- --out=DIR [--skin=kros]

var sim: MatchSim
var world: Node2D
var out := "user://"
var skin := ""
var tag := "kros"
var t0 := -1        # frame KROS starts the first move
var pending := ""   # screenshot to save once the last stepped frame has been drawn


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--skin="):
			skin = a.substr(7)
			tag = skin
	sim = MatchSim.new("ced", "kros")
	world = Node2D.new()
	root.add_child(world)
	var bg := Sprite2D.new()
	bg.texture = load("res://assets/stages/bedroom.png")
	bg.centered = false
	world.add_child(bg)
	for i in 2:
		var v := FighterView.new()
		v.setup(sim, i, false, skin if i == 1 else "")
		world.add_child(v)


func _input_p2() -> int:
	if sim.phase != MatchSim.FIGHT:
		return 0
	if t0 < 0:
		if (sim.f[1].x - sim.f[0].x) / 100 > 62:
			return Inp.LEFT
		t0 = sim.frame
	var k := sim.frame - t0
	if k == 0:
		return Inp.MK
	if k == 50:
		return Inp.HK
	return 0


func _process(_d: float) -> bool:
	if pending != "":
		root.get_texture().get_image().save_png(pending)
		pending = ""
	sim.step(0, _input_p2())
	world.position = Vector2(-sim.cam_x, 0)
	if sim.phase == MatchSim.INTRO and sim.pf % 4 == 0:   # round intro (cape toss)
		pending = "%s/%s_intro_%03d.png" % [out, tag, sim.pf]
	if t0 >= 0:
		var k := sim.frame - t0
		if k > 100:
			return true
		if k % 2 == 0:
			pending = "%s/%s_%03d.png" % [out, tag, k]
	return false
