class_name Poses
## Placeholder animation: builds a skeleton pose from the fighter's sim state.
## Pose keys: px,py (pelvis), lean, head (deg), fh/bh (front/back hand target),
## ff/bf (front/back foot target), rot (whole-body deg, + = falling backward),
## oy (y offset after rotation), open (1 = open claw hands).
## Coordinates are pixels, x forward, y up from the feet.

const KEYS_F := ["px", "py", "lean", "head", "rot", "oy", "open"]
const KEYS_V := ["fh", "bh", "ff", "bf"]


static func lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var o := {}
	for k in KEYS_F:
		o[k] = lerpf(a.get(k, 0.0), b.get(k, 0.0), t)
	for k in KEYS_V:
		o[k] = (a[k] as Vector2).lerp(b[k], t)
	return o


static func with(base: Dictionary, over: Dictionary) -> Dictionary:
	var o := base.duplicate()
	for k in over:
		o[k] = over[k]
	return o


static func idle(cid: String, t: float) -> Dictionary:
	var b := sin(t * 0.11) * 1.0
	if cid == "kros":
		return {"px": 0.0, "py": 52.0 + b, "lean": 2.0, "head": -6.0, "rot": 0.0, "oy": 0.0, "open": 1.0,
			"fh": Vector2(30, 82 + b), "bh": Vector2(20, 70 + b * 1.5),
			"ff": Vector2(20, 0), "bf": Vector2(-24, 0)}
	return {"px": 0.0, "py": 45.0 + b, "lean": 9.0, "head": -4.0, "rot": 0.0, "oy": 0.0, "open": 0.0,
		"fh": Vector2(25, 80 + b), "bh": Vector2(14, 71 + b * 1.5),
		"ff": Vector2(21, 0), "bf": Vector2(-23, 0)}


static func crouch(cid: String, t: float) -> Dictionary:
	var b := sin(t * 0.11) * 0.6
	if cid == "kros":
		return with(idle(cid, t), {"py": 31.0 + b, "lean": 12.0, "fh": Vector2(30, 56 + b), "bh": Vector2(20, 47 + b),
			"ff": Vector2(20, 0), "bf": Vector2(-22, 0)})
	return with(idle(cid, t), {"py": 27.0 + b, "lean": 18.0, "fh": Vector2(26, 54 + b), "bh": Vector2(15, 47 + b),
		"ff": Vector2(19, 0), "bf": Vector2(-20, 0)})


static func jump(cid: String, t: float) -> Dictionary:
	var k := 1.06 if cid == "kros" else 1.0
	return with(idle(cid, t), {"py": 50.0 * k, "lean": 10.0, "fh": Vector2(22, 84) * k, "bh": Vector2(8, 74) * k,
		"ff": Vector2(14, 22) * k, "bf": Vector2(-8, 16) * k})


static func walk(cid: String, t: float, dir: float) -> Dictionary:
	var p := idle(cid, t)
	var ph := t * 0.22 * dir
	var s := sin(ph)
	var c := cos(ph)
	p["ff"] = (p["ff"] as Vector2) + Vector2(7.0 * s, maxf(0.0, 5.0 * c))
	p["bf"] = (p["bf"] as Vector2) + Vector2(-7.0 * s, maxf(0.0, -5.0 * c))
	p["py"] = float(p["py"]) - absf(s) * 1.5
	p["fh"] = (p["fh"] as Vector2) + Vector2(-1.5 * s, 0)
	p["bh"] = (p["bh"] as Vector2) + Vector2(1.5 * s, 0)
	return p


static func block(cid: String, t: float, crouching: bool) -> Dictionary:
	if crouching:
		return with(crouch(cid, t), {"lean": 4.0, "head": 4.0, "fh": Vector2(19, 60), "bh": Vector2(17, 52), "open": 0.0})
	return with(idle(cid, t), {"lean": -4.0, "head": 6.0, "fh": Vector2(19, 88), "bh": Vector2(17, 78), "open": 0.0})


static func hurt(cid: String, t: float, crouching: bool, amount: float) -> Dictionary:
	var base := crouch(cid, t) if crouching else idle(cid, t)
	var h := with(base, {"lean": -20.0 if not crouching else -14.0, "head": -18.0, "px": -3.0,
		"fh": Vector2(6, (66 if not crouching else 44)), "bh": Vector2(-8, (74 if not crouching else 50))})
	return lerp_pose(base, h, amount)


static func fall(cid: String, t: float, rot: float) -> Dictionary:
	return with(idle(cid, t), {"py": 50.0, "lean": -10.0, "head": -20.0, "rot": rot, "open": 1.0,
		"fh": Vector2(14, 96), "bh": Vector2(-10, 92), "ff": Vector2(18, 12), "bf": Vector2(-4, 20)})


