class_name CpuBrain
extends RefCounted
## CPU opponent. Produces an input bitmask each frame, like a human pad.
## It reacts to what it "saw" a few frames ago, so it can be beaten.
## Held directions are committed for spans of frames (a pad doesn't flip every frame):
## flipping them frame to frame makes the fighter visibly tremble.

var slot := 1
var level := 1
var rng := RandomNumberGenerator.new()

var react := 10           # frames between something happening and the CPU "seeing" it
var block_rate := 0.7     # blocks an attack it sees coming
var guard_rate := 0.35    # holds guard in close range before anything happens
var aa_rate := 0.6        # anti-airs a jump-in
var aggression := 0.07    # chance per frame to attack when in range
var punish_rate := 0.5    # punishes a whiffed or blocked attack
var special_rate := 0.3   # uses its special move in the neutral game
var smart_guard := 0.8    # picks the right guard height (crouch vs low, stand vs overhead)

var _hist: Array = []
var _decided := {}        # per-event decisions ("atk<start frame>" -> bool), so they are not re-rolled
var _plan := "approach"
var _plan_t := 0
var _last := 0
var _hold_down := false
var _wait_back := false
var _queue: Array = []    # scripted inputs (special-move motions), one per frame
var _kd_from := -1        # frame the opponent was knocked down (-1 = not down)
var _poke_walk := false
var _air_from := -1       # frame the opponent left the ground (-1 = on the ground): one decision per jump
var _landed_at := -100    # frame the opponent last landed from a jump (they like to sweep right after)
var _blocked := 0         # how much the opponent has been blocking my attacks lately (0..4)
var _my_move_start := -1
var _op: Fighter = null   # this frame's opponent (for range checks)
var _op_lows := 0.0       # how much the opponent leans on low attacks lately (jumping beats that)
var _anti_aired := 0.0    # how often my jumps got hit lately (then stop jumping)
var _was_air := false  # frame my current attack started, to count each attack once


func _init(p_slot: int, p_level: int, seed_value: int) -> void:
	slot = p_slot
	level = clampi(p_level, 0, 2)
	rng.seed = seed_value
	react = [18, 10, 6][level]
	block_rate = [0.3, 0.7, 0.92][level]
	guard_rate = [0.2, 0.65, 0.85][level]
	aa_rate = [0.15, 0.65, 0.9][level]
	aggression = [0.03, 0.07, 0.1][level]
	punish_rate = [0.1, 0.5, 0.85][level]
	special_rate = [0.0, 0.35, 0.6][level]
	smart_guard = [0.4, 0.8, 0.97][level]


