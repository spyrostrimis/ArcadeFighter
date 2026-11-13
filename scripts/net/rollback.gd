class_name Rollback
extends RefCounted
## GGPO-style rollback session for one MatchSim, independent of the transport.
##
## Each 60 Hz tick the owner calls tick(local_input, now_ms); packets from the
## other peer go to on_packet(bytes, now_ms); outgoing packets leave through the
## send callable. The sim only ever sees confirmed or predicted inputs:
##   - local input is scheduled `delay` frames ahead (input delay),
##   - a missing remote input is predicted by repeating the last confirmed one,
##   - when the real input arrives and differs, the sim is restored from the ring
##     of saved states and re-simulated up to the present (rollback),
##   - the sim never runs more than `max_rb` frames past the last confirmed
##     remote input (it stalls instead),
##   - frame-advantage time sync makes the peer that is ahead wait a frame now
##     and then, so neither side keeps rolling back for the other,
##   - every CHECK_EVERY frames a checksum of a fully confirmed state is
##     exchanged to detect desyncs.
## Sim events (sounds, sparks, HUD) are deduplicated per frame: an event already
## emitted for a frame is not emitted again when that frame is re-simulated.

const RING := 256
const MAX_SEND := 64
const PKT_INPUT := 1
const PKT_PING := 2
const PKT_PONG := 3
const CHECK_EVERY := 30
const TIMEOUT_MS := 10000
const ADV_WINDOW := 30
const WAIT_GAP := 12
const FRAME_MS := 1000.0 / 60.0

var sim: MatchSim
var local := 0
var remote := 1
var delay := 2
var max_rb := 8
var match_id := 0

var frame := 0               # next frame to simulate
var local_last := -1         # newest local frame with an input
var remote_last := -1        # newest remote frame with all earlier ones received
var remote_ack := -1         # newest local frame the remote has confirmed

var _inp := [PackedInt32Array(), PackedInt32Array()]
var _tag := [PackedInt32Array(), PackedInt32Array()]
var _pred := PackedInt32Array()
var _states: Array = []
var _rb_from := -1
var _send: Callable
var _on_event: Callable
var _emitted := {}

# time sync
var _adv := PackedFloat32Array()
var local_adv := 0.0
var remote_adv := 0.0
var remote_frame := -1
var _last_wait := -1000

# ping
var rtt_ms := 0.0
var _ping_t := -100000

# checksums
var _next_check := CHECK_EVERY
var _my_checks := {}
var _their_checks := {}
var last_check_frame := -1
var last_check := 0
var checks_matched := 0
var desync_frame := -1
var check_log := {}          # frame -> checksum of the confirmed state (tests)

# stats for the HUD / tests
var rollbacks := 0
var rb_frames := 0
var max_depth := 0
var last_depth := 0
var stalls := 0
var waits := 0
var last_recv_ms := 0
var stalled := false         # the sim could not advance last tick
var error := ""

# optional input log for tests (index = frame)
var record := false
var log_local := PackedInt32Array()
var log_remote := PackedInt32Array()


func _init(p_sim: MatchSim, p_local: int, p_delay: int, p_match: int, send_fn: Callable,
		event_fn: Callable, now_ms: int, p_max_rb := 8) -> void:
	sim = p_sim
	local = p_local
	remote = 1 - p_local
	delay = maxi(0, p_delay)
	max_rb = clampi(p_max_rb, 1, 30)
	match_id = p_match & 0xff
	_send = send_fn
	_on_event = event_fn
	for s in 2:
		_inp[s].resize(RING)
		_tag[s].resize(RING)
		_tag[s].fill(-1)
	_pred.resize(RING)
	_states.resize(RING)
	# Frames before the input delay kicks in have neutral input on both sides.
	for fr in delay:
		_put(local, fr, 0)
		_put(remote, fr, 0)
	local_last = delay - 1
	remote_last = delay - 1
	remote_ack = delay - 1
	last_recv_ms = now_ms


func set_record() -> void:
	record = true
	log_local.clear()
	log_remote.clear()
	for fr in delay:
		log_local.append(0)
		log_remote.append(0)


func _put(s: int, fr: int, v: int) -> void:
	var i := fr % RING
	_inp[s][i] = v
	_tag[s][i] = fr


func _has(s: int, fr: int) -> bool:
	return fr >= 0 and _tag[s][fr % RING] == fr


## Frames the sim is currently running on predicted remote input.
func predicted_frames() -> int:
	return maxi(0, frame - 1 - remote_last)


func tick(local_input: int, now_ms: int) -> void:
	if error != "":
		return
	if now_ms - last_recv_ms > TIMEOUT_MS:
		error = "THE OTHER PLAYER STOPPED RESPONDING (WAITED %dS)" % (TIMEOUT_MS / 1000)
		return
	if local_last < frame + delay:
		local_last += 1
		_put(local, local_last, local_input)
		if record:
			log_local.append(local_input)
	if _rb_from >= 0:
		_rollback()
	_do_checks()
	stalled = false
	if frame - remote_last > max_rb:
		stalled = true
		stalls += 1
	elif _should_wait():
		stalled = true
		waits += 1
	else:
		_simulate(frame)
		frame += 1
	_send_input()
	if now_ms - _ping_t >= 500:
		_ping_t = now_ms
		var b := StreamPeerBuffer.new()
		b.put_u8(PKT_PING)
		b.put_u8(match_id)
		b.put_u32(now_ms & 0xffffffff)
		_send.call(b.data_array)
	if frame % 120 == 0:
		_prune()


