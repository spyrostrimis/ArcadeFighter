extends SceneTree
## Check of CED's flying knee: from the round-start distance, P1 does down, down-forward,
## forward + HP against an idle KROS. Prints positions and hit events, checks that
## rollback (save, re-simulate) gives the same result, and saves a screenshot every
## 4 frames when not headless. Run:
## godot --path . --script res://tests/fk_shot.gd -- --out=DIR [--block]

var sim: MatchSim
var world: Node2D
var out := ""
var block := false
var start_at := -1
var pending := ""
var script_inputs := [Inp.DOWN, Inp.DOWN, Inp.DOWN | Inp.RIGHT, Inp.DOWN | Inp.RIGHT, Inp.RIGHT, Inp.RIGHT | Inp.HP]
var log_lines: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a == "--block":
			block = true
	sim = MatchSim.new("ced", "kros")
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


func _input_p1() -> int:
	if sim.phase != MatchSim.FIGHT:
		return 0
	if start_at < 0:
		start_at = sim.frame
	var k := sim.frame - start_at
	return script_inputs[k] if k < script_inputs.size() else 0


func _process(_d: float) -> bool:
	if pending != "":
		root.get_texture().get_image().save_png(pending)
		pending = ""
	var i1 := Inp.RIGHT if block else 0
	sim.step(_input_p1(), i1)
	world.position = Vector2(-sim.cam_x, 0)
	var a := sim.f[0]
	for e in sim.events:
		if e["t"] in ["hit", "block", "land", "swing"]:
			print("  frame %d event %s" % [sim.frame - start_at, e])
	if start_at >= 0:
		var k := sim.frame - start_at
		if a.state == Fighter.ATTACK and k % 4 == 0:
			print("k%3d sf%3d x %6.1f y %5.1f hit_idx %d  opp x %6.1f state %d hp %d" % [
				k, a.sf, a.x / 100.0, a.y / 100.0, a.hit_idx, sim.f[1].x / 100.0, sim.f[1].state, sim.f[1].health])
			if out != "":
				pending = "%s/fk_%03d.png" % [out, k]
		if k == 30:
			_check_rollback()
		if k > 110:
			print("done: opp health %d, ced state %d" % [sim.f[1].health, a.state])
			return true
	return false


## Saves mid-move, runs ahead, rewinds and runs again: both runs must match exactly.
func _check_rollback() -> void:
	var saved := sim.save_state()
	var first: Array = []
	for i in 40:
		sim.step(0, Inp.RIGHT if block else 0)
		first.append(sim.save_state())
	sim.load_state(saved)
	for i in 40:
		sim.step(0, Inp.RIGHT if block else 0)
		if str(sim.save_state()) != str(first[i]):
			print("ROLLBACK MISMATCH at +%d" % i)
			return
	sim.load_state(saved)
	print("rollback ok")
