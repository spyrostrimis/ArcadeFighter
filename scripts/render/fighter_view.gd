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
## Bison-style cape: the fighter starts each round in `cape_sprites`; during the round intro
## the cape blinks and fades away in place, then he fights in `sprites`. Purely visual, read
## from the sim's phase/frame counter, so it replays the same under rollback.
var cape_sprites: SpriteSet = null
const CAPED := {"kros": "kros_nocape"}   # fighter id -> its sprite set once the cape is off
const FADE_AT := 24     # intro frame the cape starts blinking ("ROUND n" is on screen 8-70)
const FADE_LEN := 44    # frames until it is gone
## Placeholder puppet size -> sprite size (CED 113 -> 92 px, KROS 110 -> 97 px).
const PUPPET_SCALE := {"ced": 92.0 / 113.0, "kros": 97.0 / 110.0, "murfurrie": 94.0 / 113.0,
		"shorty": 47.0 / 95.6}   # half the others' fighting height (his puppet stands 95.6 tall)


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
		if off != null and sprites != null and sprites.has("cape"):
			cape_sprites = sprites
			sprites = off


## Frames into the cape fade (-1 = not fading: wearing it before, gone after).
func _cape_t() -> int:
	if cape_sprites == null or sim.phase != MatchSim.INTRO:
		return -1
	var k := sim.intro_pf() - FADE_AT
	return k if k < FADE_LEN else -1


## The sprite set to draw now: the caped one during the round intro until the cape fades.
func _sprites_now() -> SpriteSet:
	if cape_sprites != null and sim.phase == MatchSim.INTRO and sim.intro_pf() < FADE_AT:
		return cape_sprites
	return sprites


## The fading cape, drawn behind the cape-less body: blinks faster and fainter until it's gone.
func _draw_fading_cape(k: int) -> void:
	var period := maxi(1, 6 - k / 8)          # 6 frames on/off at first, down to every frame
	if (k / period) % 2 == 1:
		return
	var a := 1.0 - float(k) / FADE_LEN
	cape_sprites.draw_frame(self, "cape", 0, Color(1, 1, 1, 0.35 + 0.65 * a))


## Which sprite animation shows this state ("" = none yet, use the placeholder puppet).
func _sprite_anim(fi: Fighter) -> String:
	if sim.in_showcase() and fi.data.has("showcase") and _sprites_now().has("intro"):
		return "intro"   # posing with the ladies
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
		var m := fi.cur_move()
		if m.has("path"):   # root-motion moves were animated frame by frame along their path
			return clampi(fi.sf * n / fi.move_length(), 0, n - 1)
		return _sprites_now().attack_index(anim, fi.sf, int(m["startup"]), int(m["active"]),
				fi.move_length())
	if _cape_t() >= 0:
		return 0   # hold still while the cape fades: it doesn't breathe with the body
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
	draw_set_transform(base, 0.0, Vector2(fi.facing, 1))
	z_index = 1 if fi.state == Fighter.ATTACK else 0
	if sprites != null and not alt_palette:
		var anim := _sprite_anim(fi)
		if anim != "":
			if _cape_t() >= 0:
				_draw_fading_cape(_cape_t())
			_sprites_now().draw_frame(self, anim, _sprite_index(fi, anim))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
	var pose := Poses.for_fighter(fi, t)
	if sim.in_showcase() and fi.data.has("showcase"):
		pose = Poses.showcase(fi.cid, t)
	var sway := sin(t * 0.07) * 2.0 + clampf(fi.vx * fi.facing / 60.0, -4.0, 6.0)
	if fi.state == Fighter.WIN:
		sway += 6.0 + sin(t * 0.15) * 3.0
	# the puppet was built for the old, taller sprites: shrink it to the sprites' height
	var k: float = PUPPET_SCALE.get(fi.cid, 1.0)
	draw_set_transform(base, 0.0, Vector2(fi.facing * k, k))
	Puppet.draw(self, fi.cid, pal, pose, sway)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	z_index = 1 if fi.state == Fighter.ATTACK else 0


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
