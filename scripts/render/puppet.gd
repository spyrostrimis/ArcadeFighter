class_name Puppet
## Placeholder character renderer: draws an outlined, shaded "paper doll" from a
## pose, at native 384x216 resolution so it comes out as chunky pixel art.
## Real sprite sheets can replace this later without touching the sim.

const OUTLINE := Color("140a08")

const SKEL := {
	"ced": {"torso": 30.0, "neck": 4.0, "head_r": 8.0, "ua": 16.0, "fa": 15.0, "thigh": 26.0, "shin": 25.0,
		"ua_w": 8.0, "fa_w": 7.0, "thigh_w": 11.0, "shin_w": 10.0, "waist": 9.0, "chest": 11.5, "fist": 4.0},
	"kros": {"torso": 32.0, "neck": 4.0, "head_r": 8.0, "ua": 17.0, "fa": 16.0, "thigh": 28.0, "shin": 27.0,
		"ua_w": 7.0, "fa_w": 6.0, "thigh_w": 9.0, "shin_w": 8.0, "waist": 8.0, "chest": 11.0, "fist": 3.5},
	# Broad-shouldered, suit jacket squares off the chest.
	"murfurrie": {"torso": 31.0, "neck": 4.0, "head_r": 8.0, "ua": 16.0, "fa": 15.0, "thigh": 26.0, "shin": 26.0,
		"ua_w": 8.0, "fa_w": 7.0, "thigh_w": 10.0, "shin_w": 9.0, "waist": 9.5, "chest": 12.5, "fist": 4.0},
}


static func palette(cid: String, alt := false) -> Dictionary:
	if cid == "kros":
		var p := {
			"skin": Color("d9b8a6"), "hair": Color("8c8b94"), "hair_hi": Color("c9c8d2"), "hair_dk": Color("4e4d58"),
			"top": Color("2a2030"), "top_hi": Color("4c3c52"), "pants": Color("221a24"), "pants_hi": Color("3e3244"),
			"boot": Color("17131b"), "boot_hi": Color("5a5266"), "sole": Color("0a080c"),
			"cape": Color("5c0f18"), "cape_in": Color("a3192a"), "cape_hi": Color("cf3446"), "gold": Color("e0ae3a"),
			"eye": Color("8a1010"),
		}
		if alt:
			p["cape"] = Color("1e2a5c")
			p["cape_in"] = Color("3550a8")
			p["cape_hi"] = Color("5f7fd8")
			p["top"] = Color("e8e2dc")
			p["top_hi"] = Color("ffffff")
			p["hair"] = Color("d8d0c0")
		return p
	if cid == "murfurrie":
		# Light blue suit (jacket + trousers) over a dark navy shirt, black dress shoes.
		var m := {
			"skin": Color("e0ad8a"), "hair": Color("231a17"), "hair_hi": Color("4a3a32"), "hair_dk": Color("0e0a09"),
			"top": Color("8db6dc"), "top_hi": Color("c4def4"), "pants": Color("86afd6"), "pants_hi": Color("b6d2ee"),
			"shirt": Color("1b2744"), "shirt_hi": Color("33456e"), "button": Color("d8cfbe"),
			"boot": Color("231b19"), "boot_hi": Color("5a4a44"), "sole": Color("0c0808"),
			"beard": Color("3a2a24"), "eye": Color("2a140a"),
		}
		if alt:
			m["top"] = Color("54585f")
			m["top_hi"] = Color("80858e")
			m["pants"] = Color("4c5057")
			m["pants_hi"] = Color("767b84")
			m["shirt"] = Color("5a1620")
			m["shirt_hi"] = Color("84283a")
		return m
	var c := {
		"skin": Color("e7a77a"), "hair": Color("6b3b1e"), "hair_hi": Color("9a5c30"), "hair_dk": Color("40220f"),
		"top": Color("7b5236"), "top_hi": Color("a5754f"), "pants": Color("d9c9a8"), "pants_hi": Color("f3e8cc"),
		"boot": Color("8b5129"), "boot_hi": Color("bf7a40"), "sole": Color("3a2010"),
		"lace": Color("f2f0ea"), "eye": Color("1a1010"),
	}
	if alt:
		c["top"] = Color("2f5f86")
		c["top_hi"] = Color("4f8cbc")
		c["pants"] = Color("5a5a64")
		c["pants_hi"] = Color("80808c")
		c["hair"] = Color("1e1a18")
		c["hair_hi"] = Color("4a403a")
	return c


