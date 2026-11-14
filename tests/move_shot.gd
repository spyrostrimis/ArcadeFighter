extends SceneTree
## In-game check of one normal move: CHAR (P1, left) walks up to an idle VS and does MOVE.
## Saves a screenshot every 2 frames of the move and a contact sheet (every 4th frame,
## zoomed on the fighters). With --boxes, hurt boxes (blue) and the active hit box (red)
## are drawn over the sprites, to line the frame data up with the art.
## Run (not headless):
## godot --path . --script res://tests/move_shot.gd -- --char=ced --move=st_hk --out=DIR [--vs=kros] [--boxes] [--skin=ID]
## MOVE: st_/cr_/j_ + lp/mp/hp/lk/mk/hk. --skin = sprite set for CHAR (e.g. kros_nocape).

var sim: MatchSim
var world: Node2D
var out := "user://"
var cid := "ced"
var vs := "kros"
var move := "st_hp"
var skin := ""
var boxes := false
var reach := 50
var t0 := -1        # frame the move's button is pressed
var pending := ""   # screenshot to save once the last stepped frame has been drawn
var pending_k := 0
var sheet: Array[Image] = []


class Boxes extends Node2D:
	var sim: MatchSim

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for fi in sim.f:
			for r in fi.hurt_rects():
				_rect(r, Color(0.3, 0.6, 1.0))
			if fi.state == Fighter.ATTACK and fi.move_active():
				_rect(fi.hit_rect(), Color(1.0, 0.2, 0.2))

	func _rect(r: Rect2i, c: Color) -> void:
		var top := FighterView.FLOOR_Y - (r.position.y + r.size.y)
		var rr := Rect2(r.position.x, top, r.size.x, r.size.y)
		draw_rect(rr, Color(c, 0.25), true)
		draw_rect(rr, c, false, 1.0)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--char="): cid = a.substr(7)
		if a.begins_with("--vs="): vs = a.substr(5)
		if a.begins_with("--move="): move = a.substr(7)
		if a.begins_with("--skin="): skin = a.substr(7)
		if a == "--boxes": boxes = true
	sim = MatchSim.new(cid, vs)
	var m: Dictionary = CharData.get_data(cid)["moves"][move]
	reach = int(m["box"][0]) + int(m["box"][2]) + 6
	world = Node2D.new()
	root.add_child(world)
	var bg := Sprite2D.new()
	bg.texture = load("res://assets/stages/bedroom.png")
	bg.centered = false
	world.add_child(bg)
	for i in 2:
		var v := FighterView.new()
		v.setup(sim, i, false, skin if i == 0 else "")
		world.add_child(v)
	if boxes:
		var b := Boxes.new()
		b.sim = sim
		world.add_child(b)


func _button() -> int:
	var i := Inp.BUTTON_NAMES.find(move.substr(move.find("_") + 1))
	return Inp.BUTTONS[i]


func _input_p1() -> int:
	if sim.phase != MatchSim.FIGHT:
		return 0
	var a := sim.f[0]
	if t0 < 0:
		var gap := (sim.f[1].x - a.x) / 100
		if move.begins_with("j_"):
			if a.state == Fighter.IDLE or a.state == Fighter.WALK:
				return Inp.UP | Inp.RIGHT if gap < reach + 90 else Inp.RIGHT
			if a.airborne() and a.vy < 0:   # coming down
				t0 = sim.frame
				return _button()
			return 0
		if gap > reach:
			return Inp.RIGHT
		if move.begins_with("cr_") and a.state != Fighter.CROUCH:
			return Inp.DOWN
		t0 = sim.frame
		return _button() | (Inp.DOWN if move.begins_with("cr_") else 0)
	return Inp.DOWN if move.begins_with("cr_") else 0


func _process(_d: float) -> bool:
	if pending != "":
		var img := root.get_texture().get_image()
		img.save_png(pending)
		if pending_k % 4 == 0:
			img.convert(Image.FORMAT_RGBA8)
			sheet.append(img)
		pending = ""
	sim.step(_input_p1(), 0)
	world.position = Vector2(-sim.cam_x, 0)
	if t0 >= 0:
		var k := sim.frame - t0
		var done := sim.f[0].state != Fighter.ATTACK and k > 4
		if done or k > 90:
			_save_sheet()
			return true
		if k % 2 == 0:
			pending = "%s/%s_%s_%03d.png" % [out, cid, move, k]
			pending_k = k
	return false


## Every 4th frame side by side, cropped around both fighters, 2x.
func _save_sheet() -> void:
	if sheet.is_empty():
		return
	var cx := int((sim.f[0].x + sim.f[1].x) / 200.0 - sim.cam_x)
	var cw := 200
	var x0 := clampi(cx - cw / 2, 0, 384 - cw)
	var cols := mini(sheet.size(), 6)
	var rows := ceili(sheet.size() / float(cols))
	var s := Image.create(cw * cols, 150 * rows, false, Image.FORMAT_RGBA8)
	for i in sheet.size():
		s.blit_rect(sheet[i], Rect2i(x0, 60, cw, 150), Vector2i((i % cols) * cw, (i / cols) * 150))
	s.resize(s.get_width() * 2, s.get_height() * 2, Image.INTERPOLATE_NEAREST)
	s.save_png("%s/%s_%s_sheet.png" % [out, cid, move])
	print("saved %d frames, sheet %s/%s_%s_sheet.png" % [sheet.size() * 2, out, cid, move])
