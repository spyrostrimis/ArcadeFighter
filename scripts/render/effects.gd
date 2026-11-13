class_name Effects
extends Node2D
## Hit sparks, block flashes and dust puffs (world space).

const FLOOR_Y := 200

var _items: Array = []
var sim: MatchSim
var show_boxes := false


func spark(x: float, y: float, strength: int, blocked: bool) -> void:
	_items.append({"k": "block" if blocked else "hit", "x": x, "y": FLOOR_Y - y, "t": 0,
		"life": 10 + strength * 3, "s": strength})


func dust(x: float, big: bool) -> void:
	_items.append({"k": "dust", "x": x, "y": FLOOR_Y - 2, "t": 0, "life": 18 if big else 12, "s": 2 if big else 1})


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
			"dust":
				for i in 3:
					var dx := (i - 1) * (6.0 + u * 10.0) * s
					draw_circle(p + Vector2(dx, -u * 6.0), (2.0 + u * 4.0) * s * 0.7, Color(0.85, 0.7, 0.55, 0.6 * (1.0 - u)))
	if show_boxes and sim != null:
		for fi in sim.f:
			for r in fi.hurt_rects():
				_box(r, Color(0.2, 0.5, 1.0, 0.8))
			if fi.move_active() and fi.move_hit == 0:
				_box(fi.hit_rect(), Color(1.0, 0.2, 0.2, 0.9))
			var span := fi.push_span()
			var pw: int = fi.data["push_w"]
			_box(Rect2i(fi.px() - pw, span.x, pw * 2, span.y - span.x), Color(1, 1, 1, 0.35))


func _box(r: Rect2i, c: Color) -> void:
	draw_rect(Rect2(r.position.x, FLOOR_Y - r.position.y - r.size.y, r.size.x, r.size.y), c, false, 1.0)