func _rollback() -> void:
	var from := _rb_from
	_rb_from = -1
	if from >= frame:
		return
	var depth := frame - from
	sim.load_state(_states[from % RING])
	for fr in range(from, frame):
		_simulate(fr)
	rollbacks += 1
	rb_frames += depth
	last_depth = depth
	max_depth = maxi(max_depth, depth)


func _simulate(fr: int) -> void:
	var i := fr % RING
	_states[i] = sim.save_state()
	var li: int = _inp[local][i]
	var ri := 0
	if _has(remote, fr):
		ri = _inp[remote][i]
	elif _has(remote, remote_last):
		ri = _inp[remote][remote_last % RING]
	_pred[i] = ri
	if local == 0:
		sim.step(li, ri)
	else:
		sim.step(ri, li)
	if sim.events.is_empty():
		return
	var done: PackedStringArray = _emitted.get(fr, PackedStringArray())
	for e in sim.events:
		var sig := "%s/%d/%d" % [e["t"], int(e.get("slot", -1)), int(e.get("s", -1))]
		if sig in done:
			continue
		done.append(sig)
		if _on_event.is_valid():
			_on_event.call(e, fr)
	_emitted[fr] = done


func _should_wait() -> bool:
	if _adv.size() < ADV_WINDOW / 2 or frame - _last_wait < WAIT_GAP:
		return false
	if (local_adv - remote_adv) / 2.0 >= 1.0:
		_last_wait = frame
		return true
	return false


func _send_input() -> void:
	var from := maxi(remote_ack + 1, 0)
	var to := mini(local_last, from + MAX_SEND - 1)
	var n := maxi(0, to - from + 1)
	var b := StreamPeerBuffer.new()
	b.put_u8(PKT_INPUT)
	b.put_u8(match_id)
	b.put_32(frame)
	b.put_32(remote_last)
	b.put_16(clampi(int(round(local_adv * 10.0)), -32000, 32000))
	b.put_32(last_check_frame)
	b.put_u32(last_check)
	b.put_32(from)
	b.put_u8(n)
	for k in n:
		b.put_u16(_inp[local][(from + k) % RING])
	_send.call(b.data_array)


func on_packet(bytes: PackedByteArray, now_ms: int) -> void:
	if bytes.size() < 2 or bytes[1] != match_id:
		return
	last_recv_ms = now_ms
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var typ := b.get_u8()
	b.get_u8()
	match typ:
		PKT_INPUT:
			if bytes.size() < 25:
				return
			var rf := b.get_32()
			var ack := b.get_32()
			var radv := b.get_16() / 10.0
			var cf := b.get_32()
			var cs := b.get_u32()
			var start := b.get_32()
			var n := b.get_u8()
			if bytes.size() < 25 + n * 2:
				return
			remote_ack = maxi(remote_ack, mini(ack, local_last))
			if rf >= remote_frame:
				remote_frame = rf
				remote_adv = radv
				_adv_sample(rf)
			if cf > 0:
				_their_checks[cf] = cs
				_compare(cf)
			for k in n:
				_recv(start + k, b.get_u16())
		PKT_PING:
			var t := b.get_u32()
			var o := StreamPeerBuffer.new()
			o.put_u8(PKT_PONG)
			o.put_u8(match_id)
			o.put_u32(t)
			_send.call(o.data_array)
		PKT_PONG:
			var t := b.get_u32()
			var s := float((now_ms & 0xffffffff) - t)
			if s >= 0.0 and s < 5000.0:
				rtt_ms = s if rtt_ms == 0.0 else lerpf(rtt_ms, s, 0.25)


func _adv_sample(rf: int) -> void:
	var est := rf + (rtt_ms * 0.5) / FRAME_MS
	_adv.append(frame - est)
	if _adv.size() > ADV_WINDOW:
		_adv.remove_at(0)
	var sum := 0.0
	for v in _adv:
		sum += v
	local_adv = sum / _adv.size()


func _recv(fr: int, v: int) -> void:
	if fr <= remote_last or fr > frame + RING / 2:
		return
	var i := fr % RING
	if _tag[remote][i] == fr:
		return
	_inp[remote][i] = v
	_tag[remote][i] = fr
	if fr < frame and _pred[i] != v and (_rb_from < 0 or fr < _rb_from):
		_rb_from = fr
	while _has(remote, remote_last + 1):
		remote_last += 1
		if record:
			log_remote.append(_inp[remote][remote_last % RING])


func _do_checks() -> void:
	while _next_check <= remote_last + 1 and _next_check < frame:
		var cs := checksum(_states[_next_check % RING])
		_my_checks[_next_check] = cs
		check_log[_next_check] = cs
		last_check_frame = _next_check
		last_check = cs
		_compare(_next_check)
		_next_check += CHECK_EVERY


func _compare(cf: int) -> void:
	if _my_checks.has(cf) and _their_checks.has(cf):
		if _my_checks[cf] == _their_checks[cf]:
			checks_matched += 1
		elif desync_frame < 0:
			desync_frame = cf
		_my_checks.erase(cf)
		_their_checks.erase(cf)


static func checksum(state: Array) -> int:
	return hash(var_to_bytes(state)) & 0xffffffff


## State at the start of frame `fr`, if it is still in the ring (tests).
func state_at(fr: int) -> Array:
	if fr >= frame or frame - fr >= RING:
		return []
	return _states[fr % RING]


func confirmed_frame() -> int:
	return mini(remote_last + 1, frame)


func _prune() -> void:
	for k in _emitted.keys():
		if k < frame - RING:
			_emitted.erase(k)
	for d in [_my_checks, _their_checks]:
		for k in d.keys():
			if k < frame - RING * 4:
				d.erase(k)