func get_input(sim: MatchSim) -> int:
	var me: Fighter = sim.f[slot]
	var op: Fighter = sim.f[1 - slot]
	_op = op
	_hist.append({"state": op.state, "move": op.move, "x": op.x, "y": op.y, "vy": op.vy,
			"sf": op.sf, "hit": op.move_hit, "frame": sim.frame})
	if _hist.size() > react:
		_hist.pop_front()
	if sim.phase != MatchSim.FIGHT:
		_last = 0
		_queue.clear()
		return 0
	var seen: Dictionary = _hist[0]
	var toward := Inp.RIGHT if op.x > me.x else Inp.LEFT
	var away := Inp.LEFT if toward == Inp.RIGHT else Inp.RIGHT
	var dist := absi(op.x - me.x) / 100
	var seen_dist := absi(int(seen["x"]) - me.x) / 100
	var seen_state: int = seen["state"]
	var seen_start := int(seen["frame"]) - int(seen["sf"])
	_track(sim, me, op)

	# A special-move motion in progress: finish it (unless something interrupted us).
	if not _queue.is_empty():
		if _can_act(me) or me.state == Fighter.ATTACK and me.on_path():
			var q: int = _queue.pop_front()
			return _finish(_dir_bits(q, toward, away))
		_queue.clear()

	# Punish: the opponent is stuck in the recovery of a whiffed or blocked attack.
	# (the same attack as seen, not a new one started since: that would mean attacking into it)
	if seen_state == Fighter.ATTACK and op.state == Fighter.ATTACK and _can_act(me) \
			and op.move == seen["move"] and op.sf >= int(seen["sf"]) \
			and seen["move"] != "" and op.moves.has(seen["move"]) and not op.is_air_move():
		var om: Dictionary = op.moves[seen["move"]]
		var recovering := not om.has("path") and int(seen["sf"]) >= int(om["startup"]) + int(om["active"])
		if recovering and int(seen["hit"]) != 1 and dist < _max_reach(me):
			var left := int(om["startup"]) + int(om["active"]) + int(om["recovery"]) - op.sf
			if _decide("pun%d" % seen_start, punish_rate):
				var a := _attack_for(me, dist, false, true, left)
				if a != 0:
					return _finish(a)

	# Defence: the opponent's projectile is coming (seen once it has flown `react` frames).
	# Crouch-guard: it blocks the spit and ducks under it while it still flies high.
	if op.pj_on and op.pj_t >= react and signi(me.x - op.pj_x) == signi(op.pj_vx) 			and absi(me.x - op.pj_x) / 100 < 120:
		if _decide("pj%d" % (sim.frame - op.pj_t), block_rate):
			return _finish(away | Inp.DOWN)

	# Defence: the opponent started an attack (as seen `react` frames ago).
	if seen_state == Fighter.ATTACK and seen_dist < 130 and not op.is_air_move():
		if _decide("atk%d" % seen_start, block_rate):
			return _finish(_guard(op, seen["move"], away, seen_start))

	# Anti-air: opponent jumping in. Once it reacts to a jump it sticks with it until the landing.
	var op_jumping := op.airborne() and op.state != Fighter.FALL and op.state != Fighter.KO
	if not op_jumping:
		_air_from = -1
	elif _air_from < 0:
		_air_from = sim.frame
	var key := "air%d" % _air_from
	if op_jumping and (_decided.has("on" + key) or (int(seen["y"]) > 0 and seen_dist < 120)):
		_decided["on" + key] = true
		if _decide(key, aa_rate) and _can_act(me):
			if _aa_connects(me, op):
				var b := _button(Inp.HP)
				if b != 0:
					return _finish(Inp.DOWN | b)
			if op.vy > 0 or dist > 70:
				return _finish(Inp.DOWN)   # crouch and wait for it to come down
		# no anti-air (or too late for one): stand guard against the jump attack
		if _decide("blk" + key, block_rate):
			return _finish(away)

	# The opponent just landed close: expect a low attack, crouch-guard a moment.
	if sim.frame - _landed_at < 14 and dist < _threat(op) and _can_act(me) and me.state != Fighter.ATTACK:
		if _decide("land%d" % _landed_at, block_rate):
			return _finish(Inp.DOWN | away)

	# My own jump: attack on the way down.
	# Pressed when the arc carries the kick/punch into the opponent (too early whiffs overhead).
	if me.state == Fighter.AIR and not me.air_attacked:
		for b in [Inp.HK, Inp.HP, Inp.MK]:
			var mv: Dictionary = me.moves["j_" + Inp.BUTTON_NAMES[Inp.BUTTONS.find(b)]]
			if _air_connects(me, op, mv):
				return _finish(_button(b))

	# Follow up when the opponent is reeling.
	if op.state == Fighter.HITSTUN and dist < 48 and _can_act(me):
		var c := _attack_for(me, dist, true, false)
		if c != 0:
			return _finish(c)

	# Opponent knocked down: walk up and wait (decided once per knockdown).
	var op_down := op.state == Fighter.FALL or op.state == Fighter.LIE or op.state == Fighter.GETUP
	if not op_down:
		_kd_from = -1
	elif _kd_from < 0:
		_kd_from = sim.frame
	if op_down:
		# walk up to 60 px, then stay put until it is past 100 again (no stop-start flicker)
		var kd := "kd%d" % _kd_from
		if _decided.get("near" + kd, false) and dist > 100:
			_decided["near" + kd] = false
		if not _decided.get("near" + kd, false):
			if dist > 60:
				return _finish(toward)
			_decided["near" + kd] = true
		if _decide(kd, guard_rate + 0.3):
			return _finish(Inp.DOWN | away)   # meaty guard for the wake-up
		return _finish(0)

	# Neutral game.
	_plan_t -= 1
	if _plan_t <= 0:
		_choose_plan(me, dist)
	var out := 0
	match _plan:
		"approach":
			out = toward
			# the opponent outranges me here: don't stroll into it, guard and wait for a whiff
			if dist <= _threat(op) and dist >= _max_reach(me) and _hold_down and op.state != Fighter.ATTACK:
				_plan = "wait"
				_plan_t = 15 + rng.randi() % 20
				out = Inp.DOWN | away
			elif dist < _max_reach(me) and rng.randf() < aggression * 3.0:
				out = _or_keep(out, _attack_for(me, dist, false, false))
		"poke":
			# walk in until well inside reach, stop, walk again only once clearly out of it
			var reach := _max_reach(me)
			if dist >= reach + 6:
				_poke_walk = true
			elif dist < reach - 6:
				_poke_walk = false
			if _poke_walk:
				out = toward
			elif _hold_down:
				out = Inp.DOWN | away   # guard and poke from a crouch
			if dist < _max_reach(me) and rng.randf() < aggression * 2.0:
				out = _or_keep(out, _attack_for(me, dist, false, false))
		"retreat":
			out = away | (Inp.DOWN if _hold_down and dist <= _threat(op) else 0)
		"wait":
			if _hold_down or dist <= _threat(op):
				out = Inp.DOWN | away   # standing back does not block sweeps
			elif _wait_back:
				out = away
		"jump":
			if me.state == Fighter.IDLE or me.state == Fighter.WALK:
				out = Inp.UP | toward
				_plan = "approach"
				_plan_t = 30
		"special":
			_plan = "approach"
			_plan_t = 20
			if _can_act(me) and me.state != Fighter.ATTACK:
				_start_special(me)
				if not _queue.is_empty():
					return _finish(_dir_bits(_queue.pop_front(), toward, away))
	return _finish(out)