static func _shade(c: Color, k := 0.72) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func _dir(deg: float) -> Vector2:
	# y-up "up" vector rotated forward by deg
	var r := deg_to_rad(deg)
	return Vector2(sin(r), cos(r))


static func _ik(a: Vector2, t: Vector2, l1: float, l2: float, bend: float) -> Array:
	var d := t - a
	var dist := clampf(d.length(), 0.01, l1 + l2 - 0.01)
	var dn := d.normalized() if d.length() > 0.001 else Vector2(0, -1)
	var end := a + dn * dist
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var ang := acos(cos_a)
	var joint := a + Vector2.from_angle(dn.angle() + ang * bend) * l1
	return [joint, end]


## Computes all joint positions (y-up local space).
static func skeleton(cid: String, pose: Dictionary) -> Dictionary:
	var k: Dictionary = SKEL[cid]
	var pelvis := Vector2(pose["px"], pose["py"])
	var up := _dir(pose["lean"])
	var perp := Vector2(up.y, -up.x)
	var neck := pelvis + up * float(k["torso"])
	var hup := _dir(float(pose["lean"]) + float(pose["head"]))
	var head := neck + hup * (float(k["neck"]) + float(k["head_r"]))
	var sh_f := neck + perp * 3.0 - up * 3.0
	var sh_b := neck - perp * 4.0 - up * 3.0
	var hip_f := pelvis + perp * 4.0
	var hip_b := pelvis - perp * 4.0
	var af := _ik(sh_f, pose["fh"], k["ua"], k["fa"], -1.0)
	var ab := _ik(sh_b, pose["bh"], k["ua"], k["fa"], -1.0)
	var lf := _ik(hip_f, pose["ff"], k["thigh"], k["shin"], 1.0)
	var lb := _ik(hip_b, pose["bf"], k["thigh"], k["shin"], 1.0)
	var s := {
		"pelvis": pelvis, "neck": neck, "head": head, "up": up, "hup": hup,
		"sh_f": sh_f, "el_f": af[0], "ha_f": af[1], "sh_b": sh_b, "el_b": ab[0], "ha_b": ab[1],
		"hip_f": hip_f, "kn_f": lf[0], "ft_f": lf[1], "hip_b": hip_b, "kn_b": lb[0], "ft_b": lb[1],
	}
	var rot := deg_to_rad(float(pose.get("rot", 0.0)))
	var oy := float(pose.get("oy", 0.0))
	if rot != 0.0 or oy != 0.0:
		for key in s:
			var v: Vector2 = s[key]
			if key == "up" or key == "hup":
				s[key] = v.rotated(rot)
			else:
				s[key] = pelvis + (v - pelvis).rotated(rot) + Vector2(0, oy)
	return s


static func P(v: Vector2) -> Vector2:
	return Vector2(round(v.x), round(-v.y))


static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color, hi: Color) -> void:
	var pa := P(a)
	var pb := P(b)
	ci.draw_line(pa, pb, OUTLINE, w + 2.0)
	ci.draw_circle(pa, (w + 2.0) * 0.5, OUTLINE)
	ci.draw_circle(pb, (w + 2.0) * 0.5, OUTLINE)
	ci.draw_line(pa, pb, col, w)
	ci.draw_circle(pa, w * 0.5, col)
	ci.draw_circle(pb, w * 0.5, col)
	# highlight on the lit side (light from upper left on screen)
	var d := (pb - pa)
	if d.length() < 0.5:
		return
	var n := Vector2(-d.y, d.x).normalized()
	if n.dot(Vector2(-0.6, -0.8)) < 0.0:
		n = -n
	var off := n * (w * 0.5 - 1.2)
	ci.draw_line(pa + off + d * 0.15, pb + off - d * 0.15, hi, maxf(1.0, w * 0.22))


