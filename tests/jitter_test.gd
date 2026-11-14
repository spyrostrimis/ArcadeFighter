extends SceneTree
## Headless "trembling" detector: CPU vs CPU matches, counts how often a fighter's
## visible pose flips A -> B -> A within a few frames (looks like shaking on screen).
## Run: godot --headless --path . --script res://tests/jitter_test.gd

const NAMES := ["IDLE", "WALK", "CROUCH", "PREJUMP", "AIR", "LAND", "ATTACK", "HITSTUN",
		"BLOCKSTUN", "FALL", "LIE", "GETUP", "KO", "WIN", "LOSE"]
const GAP := 3   # B lasting this many frames or fewer between two A's counts as a flicker


## What the player sees: the pose (state + guard + walk direction + facing).
static func pose_key(fi: Fighter) -> String:
	var k: String = NAMES[fi.state]
	match fi.state:
		Fighter.IDLE, Fighter.CROUCH:
			if fi.guarding: k += "+guard"
		Fighter.WALK:
			k += "+guard" if fi.guarding else ("_f" if fi.vx * fi.facing > 0 else "_b")
		Fighter.ATTACK:
			k += ":" + fi.move
	return k + ("" if fi.facing == 1 else " <")


func _init() -> void:
	var total := 0
	var frames := 0
	var kinds := {}
	for p in [["ced", "kros"], ["kros", "ced"]]:
		for lvl in 3:
			var r := _play(p[0], p[1], lvl, 4321 + lvl, kinds)
			total += r[0]
			frames += r[1]
			print("%s vs %s lvl %d: %d flickers in %d frames" % [p[0], p[1], lvl, r[0], r[1]])
	var ks := kinds.keys()
	ks.sort_custom(func(a, b): return kinds[a] > kinds[b])
	for k in ks.slice(0, 12):
		print("  %5d  %s" % [kinds[k], k])
	var per_min := total * 3600.0 / maxf(1.0, frames)
	print("flickers per minute (per fighter pair): %.1f" % per_min)
	var ok := per_min < 6.0   # was ~215 before the CPU held its directions
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _play(c1: String, c2: String, lvl: int, seed_value: int, kinds: Dictionary) -> Array:
	var sim := MatchSim.new(c1, c2)
	var cpu := [CpuBrain.new(0, lvl, seed_value), CpuBrain.new(1, lvl, seed_value + 99)]
	var hist := [[], []]   # per fighter: runs of [key, length]
	var count := 0
	var n := 0
	while sim.phase != MatchSim.MATCH_OVER and n < 60 * 60 * 8:
		sim.step(cpu[0].get_input(sim), cpu[1].get_input(sim))
		n += 1
		if sim.phase != MatchSim.FIGHT or sim.hitstop > 0:
			continue
		for s in 2:
			var key := pose_key(sim.f[s])
			var runs: Array = hist[s]
			if runs.size() > 0 and runs[-1][0] == key:
				runs[-1][1] += 1
				continue
			# A (any) -> B (short) -> A again: a flicker
			if runs.size() >= 2 and runs[-2][0] == key and runs[-1][1] <= GAP:
				var a: String = key
				var b: String = runs[-1][0]
				# real game events are not flicker: attacks, getting hit, jumps
				if not (b.begins_with("ATTACK") or b.begins_with("HITSTUN") or b.begins_with("BLOCKSTUN") \
						or b.begins_with("LAND") or b.begins_with("PREJUMP")):
					count += 1
					var kind := "%s -> %s -> %s" % [a, b, a]
					kinds[kind] = int(kinds.get(kind, 0)) + 1
			runs.append([key, 1])
			if runs.size() > 4:
				runs.pop_front()
	return [count, n]
