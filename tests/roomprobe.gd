extends SceneTree
## Real-network smoke test: a host and a guest NetRoom in one process meet
## through the public MQTT brokers, open WebRTC data channels and exchange
## packets. Optional: -- --broker=wss://...  to test one broker alone.
## Run: godot --headless --path . --script res://tests/roomprobe.gd

var h := NetRoom.new()
var g := NetRoom.new()
var t0 := 0
var phase := 0
var got := 0
var sent := 0
var ctl_got := 0

func _init() -> void:
	var b := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--broker="):
			b.append(a.substr(9))
	for r in [h, g]:
		r.brokers = b
		r.data_hash = "probe"
		r.log_fn = func(s): print("%6d %s %s" % [Time.get_ticks_msec() - t0, "H" if r == h else "G", s])
	t0 = Time.get_ticks_msec()
	h.host(0)
	print("code ", h.code)

func _process(_d: float) -> bool:
	var now := Time.get_ticks_msec()
	if phase == 0 and h.state == NetRoom.WAITING:
		phase = 1
		g.join(h.code, now)
	h.poll(now)
	g.poll(now)
	if phase < 3 and (h.state == NetRoom.FAILED or g.state == NetRoom.FAILED):
		print("FAILED host='%s' guest='%s'" % [h.error, g.error])
		print("RESULT: FAIL")
		return true
	if phase == 1 and h.state == NetRoom.CONNECTED and g.state == NetRoom.CONNECTED:
		phase = 2
		print("both connected after %dms" % (now - t0))
	if phase == 2:
		if sent < 200:
			h.send_game(PackedByteArray([sent & 255, 1, 2, 3]))
			sent += 1
			if sent % 50 == 0:
				h.send_ctl({"t": "x", "n": sent})
		got += g.take_game().size()
		ctl_got += g.take_ctl().size()
		if sent >= 200 and ((got >= 200 and ctl_got >= 4) or now - t0 > 30000):
			print("game packets %d/%d  ctl %d/4" % [got, sent, ctl_got])
			h.close(now)
			phase = 3
			t0 = now
	if phase == 3:
		if g.state == NetRoom.FAILED:
			print("guest saw: ", g.error)
			print("RESULT: ", "PASS" if got >= 190 and ctl_got == 4 and g.error == NetRoom.E_LEFT else "FAIL")
			return true
		if now - t0 > 5000:
			print("guest never saw the host leave")
			print("RESULT: FAIL")
			return true
	if now - t0 > 60000:
		print("TIMEOUT states %d %d" % [h.state, g.state])
		return true
	return false
