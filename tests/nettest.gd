extends SceneTree
## Headless rollback test: two peers in one process, each with its own MatchSim
## and Rollback session, joined by simulated links with latency, jitter (so
## packets reorder) and packet loss. Each peer's player is a CPU brain reading
## that peer's (possibly predicted) sim, like a human looking at the screen.
## Checks per scenario:
##   - no checksum mismatch was ever reported and checksums were compared,
##   - both peers' confirmed state equals a reference sim replayed from the
##     confirmed input log,
##   - every event of the reference run was emitted on both peers, and no
##     event fired twice for the same frame (sounds don't double up).
## Run: godot --headless --path . --script res://tests/nettest.gd


class Link:
	var lat := 0
	var jit := 0
	var loss := 0.0
	var cut_at := -1
	var rng := RandomNumberGenerator.new()
	var q: Array = []
	var sent := 0
	var dropped := 0

	func _init(p_lat: int, p_jit: int, p_loss: float, seed_value: int) -> void:
		lat = p_lat
		jit = p_jit
		loss = p_loss
		rng.seed = seed_value

	func send(bytes: PackedByteArray, now: int) -> void:
		sent += 1
		if (cut_at >= 0 and now >= cut_at) or rng.randf() < loss:
			dropped += 1
			return
		var d := lat + (rng.randi_range(-jit, jit) if jit > 0 else 0)
		q.append([now + maxi(0, d), bytes])

	func take(now: int) -> Array:
		var out: Array = []
		var keep: Array = []
		for p in q:
			if p[0] <= now:
				out.append(p[1])
			else:
				keep.append(p)
		q = keep
		return out


class Peer:
	var sim: MatchSim
	var rb: Rollback
	var brain: CpuBrain
	var events := {}      # "frame/sig" -> count
	var dup := 0

	func on_event(e: Dictionary, fr: int) -> void:
		var k := "%d/%s/%d/%d" % [fr, e["t"], int(e.get("slot", -1)), int(e.get("s", -1))]
		if events.has(k):
			dup += 1
		events[k] = events.get(k, 0) + 1


var now := 0


func _init() -> void:
	var ok := true
	#            name                 lat jit loss  offset delay
	ok = _run("lan",                    1,  0, 0.00,  0, 2) and ok
	ok = _run("50ms-3%loss",           25,  8, 0.03,  5, 2) and ok
	ok = _run("100ms-jitter-10%loss",  50, 20, 0.10, 12, 2) and ok
	ok = _run("160ms-jitter-20%loss",  80, 35, 0.20,  3, 2) and ok
	ok = _run("100ms-delay0",          50, 10, 0.05,  0, 0) and ok
	ok = _run("100ms-delay4",          50, 10, 0.05,  7, 4) and ok
	ok = _disconnect() and ok
	ok = _injected_desync() and ok
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _make(slot: int, delay: int, link: Link, seed_value: int) -> Peer:
	var p := Peer.new()
	p.sim = MatchSim.new("ced", "kros")
	p.brain = CpuBrain.new(slot, 2, seed_value)
	p.rb = Rollback.new(p.sim, slot, delay, 1, func(b: PackedByteArray) -> void: link.send(b, now),
			p.on_event, now)
	p.rb.set_record()
	return p