func _choose_plan(me: Fighter, dist: int) -> void:
	var r := rng.randf()
	_hold_down = rng.randf() < guard_rate
	_wait_back = rng.randf() < 0.5
	var specials: Array = me.data.get("specials", [])
	var sp_range: Array = specials[0].get("range", [70, 140]) if not specials.is_empty() else [0, 0]
	var sp_ready: bool = not specials.is_empty() and not (me.pj_on and me.moves[specials[0]["move"]].has("proj"))
	# a projectile is the zoner's main tool from range: thrown more often than a rush-in special
	var sp_rate := special_rate * (1.0 if sp_ready and me.moves[specials[0]["move"]].has("proj") else 0.5)
	if sp_ready and dist > int(sp_range[0]) and dist < int(sp_range[1]) and rng.randf() < sp_rate:
		_plan = "special"
	elif level > 0 and dist > 70 and dist < 125 and rng.randf() < _jump_in_chance():
		_plan = "jump"   # the opponent keeps blocking / sweeping low and doesn't anti-air: go over the top
	elif dist > 140:
		_plan = "approach" if r < 0.75 else ("jump" if r < 0.85 else "wait")
	elif dist > 70:
		if r < 0.45 + level * 0.05:
			_plan = "approach"
		elif r < 0.6 + level * 0.07:
			_plan = "jump"
		elif r < 0.85:
			_plan = "wait"
		else:
			_plan = "retreat"
	else:
		if r < 0.5 + level * 0.1:
			_plan = "poke"
		elif r < 0.85:
			_plan = "wait"
		else:
			_plan = "retreat"
	_plan_t = 20 + rng.randi() % 40


## Chance to pick a jump-in over the other plans: grows when the opponent sticks to the ground
## (sweeps, blocks low) and shrinks when it anti-airs me.
func _jump_in_chance() -> float:
	var c := 0.08 * minf(_op_lows, 3.0) + (0.15 if _blocked >= 2 else 0.0)
	c -= 0.12 * _anti_aired
	return clampf(c, 0.0, 0.25 + 0.1 * level)


## Rolls once per event key and remembers it; old keys are dropped.
func _decide(key: String, rate: float) -> bool:
	if not _decided.has(key):
		if _decided.size() > 16:
			_decided.clear()
		_decided[key] = rng.randf() < rate
	return _decided[key]


