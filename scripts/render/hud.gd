class_name Hud
extends Node2D
## Arcade-style HUD: scores, portraits, health bars, timer, round markers, banners.

const BAR_W := 146
const BAR_H := 9
const BAR_Y := 13

const YELLOW := [Color("fff6a0"), Color("ffe800"), Color("ffd000"), Color("d8a000")]
const TIMER_GRAD := [Color("fff6b0"), Color("ffe040"), Color("ffb020"), Color("f07010")]
const NAME_GRAD := [Color("ffffff"), Color("c8e0ff"), Color("78a8ff"), Color("3868e0")]
const ROUND_GRAD := [Color("e8f4ff"), Color("90c8ff"), Color("4888f0"), Color("2050c0")]
const FIGHT_GRAD := [Color("fff8b0"), Color("ffe030"), Color("ffa020"), Color("f05010"), Color("c01808")]
const KO_GRAD := [Color("fff0e0"), Color("ff8060"), Color("e02010"), Color("901008")]
const DARK := Color("120818")

var sim: MatchSim
var pals: Array = []
var cpu_side := [false, true]
var demo := false
var online_local := -1   # online: which slot is this player (for YOU WIN / YOU LOSE)
var _red := [1000.0, 1000.0]
var _red_delay := [0, 0]
var _combo := [{"n": 0, "t": 0}, {"n": 0, "t": 0}]
var _blink := 0


func setup(p_sim: MatchSim, p_pals: Array, p_cpu: Array, p_demo: bool) -> void:
	sim = p_sim
	pals = p_pals
	cpu_side = p_cpu
	demo = p_demo
	reset_bars()


func reset_bars() -> void:
	for i in 2:
		_red[i] = float(sim.f[i].health)
		_red_delay[i] = 0


func show_combo(attacker: int, n: int) -> void:
	if n >= 2:
		_combo[attacker] = {"n": n, "t": 90}


func tick() -> void:
	_blink += 1
	for i in 2:
		var hp := float(sim.f[i].health)
		if _red[i] < hp:
			_red[i] = hp
		elif _red[i] > hp:
			if sim.f[i].state == Fighter.HITSTUN or sim.f[i].state == Fighter.FALL or sim.hitstop > 0:
				_red_delay[i] = 25
			if _red_delay[i] > 0:
				_red_delay[i] -= 1
			else:
				_red[i] = maxf(hp, _red[i] - 6.0)
		if _combo[i]["t"] > 0:
			_combo[i]["t"] -= 1


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	_top_strip()
	for i in 2:
		_bar(i)
		_portrait(i)
		_name_and_wins(i)
		_combo_text(i)
	_timer()
	_banner()


func _top_strip() -> void:
	draw_rect(Rect2(0, 0, 384, 9), Color(0, 0, 0, 0.55))
	PixelFont.draw(self, "1P", Vector2(6, 1), 1, [Color("ff9070"), Color("e83818")], DARK, 0, true)
	PixelFont.draw(self, "%06d" % mini(sim.f[0].score, 999999), Vector2(26, 1), 1, YELLOW, DARK, 0, true)
	PixelFont.draw(self, "HI", Vector2(138, 1), 1, [Color("ff9070"), Color("e83818")], DARK, 0, true)
	var hi := maxi(Game.hi_score, sim.f[0].score)
	PixelFont.draw(self, "%07d" % mini(hi, 9999999), Vector2(156, 1), 1, [Color("ffd0c0"), Color("ff5030")], DARK, 0, true)
	var right := ""
	if demo:
		right = "DEMO PLAY"
	elif cpu_side[1]:
		right = "INSERT COIN" if (_blink / 40) % 2 == 0 else ""
	else:
		right = "2P %06d" % mini(sim.f[1].score, 999999)
	if right != "":
		var w := PixelFont.width(right, 1, true)
		PixelFont.draw(self, right, Vector2(378 - w, 1), 1, [Color("ffffff"), Color("c0c8ff")], DARK, 0, true)