static func _boot(ci: CanvasItem, knee: Vector2, ankle: Vector2, pal: Dictionary, back: bool, tall: bool) -> void:
	var dn := (ankle - knee).normalized()
	var fw := dn.rotated(PI / 2.0)   # forward when the shin points down
	var col: Color = pal["boot"]
	var hi: Color = pal["boot_hi"]
	if back:
		col = _shade(col)
		hi = _shade(hi)
	var top := ankle - dn * (7.0 if tall else 2.0)
	var pts := PackedVector2Array([
		P(top - fw * 3.5), P(top + fw * 3.5), P(ankle + fw * 9.0 + dn * 1.0),
		P(ankle + fw * 9.5 + dn * 4.0), P(ankle - fw * 4.0 + dn * 4.0), P(ankle - fw * 4.5 + dn * 0.5)])
	var outline := PackedVector2Array()
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	for p in pts:
		outline.append(p + (p - c).normalized() * 1.2)
	ci.draw_colored_polygon(outline, OUTLINE)
	ci.draw_colored_polygon(pts, col)
	ci.draw_line(P(ankle - fw * 4.0 + dn * 3.6), P(ankle + fw * 9.0 + dn * 3.6), pal["sole"], 1.5)
	ci.draw_line(P(top + fw * 0.5), P(ankle + fw * 6.0), hi, 1.0)
	if pal.has("lace") and not back:
		for i in 3:
			ci.draw_rect(Rect2(P(ankle + fw * (1.0 + i * 2.2) - dn * (0.5 + i * 0.6)), Vector2(1, 1)), pal["lace"])


static func _hand(ci: CanvasItem, elbow: Vector2, hand: Vector2, pal: Dictionary, r: float, open: bool, back: bool) -> void:
	var skin: Color = pal["skin"]
	if back:
		skin = _shade(skin, 0.82)
	var ph := P(hand)
	ci.draw_circle(ph, r + 1.0, OUTLINE)
	ci.draw_circle(ph, r, skin)
	var d := (P(hand) - P(elbow)).normalized()
	if open:
		# claws
		for i in 3:
			var a := d.rotated(deg_to_rad(-35.0 + i * 35.0))
			var tip := ph + a * (r + 4.0)
			ci.draw_line(ph + a * r * 0.6, tip, OUTLINE, 2.0)
			ci.draw_line(ph + a * r * 0.6, tip - a, skin, 1.0)
	else:
		ci.draw_line(ph + d.rotated(PI / 2) * (r - 1) + d * 1.0, ph - d.rotated(PI / 2) * (r - 1) + d * 1.0, _shade(skin, 0.7), 1.0)


