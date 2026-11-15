extends SceneTree
## How hard is the CPU for a person? Plays it against scripted "player" bots that use the
## cheap tactics a human finds quickly, and prints the CPU's win rate against each.
## Run: godot --headless --path . --script res://tests/cpu_strength.gd [-- --n=20 --lvl=1]

const BOTS := ["sweeper", "jumper", "turtle", "rushdown", "masher"]

var n := 20
var levels := [0, 1, 2]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--lvl="):
			levels = [int(a.substr(6))]
	for lvl in levels:
		var line := "lvl %d:" % lvl
		var total := 0
		for bot in BOTS:
			var wins := 0
			for i in n:
				var cpu_cid: String = ["ced", "kros"][i % 2]
				var bot_cid: String = ["ced", "kros"][(i / 2) % 2]
				var cpu_slot := (i / 4) % 2
				wins += 1 if _play(bot, bot_cid, cpu_cid, cpu_slot, lvl, 500 + i * 13) else 0
			total += wins
			line += "  %s %d%%" % [bot, wins * 100 / n]
		print(line, "   | overall CPU wins %d%%" % (total * 100 / (n * BOTS.size())))
	quit()


## True when the CPU wins the match.
func _play(bot: String, bot_cid: String, cpu_cid: String, cpu_slot: int, lvl: int, seed_value: int) -> bool:
	var c := [bot_cid, cpu_cid] if cpu_slot == 1 else [cpu_cid, bot_cid]
	var sim := MatchSim.new(c[0], c[1])
	var cpu := CpuBrain.new(cpu_slot, lvl, seed_value)
	var p := Bot.new(bot, 1 - cpu_slot, seed_value + 7)
	var frames := 0
	while sim.phase != MatchSim.MATCH_OVER and frames < 60 * 60 * 8:
		var ic := cpu.get_input(sim)
		var ib := p.get_input(sim)
		if cpu_slot == 0:
			sim.step(ic, ib)
		else:
			sim.step(ib, ic)
		frames += 1
	return sim.match_winner == cpu_slot


## A scripted player. Reacts to what it saw 12 frames ago (human-ish), never randomly flips.
class Bot:
	var kind := ""
	var slot := 0
	var rng := RandomNumberGenerator.new()
	var last := 0
	var t := 0
	var hist: Array = []

	func _init(k: String, s: int, seed_value: int) -> void:
		kind = k
		slot = s
		rng.seed = seed_value

	func get_input(sim: MatchSim) -> int:
		var me: Fighter = sim.f[slot]
		var op: Fighter = sim.f[1 - slot]
		hist.append([op.state, op.sf, op.move])
		if hist.size() > 12:
			hist.pop_front()
		t += 1
		if sim.phase != MatchSim.FIGHT:
			last = 0
			return 0
		var fwd := Inp.RIGHT if op.x > me.x else Inp.LEFT
		var back := Inp.LEFT if fwd == Inp.RIGHT else Inp.RIGHT
		var dist := absi(op.x - me.x) / 100
		var sweep_reach: int = int(me.moves["cr_hk"]["box"][0]) + int(me.moves["cr_hk"]["box"][2])
		var seen: Array = hist[0]
		var op_recovering := false
		if seen[0] == Fighter.ATTACK and op.state == Fighter.ATTACK and op.moves.has(seen[2]):
			var m: Dictionary = op.moves[seen[2]]
			op_recovering = not m.has("path") and int(seen[1]) >= int(m["startup"]) + int(m["active"])
		var out := 0
		match kind:
			"sweeper":   # walk in, sweep at max range, crouch-block otherwise
				if op_recovering and dist <= sweep_reach:
					out = Inp.DOWN | _press(Inp.HK)
				elif dist > sweep_reach - 2:
					out = fwd
				elif t % 40 < 3:
					out = Inp.DOWN | _press(Inp.HK)
				else:
					out = Inp.DOWN | back
			"jumper":    # jump in with heavy kick, sweep on landing
				if me.state == Fighter.AIR and me.vy < 0 and dist < 60:
					out = _press(Inp.HK)
				elif me.state == Fighter.LAND or (dist < 40 and t % 20 < 2):
					out = Inp.DOWN | _press(Inp.HK)
				elif dist < 150:
					out = Inp.UP | fwd
				else:
					out = fwd
			"turtle":    # crouch-block everything, punish recovery, poke
				if op_recovering and dist <= sweep_reach:
					out = Inp.DOWN | _press(Inp.HK)
				elif dist < 50 and t % 50 < 2:
					out = Inp.DOWN | _press(Inp.MK)
				elif dist > 120:
					out = fwd
				else:
					out = Inp.DOWN | back
			"rushdown":  # walk in, low light chain, sweep
				if dist > 40:
					out = fwd
				else:
					var k := t % 24
					if k < 2: out = Inp.DOWN | _press(Inp.LK)
					elif k >= 6 and k < 8: out = Inp.DOWN | _press(Inp.LP)
					elif k >= 12 and k < 14: out = Inp.DOWN | _press(Inp.HK)
					else: out = Inp.DOWN | back
			"masher":    # random buttons, walking forward
				out = fwd
				if t % 6 == 0:
					out = _press(Inp.BUTTONS[rng.randi() % 6]) | (Inp.DOWN if rng.randf() < 0.5 else 0)
		last = out
		return out

	func _press(b: int) -> int:
		return 0 if (last & b) != 0 else b