func _bar(i: int) -> void:
	var fi: Fighter = sim.f[i]
	var maxh := float(fi.data["health"])
	var x0 := 28 if i == 0 else 384 - 28 - BAR_W
	# frame
	draw_rect(Rect2(x0 - 2, BAR_Y - 2, BAR_W + 4, BAR_H + 4), Color("0a0a20"))
	draw_rect(Rect2(x0 - 1, BAR_Y - 1, BAR_W + 2, BAR_H + 2), Color("e8ecff"))
	draw_rect(Rect2(x0, BAR_Y, BAR_W, BAR_H), Color("3a0810"))
	var hw := int(round(BAR_W * fi.health / maxh))
	var rw := int(round(BAR_W * _red[i] / maxh))
	# P1 bar is anchored on the left (outer) edge, P2 on the right.
	var low := fi.health < maxh * 0.25 and (_blink / 6) % 2 == 0
	if i == 0:
		draw_rect(Rect2(x0, BAR_Y, rw, BAR_H), Color("e02818"))
		_yellow(Rect2(x0, BAR_Y, hw, BAR_H), low)
	else:
		draw_rect(Rect2(x0 + BAR_W - rw, BAR_Y, rw, BAR_H), Color("e02818"))
		_yellow(Rect2(x0 + BAR_W - hw, BAR_Y, hw, BAR_H), low)


func _yellow(r: Rect2, low: bool) -> void:
	if r.size.x <= 0:
		return
	for row in int(r.size.y):
		var c: Color = YELLOW[clampi(row * YELLOW.size() / int(r.size.y), 0, YELLOW.size() - 1)]
		if low:
			c = c.lerp(Color("ff8040"), 0.5)
		draw_rect(Rect2(r.position.x, r.position.y + row, r.size.x, 1), c)


func _portrait(i: int) -> void:
	var x0 := 3 if i == 0 else 384 - 3 - 23
	var y0 := 11
	draw_rect(Rect2(x0, y0, 23, 23), Color("0a0a20"))
	draw_rect(Rect2(x0 + 1, y0 + 1, 21, 21), Color("f0a040"))
	draw_rect(Rect2(x0 + 2, y0 + 2, 19, 19), Color("a02818"))
	var fi: Fighter = sim.f[i]
	var pal: Dictionary = pals[i]
	draw_rect(Rect2(x0 + 2, y0 + 17, 19, 4), pal["top"])
	Puppet.draw_portrait(self, fi.cid, pal, Vector2(x0 + 11.5, y0 + 10), 1.0, i == 1, false)


func _name_and_wins(i: int) -> void:
	var fi: Fighter = sim.f[i]
	var nm: String = fi.data["name"]
	var y := 25
	if i == 0:
		PixelFont.draw(self, nm, Vector2(30, y), 2, NAME_GRAD, DARK, 1, false, 1)
	else:
		var w := PixelFont.width(nm, 2)
		PixelFont.draw(self, nm, Vector2(354 - w - 2, y), 2, NAME_GRAD, DARK, 1, false, 1)
	for k in sim.wins_needed:
		var bx := (30 + k * 11) if i == 0 else (384 - 30 - 9 - k * 11)
		var by := 42
		draw_rect(Rect2(bx, by, 9, 9), Color("0a0a20"))
		draw_rect(Rect2(bx + 1, by + 1, 7, 7), Color("e8ecff"))
		draw_rect(Rect2(bx + 2, by + 2, 5, 5), Color("1a1a40"))
		if fi.wins > k:
			draw_rect(Rect2(bx + 2, by + 2, 5, 5), Color("ffd000"))
			draw_rect(Rect2(bx + 3, by + 3, 3, 3), Color("ff7010"))


func _combo_text(i: int) -> void:
	var c: Dictionary = _combo[i]
	if c["t"] <= 0:
		return
	var txt := "%d HITS" % c["n"]
	var y := 66
	if i == 0:
		PixelFont.draw(self, txt, Vector2(14, y), 2, FIGHT_GRAD, DARK, 1, true)
	else:
		PixelFont.draw(self, txt, Vector2(370 - PixelFont.width(txt, 2, true), y), 2, FIGHT_GRAD, DARK, 1, true)


