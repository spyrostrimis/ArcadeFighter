class_name NetRoom
extends RefCounted
## Room-code connection: no IP, no port forwarding, no server of our own.
##
## Modelled on the SFAZ netroom: a short room code names a mailbox on free
## public MQTT brokers (RoomSignal). The guest announces itself there, the host
## answers with a WebRTC offer, both trade ICE candidates found through public
## STUN servers, and WebRTC punches a direct UDP path between the two PCs.
## After that the brokers are dropped and everything goes peer to peer:
##   "game" channel - unordered, no retransmits (rollback inputs, pings)
##   "ctl"  channel - reliable, ordered (menus, character select, rematch)
## Every failure ends in a plain-language `error` so the menu can say why.
## Poll-driven: call poll() every frame.

enum { IDLE, SIGNALING, WAITING, NEGOTIATING, HANDSHAKE, CONNECTED, FAILED, CLOSING, CLOSED }

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"   # no I/O/0/1 to misread
const CODE_LEN := 6
const PROTOCOL := 1
const STUN := ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun.cloudflare.com:3478"]
const SIGNAL_TIMEOUT := 13000
const JOIN_TIMEOUT := 15000
const CONNECT_TIMEOUT := 20000
const HELLO_TIMEOUT := 8000
const LINK_TIMEOUT := 10000
const RESEND_MS := 1500

const E_SIGNAL := "NO SIGNALLING SERVICE REACHABLE - CHECK YOUR INTERNET CONNECTION"
const E_NOHOST := "NO HOST ANSWERED - CHECK THE CODE, AND THAT THE HOST HAS HOST ROOM OPEN"
const E_NAT := "CANNOT CONNECT TO THE OTHER PLAYER - A STRICT NAT OR FIREWALL BLOCKED THE DIRECT LINK"
const E_VERSION := "BOTH PLAYERS NEED THE SAME GAME VERSION"
const E_FULL := "THAT ROOM ALREADY HAS TWO PLAYERS"
const E_NORESP := "THE OTHER PLAYER DID NOT RESPOND"
const E_LEFT := "THE OTHER PLAYER LEFT"
const E_LOST := "THE OTHER PLAYER LEFT OR THE CONNECTION WAS LOST"
const E_TIMEOUT := "THE OTHER PLAYER STOPPED RESPONDING"

var is_host := false
var code := ""
var state := IDLE
var status := ""
var error := ""
var data_hash := ""
var brokers: Array = []
var my_id := ""
var peer_id := ""
var sig: RoomSignal
var pc: WebRTCPeerConnection
var ch_game: WebRTCDataChannel
var ch_ctl: WebRTCDataChannel
var last_rx_ms := 0
var log_fn: Callable

var _t_phase := 0
var _t_resend := -100000
var _t_cands := -100000
var _t_ka := 0
var _cands: Array = []
var _cand_sent := 0
var _local_sdp := {}
var _remote_set := false
var _got_hello := false
var _remote_cands: Array = []
var _added := {}
var _game_in: Array = []
var _ctl_in: Array = []


static func gen_code() -> String:
	var c := Crypto.new()
	var b := c.generate_random_bytes(CODE_LEN)
	var s := ""
	for i in CODE_LEN:
		s += CODE_CHARS[b[i] % CODE_CHARS.length()]
	return s


## Returns [true, canonical code] or [false, reason].
static func normalize(typed: String) -> Array:
	var s := typed.strip_edges().to_upper().replace(" ", "").replace("-", "")
	for ch in s:
		if not CODE_CHARS.contains(ch):
			return [false, "INVALID CHARACTER '%s' IN ROOM CODE" % ch]
	if s.length() != CODE_LEN:
		return [false, "ROOM CODE MUST BE %d CHARACTERS" % CODE_LEN]
	return [true, s]


func host(now_ms: int, forced_code := "") -> void:
	is_host = true
	code = forced_code if forced_code != "" else gen_code()
	_start(now_ms)


func join(p_code: String, now_ms: int) -> void:
	is_host = false
	code = p_code
	_start(now_ms)


func _start(now_ms: int) -> void:
	my_id = Crypto.new().generate_random_bytes(6).hex_encode()
	sig = RoomSignal.new()
	sig.start(code, my_id, now_ms, brokers)
	state = SIGNALING
	status = "CONTACTING SIGNALLING SERVICE..."
	_t_phase = now_ms
	_log("room %s as %s, id %s" % [code, "host" if is_host else "guest", my_id])


