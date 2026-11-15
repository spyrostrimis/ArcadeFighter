class_name Effects
extends Node2D
## Hit sparks, block flashes, dust puffs and projectiles (world space).
## Projectiles are drawn straight from the sim's state, so they follow rollback.

const FLOOR_Y := 200

var _items: Array = []
var sim: MatchSim
var show_boxes := false


func spark(x: float, y: float, strength: int, blocked: bool) -> void:
	_items.append({"k": "block" if blocked else "hit", "x": x, "y": FLOOR_Y - y, "t": 0,
		"life": 10 + strength * 3, "s": strength})


func dust(x: float, big: bool) -> void:
	_items.append({"k": "dust", "x": x, "y": FLOOR_Y - 2, "t": 0, "life": 18 if big else 12, "s": 2 if big else 1})


## Spit hitting the floor: a puddle spreading out and a few drops bouncing up.
func splat(x: float) -> void:
	_items.append({"k": "splat", "x": x, "y": FLOOR_Y - 1, "t": 0, "life": 22, "s": 1})


## Two projectiles meeting: a burst of droplets.
func clash(x: float, y: float) -> void:
	_items.append({"k": "splat", "x": x, "y": FLOOR_Y - y, "t": 0, "life": 14, "s": 2})


func tick() -> void:
	for it in _items:
		it["t"] += 1
	_items = _items.filter(func(it): return it["t"] < it["life"])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for it in _items:
		var p := Vector2(it["x"], it["y"])
		var t: int = it["t"]
		var life: int = it["life"]
		var u := float(t) / life
		var s: int = it["s"]
		match it["k"]:
			"hit":
				var r := (6.0 + s * 4.0) * (0.4 + u)
				var core := Color(1, 1, 1, 1.0 - u)
				for i in 8:
					var a := TAU * i / 8.0 + 0.3
					var len := r * (1.4 if i % 2 == 0 else 0.9)
					draw_line(p + Vector2.from_angle(a) * r * 0.3, p + Vector2.from_angle(a) * len,
							Color(1.0, 0.85 - u * 0.5, 0.2, 1.0 - u), 2.0 if s > 0 else 1.0)
				if t < 4:
					draw_circle(p, 4.0 + s * 2.0 - t, core)
			"block":
				var r2 := (5.0 + s * 3.0) * (0.5 + u)
				var col := Color(0.6, 0.85, 1.0, 1.0 - u)
				var pts := PackedVector2Array([p + Vector2(0, -r2), p + Vector2(r2 * 0.5, 0), p + Vector2(0, r2), p + Vector2(-r2 * 0.5, 0)])
				pts.append(pts[0])
				draw_polyline(pts, col, 1.0)
				if t < 3:
					draw_circle(p, 3.0, Color(1, 1, 1, 0.9))
			"splat":
				var a2 := 1.0 - u
				if s == 1:
					_ellipse(p, 3.0 + u * 7.0, 1.0 + u * 1.2, Color(0.80, 0.86, 0.70, 0.8 * a2))
					_ellipse(p + Vector2(-1, -0.5), 1.5 + u * 4.0, 0.6, Color(1, 1, 1, 0.6 * a2))
				for i in 4:
					var dx2 := (i - 1.5) * (3.0 + u * 9.0)
					var dy2 := -sin(u * PI) * (5.0 + (i % 2) * 3.0) * (1.6 if s == 2 else 1.0)
					draw_rect(Rect2(p + Vector2(dx2, dy2), Vector2(1, 1)), Color(0.88, 0.93, 0.80, a2))
			"dust":
				for i in 3:
					var dx := (i - 1) * (6.0 + u * 10.0) * s
					draw_circle(p + Vector2(dx, -u * 6.0), (2.0 + u * 4.0) * s * 0.7, Color(0.85, 0.7, 0.55, 0.6 * (1.0 - u)))
	if sim != null:
		for fi in sim.f:
			if fi.pj_on:
				_spit(fi)
	if show_boxes and sim != null:
		for fi in sim.f:
			for r in fi.hurt_rects():
				_box(r, Color(0.2, 0.5, 1.0, 0.8))
			if fi.move_active() and fi.move_hit == 0:
				_box(fi.hit_rect(), Color(1.0, 0.2, 0.2, 0.9))
			if fi.pj_on:
				_box(fi.proj_rect(), Color(1.0, 0.2, 0.2, 0.9))
			var span := fi.push_span()
			var pw: int = fi.data["push_w"]
			_box(Rect2i(fi.px() - pw, span.x, pw * 2, span.y - span.x), Color(1, 1, 1, 0.35))


func _box(r: Rect2i, c: Color) -> void:
	draw_rect(Rect2(r.position.x, FLOOR_Y - r.position.y - r.size.y, r.size.x, r.size.y), c, false, 1.0)


## A glob of spit flying along its velocity, wobbling, with drops trailing behind it.
func _spit(fi: Fighter) -> void:
	var p := Vector2(round(fi.pj_x / 100.0), round(FLOOR_Y - fi.pj_y / 100.0))
	var d := Vector2(fi.pj_vx, -fi.pj_vy).normalized()
	var wob := 0.5 if (fi.pj_t / 3) % 2 == 0 else 0.0
	var body := Color(0.86, 0.91, 0.76)
	var shade := Color(0.62, 0.70, 0.52)
	for i in 3:   # trailing drops, smaller and fainter further back
		var q := p - d * (5.0 + i * 3.5) + Vector2(0, (i % 2) * 1.0)
		draw_circle(q.round(), 1.4 - i * 0.35, Color(body, 0.85 - i * 0.25))
	draw_circle(p, 3.6 + wob, Color("1e2a14"))     # outline
	draw_circle(p, 2.8 + wob, shade)
	draw_circle(p + d * 0.8 + Vector2(0, -0.4), 2.1 + wob, body)
	draw_rect(Rect2(p + d * 1.2 + Vector2(-0.5, -1.6), Vector2(1, 1)), Color(1, 1, 1, 0.95))   # glint


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