static func _torso(ci: CanvasItem, cid: String, s: Dictionary, pal: Dictionary) -> void:
	var k: Dictionary = SKEL[cid]
	var up: Vector2 = s["up"]
	var perp := Vector2(up.y, -up.x)
	var pel: Vector2 = s["pelvis"]
	var neck: Vector2 = s["neck"]
	var w0: float = k["waist"]
	var w1: float = k["chest"]
	var pts := PackedVector2Array([
		P(pel + perp * w0 - up * 2.0), P(pel - perp * w0 - up * 2.0),
		P(neck - perp * w1 - up * 1.0), P(neck - perp * (w1 - 3.0) + up * 2.0),
		P(neck + perp * (w1 - 3.0) + up * 2.0), P(neck + perp * w1 - up * 1.0)])
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var ol := PackedVector2Array()
	for p in pts:
		ol.append(p + (p - c).normalized() * 1.3)
	ci.draw_colored_polygon(ol, OUTLINE)
	ci.draw_colored_polygon(pts, pal["top"])
	# shading: back half darker, front edge highlight
	var back := PackedVector2Array([P(pel - perp * w0 - up * 2.0), P(pel - perp * (w0 * 0.2)), P(neck - perp * (w1 * 0.3)),
		P(neck - perp * w1 - up * 1.0)])
	ci.draw_colored_polygon(back, _shade(pal["top"], 0.75))
	ci.draw_line(P(neck + perp * (w1 - 1.5)), P(pel + perp * (w0 - 1.5)), pal["top_hi"], 1.0)
	if cid == "ced":
		# ribbed hem and crew collar
		ci.draw_line(P(pel + perp * w0), P(pel - perp * w0), _shade(pal["top"], 0.6), 3.0)
		for i in range(-2, 3):
			var b := pel + perp * (i * 3.5)
			ci.draw_line(P(b + up * 3.0), P(b + up * 9.0), _shade(pal["top"], 0.85), 1.0)
		ci.draw_line(P(neck - perp * 4.0 + up * 1.0), P(neck + perp * 4.0 + up * 1.0), _shade(pal["top"], 0.55), 2.0)
	elif cid == "murfurrie":
		# open suit jacket: dark shirt in a V down to the button, lapels, shirt collar and buttons
		var vtop_b := neck - perp * 3.0 + up * 1.5
		var vtop_f := neck + perp * 5.0 + up * 1.5
		var vbot := pel + perp * 2.0 + up * 9.0
		ci.draw_colored_polygon(PackedVector2Array([P(vtop_b), P(vtop_f), P(vbot)]), pal["shirt"])
		ci.draw_line(P(vtop_f - perp * 1.5 - up * 1.0), P(vbot + up * 2.0), pal["shirt_hi"], 1.0)
		for i in 3:
			ci.draw_rect(Rect2(P(neck + perp * 1.5 - up * (5.0 + i * 6.0)), Vector2(1, 1)), pal["button"])
		# collar points and the open neck (skin)
		ci.draw_colored_polygon(PackedVector2Array([P(neck - perp * 1.0 + up * 2.0), P(neck + perp * 3.0 + up * 2.0),
			P(neck + perp * 1.5 - up * 2.0)]), pal["skin"])
		# lapels (light, then the jacket edge in shadow)
		ci.draw_line(P(vtop_f + up * 0.5), P(vbot), _shade(pal["top"], 0.6), 1.0)
		ci.draw_line(P(vtop_b + up * 0.5), P(vbot - perp * 1.0), pal["top_hi"], 1.0)
		ci.draw_rect(Rect2(P(vbot - up * 1.0), Vector2(1, 1)), pal["button"])  # jacket button
		# hem and pocket flap
		ci.draw_line(P(pel + perp * w0 - up * 1.0), P(pel - perp * w0 - up * 1.0), _shade(pal["top"], 0.65), 1.0)
		ci.draw_line(P(pel - perp * 6.0 + up * 4.0), P(pel - perp * 1.5 + up * 4.0), _shade(pal["top"], 0.7), 1.0)
	else:
		# open collar showing chest, gold pendant, belt
		var v := PackedVector2Array([P(neck - perp * 3.0 + up * 1.5), P(neck + perp * 4.0 + up * 1.5), P(neck + perp * 1.0 - up * 12.0)])
		ci.draw_colored_polygon(v, pal["skin"])
		ci.draw_circle(P(neck + perp * 1.0 - up * 9.0), 1.5, pal["gold"])
		ci.draw_line(P(pel + perp * w0 + up * 1.0), P(pel - perp * w0 + up * 1.0), Color("0c080c"), 3.0)
		ci.draw_rect(Rect2(P(pel + perp * 3.0 + up * 2.0), Vector2(3, 3)), pal["gold"])
		# chain
		ci.draw_line(P(pel + perp * 5.0 + up * 4.0), P(pel - perp * 2.0 + up * 6.0), pal["gold"], 1.0)
		# brocade pattern dots
		for i in 6:
			var q := pel + up * (8.0 + (i % 3) * 7.0) + perp * (-5.0 + (i / 3) * 6.0)
			ci.draw_rect(Rect2(P(q), Vector2(1, 1)), pal["top_hi"])


