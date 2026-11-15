extends SceneTree
## Headless balance check: many seeded CED vs KROS CPU matches, both sides, all levels.
## Prints win rates and which moves deal the damage.
## Run: godot --headless --path . --script res://tests/balance_test.gd [-- --n=100 --lvl=2]
## Try a change without editing char_data: -- --p=ced.cr_hk.startup=8 --p=kros.cr_hk.boxw=58

var n := 100
var levels := [0, 1, 2]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--lvl="):
			levels = [int(a.substr(6))]
		elif a.begins_with("--p="):   # experiment: --p=ced.cr_hk.startup=8 / boxw=52 / recovery=25
			var kv := a.substr(4).split("=")
			var path := kv[0].split(".")
			var mv: Dictionary = CharData.get_data(path[0])["moves"][path[1]]
			if path[2] == "boxw":
				mv["box"][2] = int(kv[1])
			else:
				mv[path[2]] = int(kv[1])
	var ok := true
	var total_ced := 0
	var total := 0
	for lvl in levels:
		var wins := {"ced": 0, "kros": 0, "draw": 0}
		var rounds := {"ced": 0, "kros": 0}
		var hp_left := {"ced": 0, "kros": 0}
		var dmg := {"ced": {}, "kros": {}}
		var timeouts := 0
		for i in n:
			# alternate sides so slot 0/1 has no say
			var ced_slot := i % 2
			var c := ["ced", "kros"] if ced_slot == 0 else ["kros", "ced"]
			var r := _play(c[0], c[1], lvl, 9000 + i * 7 + lvl * 1000, dmg)
			timeouts += r.timeouts
			rounds["ced"] += r.wins[ced_slot]
			rounds["kros"] += r.wins[1 - ced_slot]
			if r.winner == 2:
				wins["draw"] += 1
			elif r.winner == ced_slot:
				wins["ced"] += 1
			else:
				wins["kros"] += 1
			hp_left["ced"] += r.hp_sum[ced_slot]
			hp_left["kros"] += r.hp_sum[1 - ced_slot]
		total_ced += wins["ced"]
		total += n
		print("lvl %d: CED %d  KROS %d  draw %d   rounds CED %d KROS %d   timeouts %d" % [
			lvl, wins["ced"], wins["kros"], wins["draw"], rounds["ced"], rounds["kros"], timeouts])
		for cid in ["ced", "kros"]:
			var rows: Array = []
			var sum := 0
			for k in dmg[cid]:
				rows.append([k, dmg[cid][k][0], dmg[cid][k][1]])
				sum += dmg[cid][k][0]
			rows.sort_custom(func(p, q): return p[1] > q[1])
			var s := "  %s dmg %d:" % [cid.to_upper(), sum]
			for row in rows.slice(0, 8):
				s += " %s %d%%(%d)" % [row[0], row[1] * 100 / maxi(1, sum), row[2]]
			print(s)
	var rate := float(total_ced) / maxf(1.0, total)
	print("CED match win rate overall: %.0f%%" % (rate * 100.0))
	# Fail when one side is clearly stronger (CPU vs CPU should be close to even).
	ok = rate >= 0.35 and rate <= 0.65
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _play(c1: String, c2: String, lvl: int, seed_value: int, dmg: Dictionary) -> Dictionary:
	var sim := MatchSim.new(c1, c2)
	var a := CpuBrain.new(0, lvl, seed_value)
	var b := CpuBrain.new(1, lvl, seed_value + 99)
	var r := {"timeouts": 0, "winner": -1, "wins": [0, 0], "hp_sum": [0, 0]}
	var frames := 0
	var prev_hp := [sim.f[0].health, sim.f[1].health]
	while sim.phase != MatchSim.MATCH_OVER and frames < 60 * 60 * 8:
		sim.step(a.get_input(sim), b.get_input(sim))
		frames += 1
		for e in sim.events:
			if e["t"] == "time_over":
				r.timeouts += 1
			elif e["t"] == "round_result":
				r.hp_sum[0] += sim.f[0].health
				r.hp_sum[1] += sim.f[1].health
			elif e["t"] == "hit":
				var att: Fighter = sim.f[int(e["attacker"])]
				var def: Fighter = sim.f[1 - int(e["attacker"])]
				var lost: int = prev_hp[def.slot] - def.health
				var d: Dictionary = dmg[att.cid]
				var mv: String = att.move if att.state == Fighter.ATTACK else "?"
				if not d.has(mv):
					d[mv] = [0, 0]
				d[mv][0] += maxi(0, lost)
				d[mv][1] += 1
		prev_hp = [sim.f[0].health, sim.f[1].health]
	r.winner = sim.match_winner
	r.wins = [sim.f[0].wins, sim.f[1].wins]
	return r
