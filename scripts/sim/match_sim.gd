class_name MatchSim
extends RefCounted
## Deterministic match simulation: two fighters, rounds, timer, hits.
## step() takes one input bitmask per player and advances exactly one frame.

enum { INTRO, FIGHT, KO_SLOW, ROUND_END, WIN_POSE, MATCH_OVER }

const SUB := 100
const STAGE_W := 512
const SCREEN_W := 384
const EDGE := 14
const ROUND_TIME := 99
const START_GAP := 72
const WINS_NEEDED := 2

const SAVE_FIELDS := [
	"phase", "pf", "round_num", "timer", "timer_frames", "hitstop", "frame",
	"cam_x", "round_winner", "match_winner", "time_over", "ko_happened",
]

var f: Array[Fighter] = []
var phase := INTRO
var pf := 0                 # frames in current phase
var round_num := 1
var timer := ROUND_TIME
var timer_frames := 0
var hitstop := 0
var frame := 0
var cam_x := 0
var round_winner := -1      # 0/1 = player slot, 2 = draw
var match_winner := -1      # 0/1, 2 = draw
var time_over := false
var ko_happened := false

var events: Array = []      # this frame's events for audio/visuals (not saved)

# Match rules, fixed for the whole match (not saved; online both sides use the defaults).
var round_time := ROUND_TIME   # seconds per round, 0 = no time limit
var wins_needed := WINS_NEEDED
var training := false          # nobody gets KO'd; health refills once a combo is over


## opts (all optional): {"wins": 1..3, "time": seconds or 0, "training": bool}
func _init(c1: String, c2: String, opts := {}) -> void:
	f = [Fighter.new(0, c1), Fighter.new(1, c2)]
	wins_needed = clampi(int(opts.get("wins", WINS_NEEDED)), 1, 3)
	round_time = maxi(0, int(opts.get("time", ROUND_TIME)))
	training = bool(opts.get("training", false))
	start_match()


func start_match() -> void:
	round_num = 1
	match_winner = -1
	for fi in f:
		fi.wins = 0
		fi.score = 0
	start_round()


func start_round() -> void:
	var mid := STAGE_W / 2
	f[0].reset_round(mid - START_GAP, 1)
	f[1].reset_round(mid + START_GAP, -1)
	phase = INTRO
	pf = 0
	timer = round_time
	timer_frames = 0
	hitstop = 0
	round_winner = -1
	time_over = false
	ko_happened = false
	_update_cam()
	events.append({"t": "round", "n": round_num})


func save_state() -> Array:
	var a := []
	for k in SAVE_FIELDS:
		a.append(get(k))
	a.append(f[0].save())
	a.append(f[1].save())
	return a


func load_state(a: Array) -> void:
	for i in SAVE_FIELDS.size():
		set(SAVE_FIELDS[i], a[i])
	f[0].load_state(a[SAVE_FIELDS.size()])
	f[1].load_state(a[SAVE_FIELDS.size() + 1])


func step(i0: int, i1: int) -> void:
	events = []
	frame += 1
	pf += 1
	match phase:
		INTRO:
			if pf == 70:
				events.append({"t": "fight"})
			_tick(0, 0)
			if pf >= 100:
				phase = FIGHT
				pf = 0
		FIGHT:
			var counting := hitstop == 0
			_tick(i0, i1)
			if phase == FIGHT and counting and round_time > 0:
				_count_timer()
			if training:
				_refill()
		KO_SLOW:
			if pf % 2 == 0 or hitstop > 0:
				_tick(0, 0)
			if pf >= 90:
				phase = ROUND_END
				pf = 0
		ROUND_END:
			_tick(0, 0)
			if pf >= 30 and f[0].settled() and f[1].settled() \
					and f[0].state != Fighter.ATTACK and f[1].state != Fighter.ATTACK:
				_finish_round()
			elif pf >= 300:
				_finish_round()
		WIN_POSE:
			_tick(0, 0)
			if pf >= 160:
				if f[0].wins >= wins_needed or f[1].wins >= wins_needed:
					if f[0].wins >= wins_needed and f[1].wins >= wins_needed:
						match_winner = 2
					else:
						match_winner = 0 if f[0].wins >= wins_needed else 1
					phase = MATCH_OVER
					pf = 0
					events.append({"t": "match_over", "w": match_winner})
				else:
					round_num += 1
					start_round()
		MATCH_OVER:
			_tick(0, 0)


