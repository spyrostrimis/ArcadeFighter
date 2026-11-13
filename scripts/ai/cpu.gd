class_name CpuBrain
extends RefCounted
## CPU opponent. Produces an input bitmask each frame, like a human pad.
## It reacts to what it "saw" a few frames ago, so it can be beaten.

var slot := 1
var level := 1
var rng := RandomNumberGenerator.new()

var react := 12
var block_rate := 0.65
var aa_rate := 0.5
var aggression := 0.06

var _hist: Array = []
var _decided := {}
var _plan := "approach"
var _plan_t := 0
var _press := 0          # button bit to press next frame (after a release)
var _last := 0
var _hold_down := false


func _init(p_slot: int, p_level: int, seed_value: int) -> void:
	slot = p_slot
	level = clampi(p_level, 0, 2)
	rng.seed = seed_value
	react = [20, 12, 7][level]
	block_rate = [0.25, 0.6, 0.88][level]
	aa_rate = [0.12, 0.45, 0.8][level]
	aggression = [0.025, 0.05, 0.08][level]


func get_input(sim: MatchSim) -> int:
	var me: Fighter = sim.f[slot]
	var op: Fighter = sim.f[1 - slot]
	_hist.append({"state": op.state, "move": op.move, "x": op.x, "y": op.y, "vy": op.vy,
			"sf": op.sf, "frame": sim.frame})
	if _hist.size() > react:
		_hist.pop_front()
	if sim.phase != MatchSim.FIGHT:
		_last = 0
		return 0
	var seen: Dictionary = _hist[0]
	var toward := Inp.RIGHT if op.x > me.x else Inp.LEFT
	var away := Inp.LEFT if toward == Inp.RIGHT else Inp.RIGHT
	var dist := absi(op.x - me.x) / 100
	var seen_dist := absi(int(seen["x"]) - me.x) / 100
	var out := 0

	# Defence: the opponent started an attack (as seen `react` frames ago).
	var seen_state: int = seen["state"]
	if seen_state == Fighter.ATTACK and seen_dist < 120:
		var start: int = int(seen["frame"]) - int(seen["sf"])
		var key := "atk%d" % start
		if not _decided.has(key):
			_decided = {key: rng.randf() < block_rate}
		if _decided[key]:
			out |= away
			var mv: String = seen["move"]
			if mv.begins_with("cr_") or (mv.begins_with("st_") and rng.randf() < 0.3 and level > 0):
				out |= Inp.DOWN
			if mv.begins_with("j_"):
				out &= ~Inp.DOWN
			return _finish(out)

	# Anti-air: opponent jumping in.
	var seen_y: int = seen["y"]
	if seen_y > 0 and seen_dist < 110 and op.airborne():
		var key2 := "air%d" % (int(seen["frame"]) - int(seen["sf"]))
		if not _decided.has(key2):
			_decided = {key2: rng.randf() < aa_rate}
		if _decided[key2]:
			if op.vy < 0 and dist < 64 and op.y < 70 * 100:
				return _finish(Inp.DOWN | _button(Inp.HP))
			return _finish(Inp.DOWN if dist > 64 else 0)
		return _finish(away)

	# My own jump: attack on the way down.
	if me.state == Fighter.AIR and not me.air_attacked and me.vy < 0 and dist < 60:
		return _finish(_button([Inp.HK, Inp.HP, Inp.MK][rng.randi() % 3]))

	# Follow up when the opponent is reeling.
	if op.state == Fighter.HITSTUN and dist < 56 and _can_act(me):
		return _finish(_attack_for(me, dist, true))

	# Opponent knocked down: walk up and wait.
	if op.state == Fighter.FALL or op.state == Fighter.LIE or op.state == Fighter.GETUP:
		if dist > 60:
			return _finish(toward)
		return _finish(away if rng.randf() < 0.3 else 0)

	# Neutral game.
	_plan_t -= 1
	if _plan_t <= 0:
		_choose_plan(dist)
	match _plan:
		"approach":
			out |= toward
			if dist < _max_reach(me) and rng.randf() < aggression * 3.0:
				out = _attack_for(me, dist, false)
		"poke":
			if dist < _max_reach(me) and rng.randf() < aggression * 2.0:
				out = _attack_for(me, dist, false)
			elif dist >= _max_reach(me):
				out |= toward
		"retreat":
			out |= away
		"wait":
			if _hold_down:
				out |= Inp.DOWN | away
			elif rng.randf() < 0.5:
				out |= away
		"jump":
			if me.state == Fighter.IDLE or me.state == Fighter.WALK:
				out |= Inp.UP | toward
				_plan = "approach"
				_plan_t = 30
	return _finish(out)


func _choose_plan(dist: int) -> void:
	var r := rng.randf()
	_hold_down = rng.randf() < 0.4
	if dist > 140:
		_plan = "approach" if r < 0.75 else ("jump" if r < 0.85 else "wait")
	elif dist > 70:
		if r < 0.45:
			_plan = "approach"
		elif r < 0.45 + 0.1 + level * 0.05:
			_plan = "jump"
		elif r < 0.8:
			_plan = "wait"
		else:
			_plan = "retreat"
	else:
		if r < 0.55:
			_plan = "poke"
		elif r < 0.75:
			_plan = "wait"
		else:
			_plan = "retreat"
	_plan_t = 20 + rng.randi() % 40


func _can_act(me: Fighter) -> bool:
	return me.state == Fighter.IDLE or me.state == Fighter.WALK or me.state == Fighter.CROUCH \
			or (me.state == Fighter.ATTACK and me.move_hit != 0)


func _max_reach(me: Fighter) -> int:
	var best := 0
	for k in me.moves:
		if (k as String).begins_with("j_"):
			continue
		var b: Array = me.moves[k]["box"]
		best = maxi(best, int(b[0]) + int(b[2]))
	return best + 10


## Picks a ground attack that reaches `dist`.
func _attack_for(me: Fighter, dist: int, combo: bool) -> int:
	var options: Array = []
	for k in me.moves:
		var mname: String = k
		if mname.begins_with("j_"):
			continue
		var m: Dictionary = me.moves[mname]
		var b: Array = m["box"]
		var reach := int(b[0]) + int(b[2]) + 10
		if reach < dist:
			continue
		var w := 1.0
		var strength: int = m["strength"]
		if combo:
			w = 3.0 if strength == 0 else (1.5 if strength == 1 else 0.6)
		elif strength == 2:
			w = 0.6 + level * 0.3
		if mname == "cr_hk":
			w *= 1.4
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
