extends SceneTree
## In-game check of MURFURRIE's Spit: he does the motion (down, down-forward, forward + HP)
## at a given distance and the opponent stands, crouches or blocks. Saves a screenshot every
## 2 frames from the motion until the spit is gone and he is back in his stance.
## Run (not headless):
## godot --path . --script res://tests/spit_shot.gd -- --out=DIR [--vs=ced] [--gap=150]
##     [--crouch] [--block] [--boxes]
## --gap: distance (px) between the two before the spit (VS walks back to it). The spit flies
## level for a while, then drops to the floor about halfway across the screen.

var sim: MatchSim
var world: Node2D
var fx: Effects
var out := "user://"
var vs := "ced"
var gap := 150
var crouch := false
var block := false
var t0 := -1
var pending := ""
const MOTION := [Inp.DOWN, Inp.DOWN, Inp.DOWN | Inp.RIGHT, Inp.DOWN | Inp.RIGHT, Inp.RIGHT, Inp.RIGHT | Inp.HP]


func _init() -> void:
	var boxes := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--vs="): vs = a.substr(5)
		if a.begins_with("--gap="): gap = int(a.substr(6))
		if a == "--crouch": crouch = true
		if a == "--block": block = true
		if a == "--boxes": boxes = true
	sim = MatchSim.new("murfurrie", vs)
	world = Node2D.new()
	root.add_child(world)
	var bg := Sprite2D.new()
	bg.texture = load("res://assets/stages/bedroom.png")
	bg.centered = false
	world.add_child(bg)
	for i in 2:
		var v := FighterView.new()
		v.setup(sim, i, false)
		world.add_child(v)
	fx = Effects.new()
	fx.sim = sim
	fx.z_index = 5
	fx.show_boxes = boxes
	world.add_child(fx)


func _gap() -> int:
	return (sim.f[1].x - sim.f[0].x) / 100


func _input_p1() -> int:
	if sim.phase != MatchSim.FIGHT or _gap() < gap and t0 < 0:
		return 0
	if t0 < 0:
		t0 = sim.frame
	var k := sim.frame - t0
	return MOTION[k] if k < MOTION.size() else 0


func _input_p2() -> int:
	if sim.phase != MatchSim.FIGHT:
		return 0
	var near := sim.f[0].pj_on and absi(sim.f[1].x - sim.f[0].pj_x) < 6000
	var hold := (Inp.DOWN if crouch else 0) | (Inp.RIGHT if block and near else 0)
	if t0 < 0 and _gap() < gap:
		return Inp.RIGHT   # back off to the test distance
	return hold


func _process(_d: float) -> bool:
	if pending != "":
		root.get_texture().get_image().save_png(pending)
		pending = ""
	sim.step(_input_p1(), _input_p2())
	for e in sim.events:
		match String(e["t"]):
			"splat":
				fx.splat(float(e["x"]))
				print("splat at x %d: %d px from where he spat" % [e["x"], int(e["x"]) - sim.f[0].x / 100])
			"hit", "block":
				fx.spark(e["x"], e["y"], e["s"], e["t"] == "block")
				print("%s at frame %d" % [e["t"], sim.frame - t0])
			"spit":
				print("spit thrown at frame %d" % (sim.frame - t0))
	fx.tick()
	world.position = Vector2(-sim.cam_x, 0)
	if t0 >= 0:
		var k := sim.frame - t0
		var me := sim.f[0]
		if (k > 30 and not me.pj_on and me.state != Fighter.ATTACK) or k > 120:
			print("done after %d frames" % k)
			return true
		if k % 2 == 0:
			pending = "%s/spit_%03d.png" % [out, k]
	return false
