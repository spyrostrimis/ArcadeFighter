extends SceneTree
## Visual check of one move: CED walks up to an idle KROS and does st_hp; saves a
## screenshot every 2 frames of the move. Run (not headless):
## godot --path . --script res://tests/hp_shot.gd -- --out=DIR

var sim: MatchSim
var world: Node2D
var out := "user://"
var hp_at := -1
var pending := ""   # screenshot to save once the last stepped frame has been drawn


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
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


func _process(_d: float) -> bool:
	if pending != "":
		root.get_texture().get_image().save_png(pending)
		pending = ""
	var i0 := 0
	if sim.phase == MatchSim.FIGHT and hp_at < 0:
		if (sim.f[1].x - sim.f[0].x) / 100 > 58:
			i0 = Inp.RIGHT
		else:
			i0 = Inp.HP
			hp_at = sim.frame
	sim.step(i0, 0)
	world.position = Vector2(-sim.cam_x, 0)
	if hp_at >= 0:
		var k := sim.frame - hp_at
		if k > 40:
			return true
		if k % 2 == 0:
			pending = "%s/hp_%02d.png" % [out, k]
	return false