## Guard input against an attack: crouch unless it must be blocked standing.
func _guard(op: Fighter, mv: String, away: int, start: int) -> int:
	var high := mv.begins_with("j_")
	if op.moves.has(mv):
		high = int(op.moves[mv]["guard"]) == CharData.Guard.HIGH
	var stand := high
	if not _decide("gh%d" % start, smart_guard):
		stand = not stand
	return away if stand else (away | Inp.DOWN)


## Queues the motion of the fighter's special move (down, down-forward, forward + button).
func _start_special(me: Fighter) -> void:
	for sp in me.data.get("specials", []):
		if sp["motion"] == "qcf":
			var b: int = Inp.BUTTONS[int(sp["buttons"][0])]
			# 1 = forward, -1 = back in _dir_bits
			_queue = [Inp.DOWN, Inp.DOWN, Inp.DOWN | 1 << 16, Inp.DOWN | 1 << 16, 1 << 16, (1 << 16) | b]
			return


## Turns queued inputs (bit 16 = "forward") into screen directions.
func _dir_bits(q: int, toward: int, _away: int) -> int:
	var out := q & ~(1 << 16)
	if q & (1 << 16):
		out |= toward
	return out


## Remembers when the opponent lands from a jump, and whether my attacks keep getting blocked.
func _track(sim: MatchSim, me: Fighter, op: Fighter) -> void:
	if op.state == Fighter.LAND and op.sf <= 1 and not op.fall_kd:
		_landed_at = sim.frame
	if me.state == Fighter.ATTACK:
		var start := sim.frame - me.sf
		if me.move_hit != 0 and start != _my_move_start:
			_my_move_start = start
			_blocked = mini(4, _blocked + 1) if me.move_hit == 2 else maxi(0, _blocked - 2)
	if op.state == Fighter.ATTACK and op.sf == 1 and op.moves.has(op.move) 			and int(op.moves[op.move]["guard"]) == CharData.Guard.LOW:
		_op_lows = minf(4.0, _op_lows + 1.0)
	var in_air := me.airborne() or me.state == Fighter.FALL
	if _was_air and (me.state == Fighter.FALL or me.state == Fighter.KO) and me.sf <= 1:
		_anti_aired = minf(4.0, _anti_aired + 1.5)
	_was_air = in_air and me.state != Fighter.FALL
	_op_lows = maxf(0.0, _op_lows - 0.004)       # fades over ~4 s per point
	_anti_aired = maxf(0.0, _anti_aired - 0.003)


## How far the opponent's ground attacks reach me (px between us), with a small margin.
func _threat(op: Fighter) -> int:
	return _max_reach(op) + 6


## Would my crouching heavy punch (anti-air) meet the jumping opponent if pressed now?
## Follows the jump arc forward through the move's active frames.
func _aa_connects(me: Fighter, op: Fighter) -> bool:
	var m: Dictionary = me.moves["cr_hp"]
	var s: int = m["startup"]
	var g: int = op.data["gravity"]
	var hb: Rect2i = me.box_to_world(m["box"])
	if (op.x > me.x) != (me.facing == 1):
		return false   # it would cross over me
	for k in range(s, s + int(m["active"])):
		var ox: int = op.x + op.vx * k
		var oy: int = op.y + op.vy * k - g * k * (k - 1) / 2
		if oy <= 0:
			return false   # lands first
		var hu: Array = op.data["hurt_air"]
		var bx: int = hu[0]
		var bw: int = hu[2]
		var wx: int = ox / 100 + (bx if op.facing == 1 else -bx - bw)
		if hb.intersects(Rect2i(wx, oy / 100 + int(hu[1]), bw, hu[3])):
			return true
	return false


## Would this move's hit box touch the opponent's hurt boxes where they stand now?
## (A ground opponent; the CPU judges range like a player who knows the move.)
func _connects(me: Fighter, op: Fighter, m: Dictionary) -> bool:
	var hb: Rect2i = me.box_to_world(m["box"])
	hb = hb.grow_individual(0, 0, -1, 0) if me.facing == 1 else hb.grow_individual(-1, 0, 0, 0)
	var hu: Array = op.data["hurt_crouch"] if op.is_crouching() else op.data["hurt_stand"]
	var bx: int = hu[0]
	var bw: int = hu[2]
	var wx: int = op.px() + (bx if op.facing == 1 else -bx - bw)
	return hb.intersects(Rect2i(wx, op.y / 100 + int(hu[1]), bw, hu[3]))


