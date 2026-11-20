extends SceneTree
## Headless sanity test: CPU vs CPU matches + rollback determinism check.
## Run: godot --headless --path . --script res://tests/simtest.gd


func _init() -> void:
	var ok := true
	var pairs := [["ced", "kros"], ["kros", "ced"], ["ced", "ced"], ["kros", "kros"],
		["murfurrie", "ced"], ["kros", "murfurrie"], ["murfurrie", "murfurrie"],
		["shorty", "ced"], ["kros", "shorty"], ["shorty", "murfurrie"], ["shorty", "shorty"]]
	for p in pairs:
		for lvl in 3:
			var r := _play(p[0], p[1], lvl, 1234 + lvl)
			print("%s vs %s lvl %d -> winner %d rounds %d frames %d hits %d blocks %d kos %d timeouts %d" % [
				p[0], p[1], lvl, r.winner, r.rounds, r.frames, r.hits, r.blocks, r.kos, r.timeouts])
			if r.frames >= 60 * 60 * 8:
				print("  !! match did not finish")
				ok = false
	ok = _determinism() and ok
	ok = _sprite_timing() and ok
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _play(c1: String, c2: String, lvl: int, seed_value: int) -> Dictionary:
	var sim := MatchSim.new(c1, c2)
	var a := CpuBrain.new(0, lvl, seed_value)
	var b := CpuBrain.new(1, lvl, seed_value + 99)
	var r := {"hits": 0, "blocks": 0, "kos": 0, "timeouts": 0, "frames": 0, "rounds": 0, "winner": -1}
	while sim.phase != MatchSim.MATCH_OVER and r.frames < 60 * 60 * 8:
		sim.step(a.get_input(sim), b.get_input(sim))
		r.frames += 1
		for e in sim.events:
			match e["t"]:
				"hit": r.hits += 1
				"block": r.blocks += 1
				"ko": r.kos += 1
				"time_over": r.timeouts += 1
				"round_result": r.rounds += 1
	r.winner = sim.match_winner
	return r


## Save state mid-match, run ahead, restore, re-run with same inputs: must match.
func _determinism() -> bool:
	var sim := MatchSim.new("ced", "kros")
	var a := CpuBrain.new(0, 2, 5)
	var b := CpuBrain.new(1, 2, 6)
	var inputs: Array = []
	for i in 900:
		var i0 := a.get_input(sim)
		var i1 := b.get_input(sim)
		sim.step(i0, i1)
	var snap := sim.save_state()
	for i in 600:
		var i0 := a.get_input(sim)
		var i1 := b.get_input(sim)
		inputs.append([i0, i1])
		sim.step(i0, i1)
	var end1 := str(sim.save_state())
	sim.load_state(snap)
	for io in inputs:
		sim.step(io[0], io[1])
	var end2 := str(sim.save_state())
	print("determinism (save/restore/replay): ", "OK" if end1 == end2 else "MISMATCH")
	return end1 == end2


## Sprite moves are synced to frame data (SpriteSet.attack_index): the hit pose (the widest
## frames) must be on screen exactly on the active frames, wind-up before, pulled back after.
func _sprite_timing() -> bool:
	var ok := true
	for skin in [["ced", "ced"], ["kros", "kros"], ["kros", "kros_nocape"], ["murfurrie", "murfurrie"]]:
		var moves: Dictionary = CharData.get_data(skin[0])["moves"]
		var ss := SpriteSet.load_for(skin[1])
		if ss == null:
			continue
		for mname in moves:
			var m: Dictionary = moves[mname]
			if not ss.has(mname) or m.has("path"):
				continue
			var s: int = m["startup"]
			var a: int = m["active"]
			var total := s + a + maxi(1, int(m["recovery"]))
			var h := ss.hit_span(mname)
			var shown := ""
			var good := h.x >= 1
			for f in total:
				var i := ss.attack_index(mname, f, s, a, total)
				var on_hit := i >= h.x and i <= h.y
				shown += "#" if on_hit else ("w" if i < h.x else "r")
				if f < s and on_hit: good = false
				if f >= s and f < s + a and not on_hit: good = false
				if f >= s + a + SpriteSet.HIT_HOLD and on_hit: good = false
			print("sprite timing %s %s %s %s" % [skin[1], mname, shown, "OK" if good else "BAD"])
			ok = ok and good
	return ok