static func lying(cid: String, t: float) -> Dictionary:
	return with(idle(cid, t), {"py": 50.0, "lean": 0.0, "head": 10.0, "rot": 90.0, "oy": -42.0, "open": 1.0,
		"fh": Vector2(14, 60), "bh": Vector2(-12, 66), "ff": Vector2(10, 4), "bf": Vector2(-6, 2)})


static func win(cid: String, t: float) -> Dictionary:
	var b := absf(sin(t * 0.12)) * 2.0
	if cid == "kros":
		return with(idle(cid, t), {"py": 54.0, "lean": -8.0, "head": 20.0 + b * 3.0, "open": 1.0,
			"fh": Vector2(36, 98 + b), "bh": Vector2(-26, 96 + b), "ff": Vector2(14, 0), "bf": Vector2(-16, 0)})
	return with(idle(cid, t), {"py": 49.0 + b, "lean": 0.0, "head": 12.0, "open": 0.0,
		"fh": Vector2(8, 120 + b), "bh": Vector2(10, 52 + b), "ff": Vector2(10, 0), "bf": Vector2(-12, 0)})


static func lose(cid: String, t: float) -> Dictionary:
	return with(idle(cid, t), {"py": 40.0, "lean": 32.0, "head": -28.0, "open": 0.0,
		"fh": Vector2(18, 38), "bh": Vector2(8, 36), "ff": Vector2(14, 0), "bf": Vector2(-16, 0)})


# ---------------------------------------------------------------- attacks

## [windup overrides, hit overrides] per move (Ced proportions; Kros is scaled).
static func _attack_keys(mv: String) -> Array:
	match mv:
		"st_lp": return [{"fh": Vector2(18, 78)}, {"fh": Vector2(42, 81), "lean": 12.0, "px": 2.0}]
		"st_mp": return [{"bh": Vector2(6, 74), "lean": 4.0}, {"bh": Vector2(47, 79), "lean": 20.0, "px": 5.0, "fh": Vector2(14, 72)}]
		"st_hp": return [{"bh": Vector2(-4, 72), "lean": -4.0, "px": -2.0},
			{"bh": Vector2(50, 74), "lean": 26.0, "px": 8.0, "ff": Vector2(30, 0), "fh": Vector2(10, 70)}]
		"st_lk": return [{"ff": Vector2(14, 10), "py": 48.0}, {"ff": Vector2(42, 24), "lean": -6.0, "py": 50.0, "px": -2.0}]
		"st_mk": return [{"ff": Vector2(10, 26), "lean": -4.0}, {"ff": Vector2(50, 52), "lean": -16.0, "py": 50.0, "px": -4.0, "bf": Vector2(-18, 0)}]
		"st_hk": return [{"ff": Vector2(4, 32), "lean": -8.0, "py": 50.0},
			{"ff": Vector2(52, 78), "lean": -30.0, "py": 52.0, "px": -6.0, "fh": Vector2(8, 84), "bh": Vector2(-6, 80), "bf": Vector2(-16, 0)}]
		"cr_lp": return [{"fh": Vector2(18, 52)}, {"fh": Vector2(38, 50), "lean": 22.0}]
		"cr_mp": return [{"bh": Vector2(8, 46)}, {"bh": Vector2(43, 48), "lean": 26.0, "px": 3.0}]
		"cr_hp": return [{"bh": Vector2(6, 36), "py": 24.0, "lean": 22.0},
			{"bh": Vector2(20, 104), "py": 46.0, "lean": -4.0, "px": 4.0, "ff": Vector2(18, 0), "head": 10.0}]
		"cr_lk": return [{"ff": Vector2(16, 6)}, {"ff": Vector2(41, 5), "lean": 6.0}]
		"cr_mk": return [{"ff": Vector2(14, 8)}, {"ff": Vector2(51, 6), "lean": -6.0, "px": -2.0}]
		"cr_hk": return [{"ff": Vector2(10, 8), "py": 22.0, "lean": 32.0},
			{"ff": Vector2(60, 4), "py": 20.0, "lean": 42.0, "px": -4.0, "bf": Vector2(-14, 0), "fh": Vector2(28, 10), "bh": Vector2(12, 16)}]
		"j_lp": return [{"fh": Vector2(18, 72)}, {"fh": Vector2(34, 46), "lean": 18.0}]
		"j_mp": return [{"bh": Vector2(6, 78)}, {"bh": Vector2(38, 40), "lean": 24.0}]
		"j_hp": return [{"bh": Vector2(0, 88), "lean": 0.0}, {"bh": Vector2(42, 32), "fh": Vector2(20, 58), "lean": 32.0}]
		"j_lk": return [{"ff": Vector2(18, 16)}, {"ff": Vector2(37, 16)}]
		"j_mk": return [{"ff": Vector2(14, 14)}, {"ff": Vector2(43, 12), "lean": -8.0}]
		"j_hk": return [{"ff": Vector2(10, 20), "lean": -6.0}, {"ff": Vector2(49, 10), "bf": Vector2(-14, 24), "lean": -14.0}]
	return [{}, {}]


