class_name FighterView
extends Node2D
## Draws one fighter from the sim each frame.

const FLOOR_Y := 200

var sim: MatchSim
var slot := 0
var pal: Dictionary
var t := 0.0


var sprites: SpriteSet
var alt_palette := false


func setup(p_sim: MatchSim, p_slot: int, alt: bool) -> void:
	sim = p_sim
	slot = p_slot
	alt_palette = alt
	pal = Puppet.palette(sim.f[slot].cid, alt)
	sprites = SpriteSet.load_for(sim.f[slot].cid)


## Which sprite animation shows this state ("" = none yet, use the placeholder puppet).
func _sprite_anim(fi: Fighter) -> String:
	var want := ""
	match fi.state:
		Fighter.IDLE:
			want = "block" if fi.guarding else "idle"
		Fighter.WALK:
			if fi.guarding:
				want = "block"
			else:
				want = "walk_f" if fi.vx * fi.facing > 0 else "walk_b"
		Fighter.CROUCH:
			want = "cr_block" if fi.guarding else "crouch"
		Fighter.PREJUMP, Fighter.AIR:
			want = "jump"
		Fighter.LAND:
			want = "idle"
		Fighter.ATTACK:
			want = fi.move
		Fighter.HITSTUN:
			want = "hit_low" if fi.crouched else "hit_high"
		Fighter.BLOCKSTUN:
			want = "cr_block" if fi.crouched else "block"
		Fighter.FALL, Fighter.LIE:
			want = "knockdown"
		Fighter.GETUP:
			want = "getup"
		Fighter.KO:
			want = "ko"
		Fighter.WIN:
			want = "win"
		Fighter.LOSE:
			want = "lose"
	return want if sprites.has(want) else ""


## Looping animations run on the clock; moves are synced to their frame data.
func _sprite_index(fi: Fighter, anim: String) -> int:
	var n := sprites.frame_count(anim)
	if fi.state == Fighter.ATTACK:
		var m := fi.cur_move()
		var total: int = int(m["startup"]) + int(m["active"]) + maxi(1, int(m["recovery"]))
		return clampi(fi.sf * n / total, 0, n - 1)
	var clock := sim.frame + slot * 23
	return int(clock * sprites.fps / 60.0) % n


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var fi: Fighter = sim.f[slot]
	t = float(sim.frame + slot * 37)
	var base := Vector2(round(fi.x / 100.0), FLOOR_Y - round(fi.y / 100.0))
	# shake while frozen in hitstop after being hit
	if sim.hitstop > 0 and (fi.state == Fighter.HITSTUN or fi.state == Fighter.BLOCKSTUN or fi.state == Fighter.FALL or fi.state == Fighter.KO):
		base.x += 1 if (sim.hitstop % 2) == 0 else -1
	# shadow on the floor
	var h := fi.y / 100.0
	var sw := maxf(10.0, 26.0 - h * 0.12)
	_ellipse(Vector2(base.x, FLOOR_Y - 1), sw, 3.5, Color(0, 0, 0, 0.35))
	draw_set_transform(base, 0.0, Vector2(fi.facing, 1))
	z_index = 1 if fi.state == Fighter.ATTACK else 0
	if sprites != null and not alt_palette:
		var anim := _sprite_anim(fi)
		if anim != "":
			sprites.draw_frame(self, anim, _sprite_index(fi, anim))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
	var pose := Poses.for_fighter(fi, t)
	var sway := sin(t * 0.07) * 2.0 + clampf(fi.vx * fi.facing / 60.0, -4.0, 6.0)
	if fi.state == Fighter.WIN:
		sway += 6.0 + sin(t * 0.15) * 3.0
	Puppet.draw(self, fi.cid, pal, pose, sway)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	z_index = 1 if fi.state == Fighter.ATTACK else 0


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
