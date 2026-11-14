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
## Bison-style cape: the fighter starts each round in `cape_sprites` and throws the cape
## off during the round intro, then fights in `sprites`. Purely visual, read from the sim's
## phase/frame counter, so it replays the same under rollback.
var cape_sprites: SpriteSet = null
const CAPED := {"kros": "kros_nocape"}   # fighter id -> its sprite set once the cape is off
const TOSS_AT := 40     # intro frame the cape comes off ("ROUND n" is on screen 8-70)
const CAPE_PIVOT := Vector2(0, -60)


## `skin` picks another sprite set for the same fighter (e.g. "kros_nocape": KROS without
## his cape); "" = the fighter's own (assets/fighters/<cid>).
func setup(p_sim: MatchSim, p_slot: int, alt: bool, skin := "") -> void:
	sim = p_sim
	slot = p_slot
	alt_palette = alt
	pal = Puppet.palette(sim.f[slot].cid, alt)
	var cid := sim.f[slot].cid
	sprites = SpriteSet.load_for(skin if skin != "" else cid)
	if skin == "" and CAPED.has(cid):
		var off := SpriteSet.load_for(CAPED[cid])
		if off != null and sprites != null and sprites.has("cape_toss"):
			cape_sprites = sprites
			sprites = off


## The sprite set to draw now: still wearing the cape during the round intro before the toss.
func _sprites_now() -> SpriteSet:
	if cape_sprites != null and sim.phase == MatchSim.INTRO and sim.pf < TOSS_AT:
		return cape_sprites
	return sprites


## The thrown cape: flies up and back, flapping and turning, until it leaves the screen.
func _draw_flying_cape(base: Vector2, facing: int) -> void:
	if cape_sprites == null or sim.phase != MatchSim.INTRO or sim.pf < TOSS_AT:
		return
	var t := float(sim.pf - TOSS_AT)
	var off := Vector2(-1.4 * t - 0.01 * t * t, -3.2 * t - 0.03 * t * t)
	var flap := 1.0 - 0.35 * absf(sin(t * 0.16))
	var xf := Transform2D(0.0, Vector2(facing, 1), 0.0, base)
	xf *= Transform2D(-0.025 * t, Vector2(flap, 1), 0.0, off + CAPE_PIVOT)
	xf *= Transform2D(0.0, -CAPE_PIVOT)
	draw_set_transform_matrix(xf)
	cape_sprites.draw_frame(self, "cape_toss", 0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	return want if _sprites_now().has(want) else ""


## Looping animations run on the clock; moves are synced to their frame data.
func _sprite_index(fi: Fighter, anim: String) -> int:
	var n := _sprites_now().frame_count(anim)
	if fi.state == Fighter.ATTACK:
		return clampi(fi.sf * n / fi.move_length(), 0, n - 1)
	var clock := sim.frame + slot * 23
	return int(clock * _sprites_now().fps / 60.0) % n


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
	if not alt_palette:
		_draw_flying_cape(base, fi.facing)
	draw_set_transform(base, 0.0, Vector2(fi.facing, 1))
	z_index = 1 if fi.state == Fighter.ATTACK else 0
	if sprites != null and not alt_palette:
		var anim := _sprite_anim(fi)
		if anim != "":
			_sprites_now().draw_frame(self, anim, _sprite_index(fi, anim))
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