static func _scaled(over: Dictionary, sx: float, sy: float) -> Dictionary:
	var o := {}
	for k in over:
		var v = over[k]
		o[k] = Vector2(v.x * sx, v.y * sy) if v is Vector2 else v
	return o


static func attack(cid: String, t: float, mv: String, f: int, m: Dictionary) -> Dictionary:
	var base: Dictionary
	if mv.begins_with("cr_"):
		base = crouch(cid, t)
	elif mv.begins_with("j_"):
		base = jump(cid, t)
	else:
		base = idle(cid, t)
	var keys := _attack_keys(mv)
	var wo: Dictionary = keys[0]
	var ho: Dictionary = keys[1]
	if cid == "kros":
		wo = _scaled(wo, 1.12, 1.05)
		ho = _scaled(ho, 1.12, 1.05)
		if mv == "st_mp" or mv == "j_mp":
			wo["bh"] = Vector2(14, 104)  # overhead claw slash
		ho["open"] = 1.0
	var wind := with(base, wo)
	var hit := with(base, ho)
	if mv.ends_with("p") and cid != "kros":
		hit["open"] = 0.0
	var s: int = m["startup"]
	var a: int = m["active"]
	var r: int = m["recovery"]
	var w := maxi(1, s - 2)
	if f < w:
		return lerp_pose(base, wind, float(f) / w)
	if f < s:
		return lerp_pose(wind, hit, float(f - w + 1) / float(s - w + 1))
	if f < s + a or r == 0:
		return hit
	var u := float(f - s - a) / r
	return lerp_pose(hit, base, u * u * (3.0 - 2.0 * u))


## Pose for a live fighter.
static func for_fighter(fi: Fighter, t: float) -> Dictionary:
	var cid := fi.cid
	match fi.state:
		Fighter.IDLE:
			if fi.guarding:
				return block(cid, t, false)
			return idle(cid, t)
		Fighter.WALK:
			if fi.guarding:
				return block(cid, t, false)
			return walk(cid, float(fi.sf), signf(fi.vx * fi.facing))
		Fighter.CROUCH:
			if fi.guarding:
				return block(cid, t, true)
			return crouch(cid, t)
		Fighter.PREJUMP:
			return lerp_pose(idle(cid, t), crouch(cid, t), 0.6)
		Fighter.AIR:
			var j := jump(cid, t)
			if fi.jump_dir != 0:
				# little tuck at the apex
				j["lean"] = 10.0 + clampf(-fi.vy / 30.0, -10.0, 10.0)
			return j
		Fighter.LAND:
			return lerp_pose(crouch(cid, t), idle(cid, t), clampf(float(fi.sf) / maxf(1.0, fi.land_len), 0.0, 1.0) * 0.5)
		Fighter.ATTACK:
			return attack(cid, t, fi.move, fi.sf, fi.cur_move())
		Fighter.HITSTUN:
			var amt := clampf(fi.stun / 6.0, 0.0, 1.0)
			return hurt(cid, t, fi.crouched, amt)
		Fighter.BLOCKSTUN:
			return block(cid, t, fi.crouched)
		Fighter.FALL, Fighter.KO:
			if fi.airborne():
				var r := clampf(30.0 + (600.0 - fi.vy) / 14.0, 20.0, 95.0)
				return fall(cid, t, r)
			return lying(cid, t)
		Fighter.LIE:
			return lying(cid, t)
		Fighter.GETUP:
			var u := clampf(float(fi.sf) / Fighter.GETUP_FRAMES, 0.0, 1.0)
			if u < 0.5:
				return lerp_pose(lying(cid, t), crouch(cid, t), u * 2.0)
			return lerp_pose(crouch(cid, t), idle(cid, t), (u - 0.5) * 2.0)
		Fighter.WIN:
			return lerp_pose(idle(cid, t), win(cid, t), clampf(fi.sf / 12.0, 0.0, 1.0))
		Fighter.LOSE:
			return lerp_pose(idle(cid, t), lose(cid, t), clampf(fi.sf / 20.0, 0.0, 1.0))
	return idle(cid, t)