func _timer() -> void:
	var x0 := 177
	var y0 := 9
	draw_rect(Rect2(x0, y0, 30, 30), Color("0a0a20"))
	draw_rect(Rect2(x0 + 1, y0 + 1, 28, 28), Color("4060d0"))
	draw_rect(Rect2(x0 + 2, y0 + 2, 26, 26), Color("101038"))
	PixelFont.draw_centered(self, "TIME", 192, y0 + 3, 1, [Color("e0e8ff"), Color("90a8ff")])
	var tt := "%02d" % sim.timer if sim.round_time > 0 else "--"
	var flash := sim.round_time > 0 and sim.timer <= 10 and sim.phase == MatchSim.FIGHT and (_blink / 8) % 2 == 0
	PixelFont.draw_centered(self, tt, 192, y0 + 13, 2, KO_GRAD if flash else TIMER_GRAD, DARK, 0, true)


func _banner() -> void:
	var cx := 192.0
	var y := 78.0
	var ph := sim.phase
	var pf := sim.intro_pf() if ph == MatchSim.INTRO else sim.pf
	match ph:
		MatchSim.INTRO:
			if pf >= 8 and pf < 70:
				PixelFont.draw_centered(self, "ROUND %d" % sim.round_num, cx, y, 3, ROUND_GRAD, DARK, 1, true, 2)
			elif pf >= 70:
				PixelFont.draw_centered(self, "FIGHT!", cx, y - 4, 5, FIGHT_GRAD, DARK, 1, true, 2)
		MatchSim.FIGHT:
			if pf < 25:
				PixelFont.draw_centered(self, "FIGHT!", cx, y - 4, 5, FIGHT_GRAD, DARK, 1, true, 2)
		MatchSim.KO_SLOW, MatchSim.ROUND_END:
			if sim.time_over:
				PixelFont.draw_centered(self, "TIME OVER", cx, y, 3, FIGHT_GRAD, DARK, 1, true, 2)
			elif sim.ko_happened:
				var txt := "DOUBLE K.O." if sim.round_winner == 2 else "K.O."
				var sc := 3 if sim.round_winner == 2 else 6
				if ph == MatchSim.ROUND_END or (pf / 6) % 2 == 0 or pf > 40:
					PixelFont.draw_centered(self, txt, cx, y - 8, sc, KO_GRAD, DARK, 1, true, 2)
		MatchSim.WIN_POSE:
			var w := sim.round_winner
			if pf > 10:
				if w == 2:
					PixelFont.draw_centered(self, "DRAW", cx, y, 3, ROUND_GRAD, DARK, 1, true, 2)
				else:
					var nm: String = sim.f[w].data["name"]
					PixelFont.draw_centered(self, nm + " WINS", cx, y, 3, ROUND_GRAD, DARK, 1, true, 2)
					if sim.f[w].health == int(sim.f[w].data["health"]):
						PixelFont.draw_centered(self, "PERFECT", cx, y + 28, 3, FIGHT_GRAD, DARK, 1, true, 2)
		MatchSim.MATCH_OVER:
			var mw := sim.match_winner
			var txt2 := ""
			if mw == 2:
				txt2 = "DRAW GAME"
			elif online_local >= 0:
				txt2 = "YOU WIN!" if mw == online_local else "YOU LOSE"
			elif not demo and not cpu_side[0] and not cpu_side[1]:
				txt2 = "%dP WINS" % (mw + 1)
			elif demo or (cpu_side[0] == cpu_side[1]):
				txt2 = String(sim.f[mw].data["name"]) + " WINS"
			else:
				var human := 0 if not cpu_side[0] else 1
				txt2 = "YOU WIN!" if mw == human else "YOU LOSE"
			PixelFont.draw_centered(self, txt2, cx, y, 4, FIGHT_GRAD if txt2 != "YOU LOSE" else KO_GRAD, DARK, 1, true, 2)
			if pf > 90 and (_blink / 30) % 2 == 0 and online_local < 0:
				PixelFont.draw_centered(self, "PRESS START", cx, y + 40, 1, [Color.WHITE, Color("c0c8ff")], DARK, 0, true)
