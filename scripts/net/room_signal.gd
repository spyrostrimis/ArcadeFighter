class_name RoomSignal
extends RefCounted
## Signalling mailbox for one room code, over several free public MQTT brokers
## at once (the same brokers the SFAZ netroom used). Every message goes to every
## broker that is connected and is de-duplicated on arrival, so the two players
## meet even if one broker is down or only reachable from one side.
##
## The broker topic is a hash of the room code, and every payload is AES-256
## encrypted with a key derived from the code, so people watching the public
## broker see neither the code nor the players' IP addresses in the SDP.

const BROKERS := [
	"wss://broker.emqx.io:8084/mqtt",
	"wss://broker.hivemq.com:8884/mqtt",
	"wss://test.mosquitto.org:8081/mqtt",
]
const MAGIC := "AF1|"

var clients: Array[MqttWs] = []
var my_id := ""
var topic := ""
var _key := PackedByteArray()
var _seen := {}
var _crypto := Crypto.new()


func start(code: String, p_my_id: String, now_ms: int, brokers: Array = []) -> void:
	my_id = p_my_id
	topic = "arcadefighter/v1/" + _sha("AF-ROOM-TOPIC-v1:" + code).hex_encode().substr(0, 32)
	_key = _sha("AF-ROOM-KEY-v1:" + code)
	var list: Array = brokers if not brokers.is_empty() else BROKERS
	for url in list:
		var c := MqttWs.new()
		c.start(url, "af-" + my_id + "-" + str(clients.size()), topic, now_ms)
		clients.append(c)


func poll(now_ms: int) -> void:
	for c in clients:
		c.poll(now_ms)


## Messages from the other side since the last call (decrypted dictionaries).
func take() -> Array:
	var out: Array = []
	for c in clients:
		for m in c.take():
			var d: Variant = _open(m[1])
			if d is Dictionary and d.get("from", "") != my_id and not _seen.has(d.get("mid", "")):
				_seen[d.get("mid", "")] = true
				out.append(d)
	return out


func send(msg: Dictionary) -> int:
	msg["from"] = my_id
	msg["mid"] = _crypto.generate_random_bytes(8).hex_encode()
	var payload := _seal(JSON.stringify(msg))
	var n := 0
	for c in clients:
		if c.subscribed and c.publish(payload):
			n += 1
	return n


func ready_count() -> int:
	var n := 0
	for c in clients:
		if c.subscribed:
			n += 1
	return n


func all_failed() -> bool:
	for c in clients:
		if c.state != MqttWs.FAILED:
			return false
	return true


func failures() -> String:
	var parts := []
	for c in clients:
		if c.state == MqttWs.FAILED:
			parts.append("%s: %s" % [c.url.get_slice("/", 2), c.error])
	return ", ".join(parts)


func close() -> void:
	for c in clients:
		c.close()
	clients.clear()


func _seal(text: String) -> PackedByteArray:
	var plain := (MAGIC + text).to_utf8_buffer()
	var pad := 16 - plain.size() % 16
	for i in pad:
		plain.append(pad)
	var iv := _crypto.generate_random_bytes(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, _key, iv)
	var out := iv.duplicate()
	out.append_array(aes.update(plain))
	aes.finish()
	return out


func _open(data: PackedByteArray) -> Variant:
	if data.size() < 32 or data.size() % 16 != 0:
		return null
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, _key, data.slice(0, 16))
	var plain := aes.update(data.slice(16))
	aes.finish()
	var pad := plain[plain.size() - 1]
	if pad < 1 or pad > 16:
		return null
	var text := plain.slice(0, plain.size() - pad).get_string_from_utf8()
	if not text.begins_with(MAGIC):
		return null
	return JSON.parse_string(text.substr(MAGIC.length()))


static func _sha(s: String) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(s.to_utf8_buffer())
	return h.finish()
