extends Node
## Online session that lives across screens (autoload "Net").
## Owns the NetRoom, routes game packets to the running Rollback session and
## keeps control messages (character select, rematch...) in an inbox for the
## screens. When the link drops it emits `lost` with a reason for the menu.
##
## Test options (after "--"):
##   --netsim=LAG,JITTER,LOSS   delay/jitter outgoing game packets by LAG±JITTER ms
##                              and drop LOSS percent of them (rollback testing)
##   --brokers=URL|URL          use these MQTT brokers instead of the defaults
##   --netlog=PATH              append connection/session log lines to PATH

signal lost(reason: String)

var room: NetRoom
var session: Rollback
var local_slot := 0
var delay := 2
var match_id := 0
var opponent := "OPPONENT"
var last_error := ""

var _inbox: Array = []
var _was_connected := false
var _closing: Array = []
var _lag := 0
var _jit := 0
var _loss := 0.0
var _outq: Array = []
var _rng := RandomNumberGenerator.new()
var _log_path := ""


func _ready() -> void:
	process_physics_priority = -100   # before the screens' physics tick
	var o: Dictionary = Game.opt
	if o.has("delay"):
		delay = clampi(int(o["delay"]), 0, 8)
	if o.has("netsim"):
		var p := String(o["netsim"]).split(",")
		_lag = int(p[0]) if p.size() > 0 else 0
		_jit = int(p[1]) if p.size() > 1 else 0
		_loss = float(p[2]) / 100.0 if p.size() > 2 else 0.0
	_log_path = o.get("netlog", "")
	_rng.randomize()


func log_line(s: String) -> void:
	if _log_path == "":
		return
	var f := FileAccess.open(_log_path, FileAccess.READ_WRITE if FileAccess.file_exists(_log_path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("%8d %s" % [Time.get_ticks_msec(), s])


func _new_room() -> NetRoom:
	leave()
	var r := NetRoom.new()
	r.data_hash = data_hash()
	r.log_fn = log_line
	if Game.opt.has("brokers"):
		r.brokers = Array(String(Game.opt["brokers"]).split("|"))
	last_error = ""
	_was_connected = false
	_inbox.clear()
	match_id = 0
	return r


func host(forced_code := "") -> void:
	room = _new_room()
	room.host(Time.get_ticks_msec(), forced_code)
	local_slot = 0


func join(code: String) -> void:
	room = _new_room()
	room.join(code, Time.get_ticks_msec())
	local_slot = 1


func is_online() -> bool:
	return room != null and room.state == NetRoom.CONNECTED


## Leave the room (tells the other player). Safe to call any time.
func leave() -> void:
	if room != null:
		room.close(Time.get_ticks_msec())
		if room.state == NetRoom.CLOSING:
			_closing.append(room)
		room = null
	session = null
	_inbox.clear()
	_outq.clear()
	_was_connected = false


func send_ctl(msg: Dictionary) -> void:
	if room != null:
		room.send_ctl(msg)


func take_ctl() -> Array:
	var out := _inbox
	_inbox = []
	return out


func send_game(bytes: PackedByteArray) -> void:
	if room == null:
		return
	if _lag == 0 and _jit == 0 and _loss == 0.0:
		room.send_game(bytes)
		return
	if _rng.randf() < _loss:
		return
	var d := _lag + (_rng.randi_range(-_jit, _jit) if _jit > 0 else 0)
	_outq.append([Time.get_ticks_msec() + maxi(0, d), bytes])


## Hash of everything both players must agree on, checked when connecting.
static func data_hash() -> String:
	var s := "proto%d|" % NetRoom.PROTOCOL
	for c in Game.CHARACTERS:
		s += c + str(CharData.get_data(c)) + "|"
	return s.sha256_text().substr(0, 16)


func _physics_process(_delta: float) -> void:
	poll()


func poll() -> void:
	var now := Time.get_ticks_msec()
	for r in _closing.duplicate():
		r.poll(now)
		if r.state != NetRoom.CLOSING:
			_closing.erase(r)
	if room == null:
		return
	if not _outq.is_empty():
		var keep: Array = []
		for p in _outq:
			if p[0] <= now:
				room.send_game(p[1])
			else:
				keep.append(p)
		_outq = keep
	room.poll(now)
	for pk in room.take_game():
		if session != null:
			session.on_packet(pk, now)
	_inbox.append_array(room.take_ctl())
	if room.state == NetRoom.CONNECTED:
		_was_connected = true
	elif room.state == NetRoom.FAILED and _was_connected:
		last_error = room.error
		log_line("lost: " + last_error)
		room = null
		session = null
		_was_connected = false
		lost.emit(last_error)