func is_connected_to_peer() -> bool:
	return state == CONNECTED


func poll(now_ms: int) -> void:
	if state == IDLE or state == FAILED or state == CLOSED:
		return
	if state == CLOSING:
		if pc != null:
			pc.poll()
		if now_ms - _t_phase > 300:
			_shutdown()
			state = CLOSED
		return
	if sig != null:
		sig.poll(now_ms)
		for m in sig.take():
			_on_signal(m, now_ms)
			if state == FAILED:
				return
	if pc != null:
		pc.poll()
		_read_channels(now_ms)
		if state == FAILED:
			return
	match state:
		SIGNALING:
			if sig.ready_count() > 0:
				_log("signalling ready on %d broker(s)" % sig.ready_count())
				state = WAITING
				_t_phase = now_ms
				status = "WAITING FOR OPPONENT..." if is_host else "LOOKING FOR THE HOST..."
			elif sig.all_failed() or now_ms - _t_phase > SIGNAL_TIMEOUT:
				_log("signalling failed: " + sig.failures())
				_fail(E_SIGNAL)
		WAITING:
			if not is_host:
				if now_ms - _t_resend > RESEND_MS:
					_t_resend = now_ms
					sig.send({"t": "join", "v": PROTOCOL})
				if now_ms - _t_phase > JOIN_TIMEOUT:
					_fail(E_NOHOST)
		NEGOTIATING:
			_flush_cands(now_ms)
			if is_host and not _remote_set and not _local_sdp.is_empty() and now_ms - _t_resend > RESEND_MS:
				_t_resend = now_ms
				_send_sdp()
			var cs := pc.get_connection_state()
			if cs == WebRTCPeerConnection.STATE_FAILED:
				_log("ICE failed")
				_fail(E_NAT)
			elif _open(ch_game) and _open(ch_ctl):
				_log("data channels open after %dms" % (now_ms - _t_phase))
				state = HANDSHAKE
				_t_phase = now_ms
				status = "CHECKING GAME VERSION..."
				send_ctl({"t": "hello", "v": PROTOCOL, "h": data_hash})
			elif now_ms - _t_phase > CONNECT_TIMEOUT:
				_fail(E_NAT)
		HANDSHAKE:
			if _got_hello:
				_log("connected")
				state = CONNECTED
				status = "CONNECTED"
				_t_ka = now_ms
				if sig != null:   # the brokers are not needed any more
					sig.close()
					sig = null
			elif now_ms - _t_phase > HELLO_TIMEOUT:
				_fail(E_NORESP)
		CONNECTED:
			var cs := pc.get_connection_state()
			if cs == WebRTCPeerConnection.STATE_FAILED or cs == WebRTCPeerConnection.STATE_CLOSED \
					or not _open(ch_ctl):
				_fail(E_LOST)
			elif now_ms - last_rx_ms > LINK_TIMEOUT:
				_fail(E_TIMEOUT)
			elif now_ms - _t_ka > 1000:
				_t_ka = now_ms
				send_ctl({"t": "ka"})


func send_game(bytes: PackedByteArray) -> void:
	if ch_game != null and _open(ch_game):
		ch_game.put_packet(bytes)


func send_ctl(msg: Dictionary) -> void:
	if ch_ctl != null and _open(ch_ctl):
		ch_ctl.put_packet(JSON.stringify(msg).to_utf8_buffer())


func take_game() -> Array:
	var out := _game_in
	_game_in = []
	return out


func take_ctl() -> Array:
	var out := _ctl_in
	_ctl_in = []
	return out


## Leave the room. A connected peer is told first, so it can say "left".
func close(now_ms: int) -> void:
	if state == CONNECTED or state == HANDSHAKE:
		send_ctl({"t": "bye"})
		state = CLOSING
		_t_phase = now_ms
		if sig != null:
			sig.close()
			sig = null
		return
	_shutdown()
	state = CLOSED


func _shutdown() -> void:
	if sig != null:
		sig.close()
		sig = null
	if pc != null:
		pc.close()
		pc = null
	ch_game = null
	ch_ctl = null


func _fail(msg: String) -> void:
	_log("FAIL: " + msg)
	error = msg
	status = msg
	_shutdown()
	state = FAILED


func _log(s: String) -> void:
	if log_fn.is_valid():
		log_fn.call("[room] " + s)


static func _open(ch: WebRTCDataChannel) -> bool:
	return ch != null and ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN


