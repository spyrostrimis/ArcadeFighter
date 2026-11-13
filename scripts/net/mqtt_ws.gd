class_name MqttWs
extends RefCounted
## Minimal MQTT 3.1.1 client over a secure WebSocket (QoS 0 only), enough to
## use a free public broker as a signalling mailbox. Poll-driven: call poll()
## every frame.

enum { IDLE, OPENING, HANDSHAKE, READY, FAILED }

const CONNECT_TIMEOUT_MS := 12000
const IPV4_FALLBACK_MS := 1500
const KEEPALIVE_S := 30

var url := ""
var state := IDLE
var error := ""
var subscribed := false
var ws := WebSocketPeer.new()
var _client_id := ""
var _topic := ""
var _buf := PackedByteArray()
var _t0 := 0
var _last_tx := 0
var _inbox: Array = []     # [topic, payload]
var _host := ""
var _resolve_id := -1
var _v4_tried := false


func start(p_url: String, client_id: String, topic: String, now_ms: int) -> void:
	url = p_url
	_client_id = client_id
	_topic = topic
	_t0 = now_ms
	_host = url.get_slice("/", 2).get_slice(":", 0)
	_open(url, TLSOptions.client())


func _open(u: String, tls: TLSOptions) -> void:
	ws = WebSocketPeer.new()
	ws.supported_protocols = PackedStringArray(["mqtt"])
	ws.inbound_buffer_size = 1 << 18
	ws.outbound_buffer_size = 1 << 18
	var err := ws.connect_to_url(u, tls)
	if err != OK:
		_fail("connect error %d" % err)
	else:
		state = OPENING


## Godot connects to the first address DNS returns, often IPv6. Where IPv6 is
## broken the socket just hangs, so after a moment retry over IPv4: the URL gets
## the literal address and TLS still checks the certificate against the name.
func _ipv4_fallback(now_ms: int) -> void:
	if _v4_tried or _host.is_valid_ip_address():
		return
	if _resolve_id < 0:
		_resolve_id = IP.resolve_hostname_queue_item(_host, IP.TYPE_IPV4)
		return
	var st := IP.get_resolve_item_status(_resolve_id)
	if st == IP.RESOLVER_STATUS_WAITING:
		return
	_v4_tried = true
	var addr := IP.get_resolve_item_address(_resolve_id) if st == IP.RESOLVER_STATUS_DONE else ""
	IP.erase_resolve_item(_resolve_id)
	if addr == "" or not addr.is_valid_ip_address():
		return
	ws.close()
	_open(url.replace("//" + _host, "//" + addr), TLSOptions.client(null, _host) if url.begins_with("wss") else null)


func poll(now_ms: int) -> void:
	if state == IDLE or state == FAILED:
		return
	ws.poll()
	var rs := ws.get_ready_state()
	if rs == WebSocketPeer.STATE_OPEN:
		if state == OPENING:
			_send_connect()
			state = HANDSHAKE
		while ws.get_available_packet_count() > 0:
			_buf.append_array(ws.get_packet())
		_parse()
		if state == READY and now_ms - _last_tx > KEEPALIVE_S * 500:
			_raw(PackedByteArray([0xC0, 0x00]))   # PINGREQ
			_last_tx = now_ms
	elif rs == WebSocketPeer.STATE_CLOSED:
		_fail("closed (%d %s)" % [ws.get_close_code(), ws.get_close_reason()])
		return
	if state == OPENING and now_ms - _t0 > IPV4_FALLBACK_MS:
		_ipv4_fallback(now_ms)
	if state != READY and now_ms - _t0 > CONNECT_TIMEOUT_MS:
		_fail("timeout in state %d, ws %d" % [state, ws.get_ready_state()])


func publish(payload: PackedByteArray) -> bool:
	if state != READY:
		return false
	var body := _str(_topic)
	body.append_array(payload)
	return _raw(_packet(0x30, body))


func take() -> Array:
	var out := _inbox
	_inbox = []
	return out


func close() -> void:
	if state == READY or state == HANDSHAKE:
		_raw(PackedByteArray([0xE0, 0x00]))   # DISCONNECT
	if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		ws.close()
	state = IDLE


func _fail(msg: String) -> void:
	if state != FAILED:
		error = msg
		state = FAILED
		if ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			ws.close()


func _raw(bytes: PackedByteArray) -> bool:
	return ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY) == OK


func _send_connect() -> void:
	var body := _str("MQTT")
	body.append_array(PackedByteArray([4, 0x02, KEEPALIVE_S >> 8, KEEPALIVE_S & 0xff]))  # level 4, clean session
	body.append_array(_str(_client_id))
	_raw(_packet(0x10, body))


func _send_subscribe() -> void:
	var body := PackedByteArray([0x00, 0x01])   # packet id 1
	body.append_array(_str(_topic))
	body.append(0)                              # QoS 0
	_raw(_packet(0x82, body))


func _parse() -> void:
	while _buf.size() >= 2:
		var mult := 1
		var rl := 0
		var i := 1
		var complete := false
		while i < _buf.size() and i <= 4:
			var d := _buf[i]
			rl += (d & 0x7f) * mult
			mult *= 128
			i += 1
			if d & 0x80 == 0:
				complete = true
				break
		if not complete:
			return
		if _buf.size() < i + rl:
			return
		var head := _buf[0]
		var body := _buf.slice(i, i + rl)
		_buf = _buf.slice(i + rl)
		match head >> 4:
			2:  # CONNACK
				if body.size() >= 2 and body[1] == 0:
					state = READY
					_send_subscribe()
				else:
					_fail("refused %d" % (body[1] if body.size() >= 2 else -1))
					return
			3:  # PUBLISH
				if body.size() < 2:
					continue
				var tl := (body[0] << 8) | body[1]
				var topic := body.slice(2, 2 + tl).get_string_from_utf8()
				var p := 2 + tl
				if (head >> 1) & 3 > 0:
					p += 2   # packet id (QoS 1/2)
				_inbox.append([topic, body.slice(p)])
			9:  # SUBACK
				subscribed = true


static func _str(s: String) -> PackedByteArray:
	var u := s.to_utf8_buffer()
	var out := PackedByteArray([u.size() >> 8, u.size() & 0xff])
	out.append_array(u)
	return out


static func _packet(head: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([head])
	var n := body.size()
	while true:
		var d := n % 128
		n /= 128
		if n > 0:
			d |= 0x80
		out.append(d)
		if n == 0:
			break
	out.append_array(body)
	return out