static func _head(ci: CanvasItem, cid: String, s: Dictionary, pal: Dictionary) -> void:
	var k: Dictionary = SKEL[cid]
	var r: float = k["head_r"]
	var hc: Vector2 = s["head"]
	var hup: Vector2 = s["hup"]
	var fw := Vector2(hup.y, -hup.x)
	var skin: Color = pal["skin"]
	# outline + hair mass + face
	ci.draw_circle(P(hc), r + 1.2, OUTLINE)
	ci.draw_circle(P(hc + fw * 2.5 - hup * 3.5), r * 0.62 + 1.0, OUTLINE)  # jaw
	if cid == "kros":
		for i in 7:
			var a := deg_to_rad(-80.0 + i * 32.0)
			var bp := hc + hup.rotated(a) * (r - 1.0) - fw * 1.0
			ci.draw_circle(P(bp), 4.2, OUTLINE)
	ci.draw_circle(P(hc - fw * 1.0 + hup * 1.0), r, pal["hair"])
	ci.draw_circle(P(hc + fw * 1.8 - hup * 1.2), r - 1.6, skin)
	ci.draw_circle(P(hc + fw * 2.5 - hup * 3.5), r * 0.62, skin)
	# ear
	ci.draw_circle(P(hc - fw * 1.0 - hup * 1.0), 1.6, _shade(skin, 0.8))
	# hair top/back
	if cid == "kros":
		for i in 7:
			var a2 := deg_to_rad(-80.0 + i * 32.0)
			var bp2 := hc + hup.rotated(a2) * (r - 1.0) - fw * 1.0
			ci.draw_circle(P(bp2), 3.4, pal["hair"])
			ci.draw_rect(Rect2(P(bp2 + hup * 1.5 - fw * 1.0), Vector2(1, 1)), pal["hair_hi"])
			ci.draw_rect(Rect2(P(bp2 - hup * 1.5 + fw * 1.0), Vector2(1, 1)), pal["hair_dk"])
	elif cid == "murfurrie":
		# short, faded sides; volume swept up and back on top, a tuft rising over the forehead
		var mp := PackedVector2Array([P(hc - fw * (r + 0.3) - hup * 2.5), P(hc - fw * 5.0 + hup * (r + 0.5)),
			P(hc + fw * 1.0 + hup * (r + 2.5)), P(hc + fw * 5.5 + hup * (r + 2.0)), P(hc + fw * (r - 0.5) + hup * 4.0),
			P(hc + fw * 2.0 + hup * 4.5), P(hc - fw * 2.0 + hup * 2.0), P(hc - fw * 3.0 - hup * 3.0)])
		var c := Vector2.ZERO
		for p in mp:
			c += p
		c /= mp.size()
		var ol := PackedVector2Array()
		for p in mp:
			ol.append(p + (p - c).normalized() * 1.2)
		ci.draw_colored_polygon(ol, OUTLINE)
		ci.draw_colored_polygon(mp, pal["hair"])
		ci.draw_line(P(hc - fw * 3.0 + hup * (r - 0.5)), P(hc + fw * 4.5 + hup * (r + 1.0)), pal["hair_hi"], 1.0)
		ci.draw_line(P(hc - fw * (r - 1.0) - hup * 1.0), P(hc - fw * 3.5 + hup * 1.0), pal["hair_dk"], 1.0)  # faded side
	else:
		var hp := PackedVector2Array([P(hc - fw * (r + 0.5) - hup * 2.0), P(hc - fw * 4.0 + hup * (r + 0.8)),
			P(hc + fw * 5.5 + hup * (r - 0.5)), P(hc + fw * (r - 0.5) + hup * 3.5), P(hc + fw * 1.0 + hup * 4.0),
			P(hc - fw * 2.0 + hup * 2.0), P(hc - fw * 3.0 - hup * 2.5)])
		ci.draw_colored_polygon(hp, pal["hair"])
		ci.draw_line(P(hc - fw * 2.0 + hup * (r - 0.5)), P(hc + fw * 4.0 + hup * (r - 1.0)), pal["hair_hi"], 1.0)
	# face: brow, eye, nose, mouth
	var eye := hc + fw * 4.0 + hup * 0.5
	if cid == "murfurrie":
		# beard along the jaw and chin, moustache, angry brow pulled down to the nose, gritted teeth
		var jaw := hc + fw * 2.5 - hup * 3.5
		# short boxed beard: a strip along the jawline from the sideburn, thicker on the chin
		ci.draw_line(P(hc - fw * 0.8 - hup * 1.5), P(jaw + fw * 1.0 - hup * 4.0), pal["beard"], 2.0)
		ci.draw_line(P(jaw + fw * 1.0 - hup * 4.0), P(jaw + fw * 4.0 - hup * 3.0), pal["beard"], 2.0)
		ci.draw_rect(Rect2(P(jaw + fw * 3.0 - hup * 2.5), Vector2(2, 2)), pal["beard"])
		ci.draw_line(P(hc + fw * 3.5 - hup * 3.4), P(hc + fw * 7.0 - hup * 3.2), pal["beard"], 1.0)  # moustache
		ci.draw_line(P(hc + fw * 3.8 - hup * 4.6), P(hc + fw * 6.6 - hup * 4.4), Color("f2ece0"), 1.0)  # teeth
		ci.draw_line(P(eye + hup * 2.6 - fw * 1.5), P(eye + hup * 0.8 + fw * 2.5), OUTLINE, 2.0)  # scowl
		ci.draw_rect(Rect2(P(eye), Vector2(2, 1)), pal["eye"])
		ci.draw_rect(Rect2(P(hc + fw * (r + 0.5) - hup * 1.5), Vector2(1, 2)), _shade(skin, 0.75))
		return
	ci.draw_line(P(eye + hup * 2.0 - fw * 1.5), P(eye + hup * 1.2 + fw * 2.0), OUTLINE, 1.0)
	ci.draw_rect(Rect2(P(eye), Vector2(2, 1)), pal["eye"])
	ci.draw_rect(Rect2(P(hc + fw * (r + 0.5) - hup * 1.5), Vector2(1, 2)), _shade(skin, 0.75))
	ci.draw_line(P(hc + fw * 4.0 - hup * 4.6), P(hc + fw * 6.5 - hup * 4.4), _shade(skin, 0.55), 1.0)
	if cid == "kros":
		ci.draw_rect(Rect2(P(hc + fw * 4.0 - hup * 5.5), Vector2(1, 2)), Color("b01010"))  # blood drip
	else:
		ci.draw_line(P(hc + fw * 2.0 - hup * 6.0), P(hc + fw * 6.0 - hup * 5.5), _shade(skin, 0.8), 1.0)  # stubble