func _tick(i0: int, i1: int) -> void:
	f[0].inp = i0
	f[1].inp = i1
	if hitstop > 0:
		hitstop -= 1
		for fi in f:
			fi.read_buttons(false)
		return
	for fi in f:
		fi.read_buttons(true)
	f[0].think(f[1])
	f[1].think(f[0])
	for fi in f:
		fi.physics()
	_separate()
	_clamp()
	_separate_after_clamp()
	_update_cam()
	_hits()
	for fi in f:
		for e in fi.ev:
			e["slot"] = fi.slot
			events.append(e)
		fi.ev.clear()


## Training: health comes back to full as soon as a fighter is free to act again.
func _refill() -> void:
	for fi in f:
		if fi.state in [Fighter.IDLE, Fighter.WALK, Fighter.CROUCH, Fighter.AIR, Fighter.PREJUMP, Fighter.ATTACK] 				and fi.health > 0:
			fi.health = int(fi.data["health"])


func _count_timer() -> void:
	timer_frames += 1
	if timer_frames >= 60:
		timer_frames = 0
		timer -= 1
		if timer <= 0:
			timer = 0
			time_over = true
			var h0 := f[0].health
			var h1 := f[1].health
			round_winner = 0 if h0 > h1 else (1 if h1 > h0 else 2)
			phase = ROUND_END
			pf = 0
			events.append({"t": "time_over"})


func _finish_round() -> void:
	var w := round_winner
	if w == 0 or w == 2:
		f[0].wins += 1
	if w == 1 or w == 2:
		f[1].wins += 1
	for fi in f:
		if fi.state == Fighter.KO:
			continue
		if w == fi.slot:
			fi.set_state(Fighter.WIN)
			fi.score += timer * 100 + fi.health * 10
		else:
			fi.set_state(Fighter.LOSE)
		fi.vx = 0
	var perfect := w < 2 and f[w].health == int(f[w].data["health"])
	events.append({"t": "round_result", "w": w, "perfect": perfect})
	phase = WIN_POSE
	pf = 0


# ---------------------------------------------------------------- collisions

func _separate() -> void:
	var a := f[0]
	var b := f[1]
	var ov := _overlap(a, b)
	if ov <= 0:
		return
	var dir := signi(b.x - a.x)
	if dir == 0:
		dir = a.facing
	a.x -= dir * (ov / 2)
	b.x += dir * (ov - ov / 2)


func _separate_after_clamp() -> void:
	# If a wall/screen edge stopped one fighter, push the other one instead.
	var a := f[0]
	var b := f[1]
	var ov := _overlap(a, b)
	if ov <= 0:
		return
	var dir := signi(b.x - a.x)
	if dir == 0:
		dir = a.facing
	var lim := _limits()
	if (dir > 0 and a.x <= lim.x) or (dir < 0 and a.x >= lim.y):
		b.x += dir * ov
	else:
		a.x -= dir * ov
	_clamp()


func _overlap(a: Fighter, b: Fighter) -> int:
	var ya := a.push_span()
	var yb := b.push_span()
	if ya.y <= yb.x or yb.y <= ya.x:
		return 0
	var w: int = (int(a.data["push_w"]) + int(b.data["push_w"])) * SUB
	return w - absi(b.x - a.x)


func _limits() -> Vector2i:
	var lo := maxi(EDGE, cam_x + EDGE) * SUB
	var hi := mini(STAGE_W - EDGE, cam_x + SCREEN_W - EDGE) * SUB
	return Vector2i(lo, hi)