func _run(name: String, lat: int, jit: int, loss: float, offset: int, delay: int) -> bool:
	now = 0
	var ab := Link.new(lat, jit, loss, 11)
	var ba := Link.new(lat, jit, loss, 22)
	var a := _make(0, delay, ab, 101)
	var b: Peer = null
	var tick := 0
	var over_at := -1
	var t0 := Time.get_ticks_msec()
	while tick < 60 * 60 * 6:
		now = int(tick * 1000.0 / 60.0)
		if tick == offset:
			b = _make(1, delay, ba, 202)
		for pk in ab.take(now):
			if b != null:
				b.rb.on_packet(pk, now)
		for pk in ba.take(now):
			a.rb.on_packet(pk, now)
		a.rb.tick(a.brain.get_input(a.sim), now)
		if b != null:
			b.rb.tick(b.brain.get_input(b.sim), now)
		if over_at < 0 and b != null and a.sim.phase == MatchSim.MATCH_OVER and b.sim.phase == MatchSim.MATCH_OVER:
			over_at = tick
		if over_at >= 0 and tick > over_at + 120:
			break
		tick += 1
	var ok := true
	var msg := []
	if over_at < 0:
		ok = false
		msg.append("match did not finish")
	if a.rb.desync_frame >= 0 or b.rb.desync_frame >= 0:
		ok = false
		msg.append("DESYNC at %d/%d" % [a.rb.desync_frame, b.rb.desync_frame])
	if a.rb.checks_matched < 5 or b.rb.checks_matched < 5:
		ok = false
		msg.append("too few checksums compared")
	if a.rb.error != "" or b.rb.error != "":
		ok = false
		msg.append("error: %s %s" % [a.rb.error, b.rb.error])
	# Reference: replay the confirmed inputs on a fresh sim.
	var cf := mini(a.rb.confirmed_frame(), b.rb.confirmed_frame())
	cf = mini(cf, mini(a.rb.log_local.size(), b.rb.log_local.size()))
	cf = mini(cf, mini(a.rb.frame, b.rb.frame) - 1)
	var ref := MatchSim.new("ced", "kros")
	var ref_ev := {}
	var mismatch_inputs := 0
	for fr in cf:
		var i0: int = a.rb.log_local[fr]
		var i1: int = b.rb.log_local[fr]
		if fr < b.rb.log_remote.size() and b.rb.log_remote[fr] != i0:
			mismatch_inputs += 1
		if fr < a.rb.log_remote.size() and a.rb.log_remote[fr] != i1:
			mismatch_inputs += 1
		ref.step(i0, i1)
		for e in ref.events:
			ref_ev["%d/%s/%d/%d" % [fr, e["t"], int(e.get("slot", -1)), int(e.get("s", -1))]] = 1
	if mismatch_inputs > 0:
		ok = false
		msg.append("%d input log mismatches" % mismatch_inputs)
	var ref_s := str(ref.save_state())
	var sa := str(a.rb.state_at(cf))
	var sb := str(b.rb.state_at(cf))
	if sa != ref_s or sb != ref_s:
		ok = false
		msg.append("state at confirmed frame %d differs from reference (a=%s b=%s)" % [cf, sa == ref_s, sb == ref_s])
	var missed := 0
	var extra := 0
	for p in [a, b]:
		for k in ref_ev:
			if not p.events.has(k):
				missed += 1
		for k in p.events:
			if not ref_ev.has(k) and int(k.split("/")[0]) < cf:
				extra += 1
		if p.dup > 0:
			ok = false
			msg.append("%d events fired twice for one frame" % p.dup)
	if missed > 0:
		ok = false
		msg.append("%d reference events never emitted" % missed)
	print("[%s] %s  frames %d/%d confirmed %d  winner %d  checks %d/%d  rollbacks %d/%d (avg %.1f, max %d)  stalls %d/%d waits %d/%d  rtt %.0fms  loss %d/%d pk  events ref %d extra(mispredicted) %d  %dms%s" % [
		"PASS" if ok else "FAIL", name, a.rb.frame, b.rb.frame, cf, a.sim.match_winner,
		a.rb.checks_matched, b.rb.checks_matched, a.rb.rollbacks, b.rb.rollbacks,
		float(a.rb.rb_frames + b.rb.rb_frames) / maxi(1, a.rb.rollbacks + b.rb.rollbacks),
		maxi(a.rb.max_depth, b.rb.max_depth), a.rb.stalls, b.rb.stalls, a.rb.waits, b.rb.waits,
		a.rb.rtt_ms, ab.dropped + ba.dropped, ab.sent + ba.sent, ref_ev.size(), extra,
		Time.get_ticks_msec() - t0, "" if msg.is_empty() else "\n    " + "; ".join(msg)])
	return ok


## The link dies mid-match: both peers must stop with a timeout error, not hang
## or crash, and their sims must stay within the rollback window of each other.
func _disconnect() -> bool:
	now = 0
	var ab := Link.new(30, 5, 0.02, 3)
	var ba := Link.new(30, 5, 0.02, 4)
	var a := _make(0, 2, ab, 7)
	var b := _make(1, 2, ba, 8)
	var tick := 0
	var cut := 15000
	ab.cut_at = cut
	ba.cut_at = cut
	while tick < 60 * 40:
		now = int(tick * 1000.0 / 60.0)
		for pk in ab.take(now):
			b.rb.on_packet(pk, now)
		for pk in ba.take(now):
			a.rb.on_packet(pk, now)
		a.rb.tick(a.brain.get_input(a.sim), now)
		b.rb.tick(b.brain.get_input(b.sim), now)
		if a.rb.error != "" and b.rb.error != "":
			break
		tick += 1
	var ok := a.rb.error != "" and b.rb.error != "" and now >= cut + Rollback.TIMEOUT_MS \
			and absi(a.rb.frame - b.rb.frame) <= a.rb.max_rb + 4 and a.rb.desync_frame < 0
	print("[%s] disconnect  link cut at %dms, errors at %dms: '%s' / '%s'  frames %d/%d" % [
		"PASS" if ok else "FAIL", cut, now, a.rb.error, b.rb.error, a.rb.frame, b.rb.frame])
	return ok


## Negative check: corrupt one peer's sim mid-match; the checksum exchange
## must notice on both sides within a couple of checksum periods.
func _injected_desync() -> bool:
	now = 0
	var ab := Link.new(20, 0, 0.0, 5)
	var ba := Link.new(20, 0, 0.0, 6)
	var a := _make(0, 2, ab, 9)
	var b := _make(1, 2, ba, 10)
	var tick := 0
	var hit_at := 600
	while tick < 1200:
		now = int(tick * 1000.0 / 60.0)
		for pk in ab.take(now):
			b.rb.on_packet(pk, now)
		for pk in ba.take(now):
			a.rb.on_packet(pk, now)
		if tick == hit_at:
			b.sim.f[0].health -= 7
		a.rb.tick(a.brain.get_input(a.sim), now)
		b.rb.tick(b.brain.get_input(b.sim), now)
		tick += 1
	var ok := a.rb.desync_frame > 0 and b.rb.desync_frame > 0 and a.rb.desync_frame <= hit_at + 3 * Rollback.CHECK_EVERY
	print("[%s] injected desync at tick %d detected at frame %d/%d" % [
		"PASS" if ok else "FAIL", hit_at, a.rb.desync_frame, b.rb.desync_frame])
	return ok