static func _cape(ci: CanvasItem, s: Dictionary, pal: Dictionary, sway: float) -> void:
	var up: Vector2 = s["up"]
	var perp := Vector2(up.y, -up.x)
	var neck: Vector2 = s["neck"]
	var pel: Vector2 = s["pelvis"]
	var down := -up
	var sh_b := neck - perp * 11.0
	var sh_f := neck + perp * 6.0
	var mid := pel - perp * (16.0 + sway * 0.5) + up * 10.0
	var hem_b := pel - perp * (26.0 + sway) + down * 40.0
	var hem_f := pel + perp * 4.0 + down * 44.0
	var outer := PackedVector2Array([P(sh_f + up * 2.0), P(sh_b + up * 2.0), P(mid), P(hem_b), P(hem_b + perp * 10.0 + down * 2.0),
		P(hem_f - perp * 8.0 + down * 1.0), P(hem_f)])
	var c := Vector2.ZERO
	for p in outer:
		c += p
	c /= outer.size()
	var ol := PackedVector2Array()
	for p in outer:
		ol.append(p + (p - c).normalized() * 1.3)
	ci.draw_colored_polygon(ol, OUTLINE)
	ci.draw_colored_polygon(outer, pal["cape"])
	var lining := PackedVector2Array([P(sh_b + up * 1.0), P(mid), P(hem_b), P(hem_b + perp * 7.0), P(mid + perp * 6.0 + down * 6.0),
		P(sh_b + perp * 5.0)])
	ci.draw_colored_polygon(lining, pal["cape_in"])
	ci.draw_line(P(sh_b + perp * 2.0), P(mid + perp * 2.0), pal["cape_hi"], 1.0)
	ci.draw_line(P(mid + perp * 3.0), P(hem_b + perp * 4.0), pal["cape_hi"], 1.0)
	# fold lines
	for i in 3:
		var a := pel - perp * (4.0 + i * 7.0) + down * 6.0
		ci.draw_line(P(a), P(a - perp * (2.0 + sway * 0.3) + down * 30.0), _shade(pal["cape"], 0.6), 1.0)
	ci.draw_line(P(hem_b), P(hem_f), pal["gold"], 1.0)


static func _collar(ci: CanvasItem, s: Dictionary, pal: Dictionary) -> void:
	var up: Vector2 = s["up"]
	var perp := Vector2(up.y, -up.x)
	var neck: Vector2 = s["neck"]
	var pts := PackedVector2Array([P(neck - perp * 8.0), P(neck - perp * 12.0 + up * 15.0), P(neck - perp * 3.0 + up * 9.0),
		P(neck + perp * 2.0 + up * 1.0)])
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var ol := PackedVector2Array()
	for p in pts:
		ol.append(p + (p - c).normalized() * 1.3)
	ci.draw_colored_polygon(ol, OUTLINE)
	ci.draw_colored_polygon(pts, pal["cape_in"])
	ci.draw_line(P(neck - perp * 8.0), P(neck - perp * 12.0 + up * 15.0), pal["gold"], 1.0)