func _make_pc() -> void:
	pc = WebRTCPeerConnection.new()
	pc.initialize({"iceServers": [{"urls": STUN}]})
	pc.session_description_created.connect(_on_sdp)
	pc.ice_candidate_created.connect(_on_cand)
	ch_game = pc.create_data_channel("game", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	ch_ctl = pc.create_data_channel("ctl", {"negotiated": true, "id": 2})
	ch_game.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY
	ch_ctl.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY


func _on_sdp(type: String, sdp: String) -> void:
	if pc == null:
		return
	pc.set_local_description(type, sdp)
	_local_sdp = {"type": type, "sdp": sdp}
	_send_sdp()


func _send_sdp() -> void:
	if sig != null and not _local_sdp.is_empty():
		sig.send({"t": _local_sdp["type"], "to": peer_id, "sdp": _local_sdp["sdp"]})


func _on_cand(media: String, index: int, cname: String) -> void:
	_cands.append([media, index, cname])


func _flush_cands(now_ms: int) -> void:
	if _cands.is_empty() or sig == null:
		return
	# New candidates go out in small batches; the full list is repeated now and
	# then because the brokers may drop a message (QoS 0).
	if (_cands.size() > _cand_sent and now_ms - _t_cands > 150) or now_ms - _t_cands > 2000:
		_t_cands = now_ms
		_cand_sent = _cands.size()
		sig.send({"t": "ice", "to": peer_id, "c": _cands})


func _add_cands(list: Array) -> void:
	for c in list:
		if c is Array and c.size() == 3:
			if not _remote_set:
				_remote_cands.append(c)
				continue
			var k := str(c)
			if _added.has(k):
				continue
			_added[k] = true
			pc.add_ice_candidate(String(c[0]), int(c[1]), String(c[2]))


func _set_remote(type: String, sdp: String) -> void:
	pc.set_remote_description(type, sdp)
	_remote_set = true
	var pending := _remote_cands
	_remote_cands = []
	_add_cands(pending)


func _on_signal(m: Dictionary, now_ms: int) -> void:
	var t: String = m.get("t", "")
	var from: String = m.get("from", "")
	if t != "join" and m.get("to", "") != my_id:
		return
	if is_host:
		match t:
			"join":
				if int(m.get("v", -1)) != PROTOCOL:
					sig.send({"t": "badver", "to": from})
				elif peer_id == "":
					peer_id = from
					_log("guest %s joined" % from)
					_make_pc()
					pc.create_offer()
					state = NEGOTIATING
					status = "CONNECTING..."
					_t_phase = now_ms
				elif from == peer_id:
					if not _remote_set:
						_send_sdp()
				else:
					sig.send({"t": "full", "to": from})
			"answer":
				if from == peer_id and not _remote_set and pc != null:
					_log("answer received")
					_set_remote("answer", m.get("sdp", ""))
			"ice":
				if from == peer_id and pc != null:
					_add_cands(m.get("c", []))
	else:
		match t:
			"offer":
				if peer_id == "" and state == WAITING:
					peer_id = from
					_log("offer received from %s" % from)
					_make_pc()
					_set_remote("offer", m.get("sdp", ""))
					state = NEGOTIATING
					status = "CONNECTING..."
					_t_phase = now_ms
				elif from == peer_id:
					_send_sdp()   # our answer was probably lost
			"ice":
				if from == peer_id and pc != null:
					_add_cands(m.get("c", []))
			"full":
				if peer_id == "":
					_fail(E_FULL)
			"badver":
				_fail(E_VERSION)


func _read_channels(now_ms: int) -> void:
	if ch_game != null:
		while ch_game.get_available_packet_count() > 0:
			_game_in.append(ch_game.get_packet())
			last_rx_ms = now_ms
	if ch_ctl != null:
		while ch_ctl != null and ch_ctl.get_available_packet_count() > 0:
			var d: Variant = JSON.parse_string(ch_ctl.get_packet().get_string_from_utf8())
			last_rx_ms = now_ms
			if not d is Dictionary:
				continue
			match String(d.get("t", "")):
				"hello":
					if int(d.get("v", -1)) != PROTOCOL or String(d.get("h", "")) != data_hash:
						_fail(E_VERSION)
						return
					_got_hello = true
				"bye":
					_fail(E_LEFT)
					return
				"ka":
					pass
				_:
					_ctl_in.append(d)