## Would this jump attack, pressed now, hit the (grounded) opponent during its active frames?
func _air_connects(me: Fighter, op: Fighter, m: Dictionary) -> bool:
	if op.airborne():
		return false
	var s: int = m["startup"]
	var g: int = me.data["gravity"]
	var hu: Array = op.data["hurt_crouch"] if op.is_crouching() else op.data["hurt_stand"]
	var ux: int = op.px() + (int(hu[0]) if op.facing == 1 else -int(hu[0]) - int(hu[2]))
	var hurt := Rect2i(ux, int(hu[1]), hu[2], hu[3])
	var b: Array = m["box"]
	for k in range(s, s + int(m["active"])):
		var my: int = me.y + me.vy * k - g * k * (k - 1) / 2
		if my <= 0:
			return false
		var mx: int = (me.x + me.vx * k) / 100
		var wx: int = mx + (int(b[0]) if me.facing == 1 else -int(b[0]) - int(b[2]))
		if Rect2i(wx, my / 100 + int(b[1]), b[2], b[3]).intersects(hurt):
			return true
	return false


func _can_act(me: Fighter) -> bool:
	return me.state == Fighter.IDLE or me.state == Fighter.WALK or me.state == Fighter.CROUCH \
			or (me.state == Fighter.ATTACK and me.move_hit != 0)


func _max_reach(me: Fighter) -> int:
	var best := 0
	for k in me.moves:
		if (k as String).begins_with("j_") or me.moves[k].has("path") or me.moves[k].has("proj"):
			continue
		var b: Array = me.moves[k]["box"]
		best = maxi(best, int(b[0]) + int(b[2]))
	return best + 10


## An attack input, or `keep` when there is none to press this frame.
func _or_keep(keep: int, attack: int) -> int:
	return attack if attack != 0 else keep


## Picks a ground attack that reaches `dist` (0 = none, or its button is still held).
## `max_startup`: only moves that come out in time (punishing a recovery of that many frames).
func _attack_for(me: Fighter, dist: int, combo: bool, punish: bool, max_startup := 99) -> int:
	var op: Fighter = _op
	var options: Array = []
	for k in me.moves:
		var mname: String = k
		if mname.begins_with("j_") or me.moves[mname].has("path") or me.moves[mname].has("proj"):
			continue   # specials are done by plan ("special"), not as normals
		var m: Dictionary = me.moves[mname]
		var b: Array = m["box"]
		if int(m["startup"]) >= max_startup:
			continue
		if op != null and not op.airborne():
			if not _connects(me, op, m):
				continue
		elif int(b[0]) + int(b[2]) + 10 < dist:
			continue
		var w := 1.0
		var strength: int = m["strength"]
		if combo:
			w = 3.0 if strength == 0 else (1.5 if strength == 1 else 0.6)
		elif punish:
			w = 0.5 if strength == 0 else (1.0 if strength == 1 else 2.5)
		elif strength == 2:
			w = 0.6 + level * 0.3
		if mname == "cr_hk" and not combo:
			# the sweep is a great punish but unsafe when blocked: less of it vs a blocker
			w *= 1.4 if punish else (1.0 if _blocked < 2 else 0.3)
		options.append([mname, w])
	if options.is_empty():
		return 0
	var total := 0.0
	for o in options:
		total += o[1]
	var pick := rng.randf() * total
	for o in options:
		pick -= o[1]
		if pick <= 0.0:
			return _move_input(o[0])
	return _move_input(options[0][0])


func _move_input(mname: String) -> int:
	var idx := Inp.BUTTON_NAMES.find(mname.substr(3))
	var bits := _button(Inp.BUTTONS[idx])
	if bits == 0:
		return 0
	if mname.begins_with("cr_"):
		bits |= Inp.DOWN
	return bits


## Returns the button bit, unless it is still held from last frame (needs a release first).
func _button(b: int) -> int:
	if (_last & b) != 0:
		return 0
	return b


func _finish(out: int) -> int:
	_last = out
	return out