## Draws the whole character at the canvas origin (feet), facing +x.
static func draw(ci: CanvasItem, cid: String, pal: Dictionary, pose: Dictionary, sway := 0.0) -> void:
	var k: Dictionary = SKEL[cid]
	var s := skeleton(cid, pose)
	var open := float(pose.get("open", 0.0)) > 0.5
	var tall := cid == "kros"
	if cid == "kros":
		_cape(ci, s, pal, sway)
	# back arm
	var top_b := _shade(pal["top"]) if cid == "ced" else _shade(pal["top"], 0.8)
	_limb(ci, s["sh_b"], s["el_b"], k["ua_w"], top_b, _shade(pal["top_hi"]))
	_limb(ci, s["el_b"], s["ha_b"], k["fa_w"], top_b, _shade(pal["top_hi"]))
	_hand(ci, s["el_b"], s["ha_b"], pal, k["fist"], open, true)
	# back leg
	_limb(ci, s["hip_b"], s["kn_b"], k["thigh_w"], _shade(pal["pants"]), _shade(pal["pants_hi"]))
	_limb(ci, s["kn_b"], s["ft_b"], k["shin_w"], _shade(pal["pants"]), _shade(pal["pants_hi"]))
	_boot(ci, s["kn_b"], s["ft_b"], pal, true, tall)
	# hips
	ci.draw_circle(P(s["pelvis"]), float(k["waist"]) + 1.0, OUTLINE)
	ci.draw_circle(P(s["pelvis"]), float(k["waist"]), pal["pants"])
	# front leg
	_limb(ci, s["hip_f"], s["kn_f"], k["thigh_w"], pal["pants"], pal["pants_hi"])
	_limb(ci, s["kn_f"], s["ft_f"], k["shin_w"], pal["pants"], pal["pants_hi"])
	if cid == "murfurrie":
		# trouser crease down the front leg
		ci.draw_line(P((s["hip_f"] as Vector2).lerp(s["kn_f"], 0.3)), P((s["kn_f"] as Vector2).lerp(s["ft_f"], 0.8)),
			pal["pants_hi"], 1.0)
	if cid == "ced":
		# baggy trouser folds
		var kn: Vector2 = s["kn_f"]
		ci.draw_line(P(kn + Vector2(-2, -3)), P(kn + Vector2(2, -7)), _shade(pal["pants"], 0.8), 1.0)
	_boot(ci, s["kn_f"], s["ft_f"], pal, false, tall)
	_torso(ci, cid, s, pal)
	if cid == "kros":
		_collar(ci, s, pal)
	_head(ci, cid, s, pal)
	# front arm
	_limb(ci, s["sh_f"], s["el_f"], k["ua_w"], pal["top"], pal["top_hi"])
	_limb(ci, s["el_f"], s["ha_f"], k["fa_w"], pal["top"], pal["top_hi"])
	if cid == "ced":
		# sweater cuff
		var e: Vector2 = s["el_f"]
		var h: Vector2 = s["ha_f"]
		var cuff := e.lerp(h, 0.8)
		ci.draw_circle(P(cuff), float(k["fa_w"]) * 0.5, _shade(pal["top"], 0.7))
	elif cid == "murfurrie":
		# dark shirt cuff showing at the end of the jacket sleeve
		var cuff2: Vector2 = (s["el_f"] as Vector2).lerp(s["ha_f"], 0.85)
		ci.draw_circle(P(cuff2), float(k["fa_w"]) * 0.45, pal["shirt"])
	_hand(ci, s["el_f"], s["ha_f"], pal, k["fist"], open, false)


## Draws only the head, scaled, for HUD portraits.
static func draw_portrait(ci: CanvasItem, cid: String, pal: Dictionary, center: Vector2, scale: float, flip := false, with_torso := true) -> void:
	var pose := Poses.idle(cid, 0.0)
	pose["head"] = 0.0
	pose["lean"] = 0.0
	var s := skeleton(cid, pose)
	var hc: Vector2 = s["head"]
	ci.draw_set_transform(center + Vector2(-hc.x * scale * (-1.0 if flip else 1.0), hc.y * scale), 0.0,
			Vector2(scale * (-1.0 if flip else 1.0), scale))
	if cid == "kros":
		_collar(ci, s, pal)
	if with_torso:
		_torso(ci, cid, s, pal)
	_head(ci, cid, s, pal)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
