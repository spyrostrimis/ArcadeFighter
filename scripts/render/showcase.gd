class_name Showcase
extends Node2D
## SHORTY's round-1 intro (MatchSim.in_showcase): two tall ladies in evening dresses stand
## either side of him while he poses, then walk off behind him before "ROUND 1" is announced.
## Drawn from the sim's phase and frame counter only, so it replays the same under rollback.
## Placeholder art drawn in code; real sprites can replace _lady() later.

const FLOOR_Y := 200
const LEAVE_AT := 96     # showcase frame the ladies start walking off
const WALK_SPEED := 3.0  # px per frame
const SIDE := 27         # px from SHORTY's feet to each lady's

const OUTLINE := Color("140a10")
const LADIES := [
	{"dress": Color("b3122b"), "dress_hi": Color("e33a52"), "hair": Color("e2b85a"), "hair_hi": Color("fbe5a0"),
		"hair_dk": Color("9c7430"), "skin": Color("f2caa8"), "shoe": Color("c0182e"), "lips": Color("c41a32")},
	{"dress": Color("1d1a26"), "dress_hi": Color("6b5c92"), "hair": Color("3a2018"), "hair_hi": Color("6e4430"),
		"hair_dk": Color("1e100a"), "skin": Color("d9a07a"), "shoe": Color("101014"), "lips": Color("9a1a2a"),
		"gold": Color("e0b040")},
]

var sim: MatchSim


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null or not sim.in_showcase():
		return
	var t := sim.pf
	for fi in sim.f:
		if not fi.data.has("showcase"):
			continue
		var x0 := fi.x / 100.0
		var away := -fi.facing        # they leave towards the screen edge behind him
		for i in 2:
			var side := -1 if i == 0 else 1
			var x := x0 + side * SIDE
			var walking := t >= LEAVE_AT
			var face := fi.facing * (-1 if side > 0 else 1)   # turned towards him while posing
			if walking:
				x += away * WALK_SPEED * (t - LEAVE_AT)
				face = away
			_lady(Vector2(round(x), FLOOR_Y), LADIES[i], face, walking, t + i * 7, i == 1)