func _clamp() -> void:
	var lim := _limits()
	for fi in f:
		fi.x = clampi(fi.x, lim.x, lim.y)


func _update_cam() -> void:
	var mid := (f[0].x + f[1].x) / 2 / SUB
	cam_x = clampi(mid - SCREEN_W / 2, 0, STAGE_W - SCREEN_W)


func _hits() -> void:
	var h0 := _check(f[0], f[1])
	var h1 := _check(f[1], f[0])
	if h0.size() > 0:
		_apply(f[0], f[1], h0)
	if h1.size() > 0:
		_apply(f[1], f[0], h1)


func _check(att: Fighter, def: Fighter) -> Dictionary:
	if att.move_hit != 0 or not att.move_active():
		return {}
	var hb := att.hit_rect()
	for hr in def.hurt_rects():
		if hb.intersects(hr):
			var ix := hb.intersection(hr)
			return {"x": ix.position.x + ix.size.x / 2, "y": ix.position.y + ix.size.y / 2}
	return {}


func _apply(att: Fighter, def: Fighter, at: Dictionary) -> void:
	var m := att.hit_data()
	var strength: int = m["strength"]
	var dir := signi(def.x - att.x)
	if dir == 0:
		dir = att.facing
	if def.can_block(att, m):
		def.set_state(Fighter.BLOCKSTUN)
		def.stun = m["blockstun"]
		def.crouched = def.holds(Inp.DOWN)
		def.vx = 0
		att.move_hit = 2
		_push(att, def, m["push_block"], dir)
		hitstop = maxi(hitstop, int(m["hitstop"]) - 3)
		events.append({"t": "block", "s": strength, "x": at["x"], "y": at["y"], "slot": def.slot})
		return
	att.move_hit = 1
	var was_crouching := def.is_crouching()
	var was_air := def.airborne()
	var in_combo := def.state == Fighter.HITSTUN or def.state == Fighter.FALL
	def.combo = def.combo + 1 if in_combo else 1
	var dmg: int = int(m["damage"]) * clampi(11 - def.combo, 5, 10) / 10
	def.health = maxi(1 if training else 0, def.health - dmg)
	att.score += dmg * 10 + 100 * (def.combo - 1)
	def.guarding = false
	def.bounced = false
	if def.health <= 0:
		def.set_state(Fighter.KO)
		def.vy = 760
		def.vx = 300 * dir
		def.push_v = 0
		hitstop = 24
		ko_happened = true
		if att.state == Fighter.KO:
			round_winner = 2
		else:
			round_winner = att.slot
		phase = KO_SLOW
		pf = 0
		events.append({"t": "ko", "x": at["x"], "y": at["y"], "slot": def.slot})
	elif was_air:
		def.set_state(Fighter.FALL)
		def.fall_kd = strength == 2 or bool(m["kd"])
		def.vy = 520 if def.fall_kd else 420
		def.vx = 200 * dir
		def.push_v = 0
	elif m["kd"]:
		def.set_state(Fighter.FALL)
		def.fall_kd = true
		def.vy = 620
		def.vx = 230 * dir
		def.push_v = 0
	else:
		def.set_state(Fighter.HITSTUN)
		def.stun = m["hitstun"]
		def.crouched = was_crouching
		def.vx = 0
		_push(att, def, m["push_hit"], dir)
	hitstop = maxi(hitstop, int(m["hitstop"]))
	events.append({"t": "hit", "s": strength, "x": at["x"], "y": at["y"], "slot": def.slot,
			"combo": def.combo, "attacker": att.slot})


func _push(att: Fighter, def: Fighter, amount: int, dir: int) -> void:
	var v := amount * SUB * dir
	var lim := _limits()
	var cornered := (dir > 0 and def.x >= lim.y - 2 * SUB) or (dir < 0 and def.x <= lim.x + 2 * SUB)
	if cornered and not att.airborne():
		att.push_v = -v
	else:
		def.push_v = v