## One lady, feet at `at`. Mostly front-on (a promo pose); `face` turns her head and hips.
func _lady(at: Vector2, c: Dictionary, face: int, walking: bool, t: int, hand_on_hip: bool) -> void:
	var step := sin(t * 0.35) if walking else 0.0
	var bob := absf(step) * 1.0 if walking else 0.0
	var sway := 0.0 if walking else sin(t * 0.05) * 0.6
	var hip := 2.0 * face + sway                                  # hips cocked to one side
	# y is up from the feet; P() turns it into screen space
	var P := func(x: float, y: float) -> Vector2:
		return (at + Vector2(x, -y - bob)).round()
	# --- legs and heels (long; the dress stops mid-thigh)
	var feet := [Vector2(-4 + step * 5.0, 0), Vector2(4 - step * 5.0, 0)]
	if not walking:
		feet = [Vector2(-3 + hip * 0.5, 0), Vector2(5 + hip * 0.3, 0)]
	for k in 2:
		var hx := (-4.0 if k == 0 else 4.0) + hip
		var fx: float = feet[k].x
		var lift := maxf(0.0, (step if k == 0 else -step)) * 3.0 if walking else 0.0
		var knee := Vector2((hx + fx) / 2.0 + face * 1.0, 27.0 + lift)
		_shape([P.call(hx - 3.0, 50), P.call(hx + 3.0, 50), P.call(knee.x + 2.2, knee.y), P.call(fx + 1.4, 5 + lift),
			P.call(fx - 1.4, 5 + lift), P.call(knee.x - 2.2, knee.y)], c["skin"])
		# heel: pointed toe forward, thin heel back
		var shoe := [P.call(fx - face * 2.0, 5 + lift), P.call(fx + face * 2.0, 5 + lift),
			P.call(fx + face * 4.5, 1 + lift), P.call(fx + face * 3.5, 0 + lift), P.call(fx - face * 2.0, 0 + lift),
			P.call(fx - face * 2.0, 3 + lift)]
		if face < 0:
			shoe.reverse()   # keep the winding when she faces left
		_shape(shoe, c["shoe"])
	# --- dress: fitted, short, slit hem, strapless with a sweetheart top
	_shape([P.call(-10 + hip, 38), P.call(10 + hip, 38), P.call(9 + hip, 52), P.call(6 + hip * 0.5, 62),
		P.call(8, 74), P.call(7, 80), P.call(3, 78), P.call(0, 80), P.call(-3, 78), P.call(-7, 80), P.call(-8, 74),
		P.call(-6 + hip * 0.5, 62), P.call(-9 + hip, 52)], c["dress"])
	draw_line(P.call(-5 + hip, 40), P.call(-3 + hip * 0.5, 60), c["dress_hi"], 1.0)
	draw_line(P.call(5, 76), P.call(4 + hip * 0.5, 62), c["dress_hi"], 1.0)
	if c.has("gold"):   # sequins
		for k in 5:
			draw_rect(Rect2(P.call(-6 + k * 3 + hip, 44 + (k % 2) * 7), Vector2(1, 1)), c["gold"])
	# --- shoulders, neck, arms
	_shape([P.call(-8, 78), P.call(8, 78), P.call(9, 83), P.call(2, 86), P.call(-2, 86), P.call(-9, 83)], c["skin"])
	_shape([P.call(-2, 85), P.call(2, 85), P.call(2, 90), P.call(-2, 90)], c["skin"])
	var arm_swing := step * 4.0
	# arm on the far side: down by her side (or swinging)
	_limb(P.call(-9, 82), P.call(-12 - arm_swing * 0.3, 66), P.call(-12 + arm_swing, 50), c["skin"])
	if hand_on_hip and not walking:
		_limb(P.call(9, 82), P.call(16, 68), P.call(8 + hip, 58), c["skin"])   # hand on the hip
	else:
		_limb(P.call(9, 82), P.call(12 + arm_swing * 0.3, 66), P.call(12 - arm_swing, 50), c["skin"])
	# --- head and long hair (falls behind the shoulders)
	var hx2 := face * 1.0
	_shape([P.call(hx2 - 8, 104), P.call(hx2 + 8, 104), P.call(hx2 + 10, 90), P.call(hx2 + 9, 74),
		P.call(hx2 + 4, 78), P.call(hx2 - 4, 78), P.call(hx2 - 9, 74), P.call(hx2 - 10, 90)], c["hair"])
	_shape([P.call(hx2 - 5, 100), P.call(hx2 + 5, 100), P.call(hx2 + 5, 93), P.call(hx2 + 2, 89),
		P.call(hx2 - 2, 89), P.call(hx2 - 5, 93)], c["skin"])
	# fringe swept to one side, highlight
	_shape([P.call(hx2 - 7, 104), P.call(hx2 + 7, 105), P.call(hx2 + 6, 99), P.call(hx2 - face * 2.0, 101),
		P.call(hx2 - 6, 97)], c["hair"])
	draw_line(P.call(hx2 - 4, 103), P.call(hx2 + 4, 104), c["hair_hi"], 1.0)
	draw_line(P.call(hx2 - 8, 90), P.call(hx2 - 8, 80), c["hair_dk"], 1.0)
	# face: eyes, lips (looking `face`)
	var ex := hx2 + face * 1.0
	draw_rect(Rect2(P.call(ex - 3, 96), Vector2(1, 1)), Color("2a1418"))
	draw_rect(Rect2(P.call(ex + 2, 96), Vector2(1, 1)), Color("2a1418"))
	draw_rect(Rect2(P.call(ex - 1, 92), Vector2(2, 1)), c["lips"])


## Filled polygon with a 1 px dark outline.
func _shape(pts: Array, col: Color) -> void:
	var poly := PackedVector2Array(pts)
	if Geometry2D.triangulate_polygon(poly).is_empty():
		poly = Geometry2D.convex_hull(poly)   # a pose folded the outline over itself
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var moved := PackedVector2Array()
		for p in poly:
			moved.append(p + o)
		draw_colored_polygon(moved, OUTLINE)
	draw_colored_polygon(poly, col)


## Slim arm: shoulder -> elbow -> hand, outlined.
func _limb(a: Vector2, b: Vector2, h: Vector2, col: Color) -> void:
	for seg in [[a, b, 3.0], [b, h, 2.5]]:
		draw_line(seg[0], seg[1], OUTLINE, float(seg[2]) + 2.0)
	for seg in [[a, b, 3.0], [b, h, 2.5]]:
		draw_line(seg[0], seg[1], col, float(seg[2]))
	draw_circle(h, 1.6, col)
