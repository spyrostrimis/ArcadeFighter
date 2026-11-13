class_name Fighter
extends RefCounted
## One fighter's simulation state. Integer math only (positions in 1/100 px)
## so the whole match can be saved, restored and re-simulated for rollback.

enum { IDLE, WALK, CROUCH, PREJUMP, AIR, LAND, ATTACK, HITSTUN, BLOCKSTUN, FALL, LIE, GETUP, KO, WIN, LOSE }

const SUB := 100
const BUF := 5            # input buffer window (frames)
const PREJUMP_FRAMES := 4
const LIE_FRAMES := 40
const GETUP_FRAMES := 24
const MOTION_WINDOW := 12  # frames allowed between the steps of a motion (e.g. down, down-forward, forward)

const SAVE_FIELDS := [
	"x", "y", "vx", "vy", "facing", "health", "state", "sf", "move", "move_hit",
	"stun", "crouched", "air_attacked", "jump_dir", "push_v", "fall_kd", "combo",
	"inp", "prev_inp", "buf", "guarding", "invuln", "score", "wins", "land_len", "bounced",
	"hit_idx", "qcf", "qcf_t",
]

var slot := 0
var cid := "ced"
var data: Dictionary
var moves: Dictionary

var x := 0
var y := 0
var vx := 0
var vy := 0
var facing := 1
var health := 1000
var state := IDLE
var sf := 0               # frames spent in current state
var move := ""
var move_hit := 0         # 0 = not connected, 1 = hit, 2 = blocked
var stun := 0
var crouched := false
var air_attacked := false
var jump_dir := 0
var push_v := 0
var fall_kd := false
var combo := 0            # hits taken in the current combo
var inp := 0
var prev_inp := 0
var buf: Array = [99, 99, 99, 99, 99, 99]
var guarding := false
var invuln := 0
var score := 0
var wins := 0
var land_len := 3
var bounced := false
var hit_idx := 0          # which hit of a multi-hit move is current
var qcf := 0              # quarter-circle-forward progress: 1 down, 2 down-forward, 3 forward
var qcf_t := 0            # frames left to continue the motion

var ev: Array = []        # events for this frame (sound/effects), not saved


func _init(p_slot: int, p_cid: String) -> void:
	slot = p_slot
	cid = p_cid
	data = CharData.get_data(cid)
	moves = data["moves"]


func reset_round(px_pos: int, face: int) -> void:
	x = px_pos * SUB
	y = 0
	vx = 0
	vy = 0
	facing = face
	health = data["health"]
	set_state(IDLE)
	move = ""
	move_hit = 0
	stun = 0
	crouched = false
	air_attacked = false
	jump_dir = 0
	push_v = 0
	fall_kd = false
	combo = 0
	inp = 0
	prev_inp = 0
	buf = [99, 99, 99, 99, 99, 99]
	guarding = false
	invuln = 0
	land_len = 3
	bounced = false
	hit_idx = 0
	qcf = 0
	qcf_t = 0


func save() -> Array:
	var a := []
	for f in SAVE_FIELDS:
		var v = get(f)
		a.append(v.duplicate() if v is Array else v)
	return a


func load_state(a: Array) -> void:
	for i in SAVE_FIELDS.size():
		var v = a[i]
		set(SAVE_FIELDS[i], v.duplicate() if v is Array else v)


# ---------------------------------------------------------------- queries

func px() -> int:
	return x / SUB


func fwd_bit() -> int:
	return Inp.RIGHT if facing == 1 else Inp.LEFT


func back_bit() -> int:
	return Inp.LEFT if facing == 1 else Inp.RIGHT


func holds(bit: int) -> bool:
	return (inp & bit) != 0


func is_air_move() -> bool:
	return state == ATTACK and move.begins_with("j_")


func airborne() -> bool:
	return y > 0 or vy > 0


func cur_move() -> Dictionary:
	return moves[move]


## Frame data of the current hit: the move itself, or one entry of a multi-hit move's "hits".
func hit_data() -> Dictionary:
	var m: Dictionary = moves[move]
	if m.has("hits"):
		return m["hits"][hit_idx]
	return m


## Moves that carry their own root motion (travel + height per frame, from the animation).
func on_path() -> bool:
	return state == ATTACK and moves[move].has("path")


## Number of frames the current move lasts.
func move_length() -> int:
	var m: Dictionary = moves[move]
	if m.has("path"):
		return (m["path"] as Array).size()
	return int(m["startup"]) + int(m["active"]) + maxi(1, int(m["recovery"]))


func move_active() -> bool:
	if state != ATTACK:
		return false
	var m := hit_data()
	var s: int = m["startup"]
	return sf >= s and sf < s + int(m["active"])


func is_crouching() -> bool:
	if state == CROUCH:
		return true
	if state == ATTACK:
		return move.begins_with("cr_")
	if state == HITSTUN or state == BLOCKSTUN:
		return crouched
	return false


func is_threat_to(other: Fighter) -> bool:
	return state == ATTACK and absi(x - other.x) < 150 * SUB


func settled() -> bool:
	return not airborne() and state != PREJUMP and state != AIR and state != FALL and not is_air_move()


func can_block(att: Fighter, m: Dictionary) -> bool:
	if not (state == IDLE or state == WALK or state == CROUCH or state == BLOCKSTUN):
		return false
	if airborne():
		return false
	var away := Inp.LEFT if att.x > x else (Inp.RIGHT if att.x < x else back_bit())
	if not holds(away):
		return false
	var down := holds(Inp.DOWN)
	var g: int = m["guard"]
	if g == CharData.Guard.LOW and not down:
		return false
	if g == CharData.Guard.HIGH and down:
		return false
	return true


## World-space box from a local [x, y, w, h] box (y up from the feet).
func box_to_world(b: Array) -> Rect2i:
	var bx: int = b[0]
	var bw: int = b[2]
	var wx: int = px() + (bx if facing == 1 else -bx - bw)
	return Rect2i(wx, y / SUB + int(b[1]), bw, b[3])


func hurt_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if invuln > 0 or state == FALL or state == LIE or state == GETUP or state == KO:
		return out
	var hb: Array
	if airborne():
		hb = data["hurt_air"]
	elif is_crouching():
		hb = data["hurt_crouch"]
	else:
		hb = data["hurt_stand"]
	out.append(box_to_world(hb))
	if state == ATTACK:
		var m := hit_data()
		var s: int = m["startup"]
		if sf >= s - 1 and sf < s + int(m["active"]) + int(m["recovery"]) / 2:
			var b: Array = m["box"]
			out.append(box_to_world([int(b[0]) + 2, int(b[1]) + 1, int(b[2]) - 4, int(b[3]) - 2]))
	return out


func hit_rect() -> Rect2i:
	return box_to_world(hit_data()["box"])


## Vertical extent of the push box (bottom, top) in px.
func push_span() -> Vector2i:
	var by := y / SUB
	if state == LIE or (state == KO and not airborne()):
		return Vector2i(0, 16)
	if airborne():
		return Vector2i(by + 18, by + 74)
	if is_crouching():
		return Vector2i(0, 60)
	return Vector2i(0, 90)


# ---------------------------------------------------------------- update

func set_state(st: int) -> void:
	state = st
	sf = 0


func read_buttons(age: bool) -> void:
	for i in 6:
		var b: int = Inp.BUTTONS[i]
		if (inp & b) != 0 and (prev_inp & b) == 0:
			buf[i] = 0
		elif age and buf[i] < 99:
			buf[i] += 1
	prev_inp = inp
	if age:
		_track_qcf()


## Follows down -> down-forward -> forward. qcf == 3 means the motion is done
## and a punch within the next frames does the special move.
func _track_qcf() -> void:
	var d := holds(Inp.DOWN)
	var fw := holds(fwd_bit())
	if d and not fw:
		qcf = 1
		qcf_t = MOTION_WINDOW
	elif d and fw:
		if qcf == 1:
			qcf = 2
			qcf_t = MOTION_WINDOW
	elif fw and qcf == 2:
		qcf = 3
		qcf_t = MOTION_WINDOW
	if qcf_t > 0:
		qcf_t -= 1
	if qcf_t <= 0:
		qcf = 0


## A special move whose motion is done and whose button was just pressed, or "".
func _special() -> String:
	for sp in data.get("specials", []):
		if sp["motion"] == "qcf" and qcf == 3:
			for i in sp["buttons"]:
				if buf[i] <= BUF:
					buf[i] = 99
					qcf = 0
					return sp["move"]
	return ""


## Takes the strongest buffered button (index into Inp.BUTTONS) or -1.
func _take(only_light := false) -> int:
	var order := [0, 3] if only_light else [2, 5, 1, 4, 0, 3]
	for i in order:
		if buf[i] <= BUF:
			buf[i] = 99
			return i
	return -1


func _face(opp: Fighter) -> void:
	if opp.x > x:
		facing = 1
	elif opp.x < x:
		facing = -1


func _to_neutral() -> void:
	set_state(CROUCH if holds(Inp.DOWN) else IDLE)


func _start_move(mname: String) -> void:
	move = mname
	move_hit = 0
	hit_idx = 0
	set_state(ATTACK)
	if not mname.begins_with("j_"):
		vx = 0
	crouched = mname.begins_with("cr_")
	guarding = false


func think(opp: Fighter) -> void:
	sf += 1
	if invuln > 0:
		invuln -= 1
	match state:
		IDLE, WALK, CROUCH:
			_neutral(opp)
		PREJUMP:
			if sf >= PREJUMP_FRAMES:
				set_state(AIR)
				vy = data["jump_vy"]
				vx = jump_dir * int(data["jump_vx"]) * facing
				air_attacked = false
				ev.append({"t": "jump"})
		AIR:
			if not air_attacked:
				var bi := _take()
				if bi >= 0:
					_start_move("j_" + Inp.BUTTON_NAMES[bi])
					air_attacked = true
		LAND:
			if sf >= land_len:
				_to_neutral()
				_neutral(opp)
		ATTACK:
			_attack(opp)
		HITSTUN:
			stun -= 1
			if stun <= 0:
				combo = 0
				_to_neutral()
				_neutral(opp)
		BLOCKSTUN:
			crouched = holds(Inp.DOWN)
			stun -= 1
			if stun <= 0:
				_to_neutral()
				_neutral(opp)
		LIE:
			if sf >= LIE_FRAMES:
				set_state(GETUP)
				ev.append({"t": "getup"})
		GETUP:
			if sf >= GETUP_FRAMES:
				set_state(IDLE)
				_face(opp)
				_neutral(opp)


func _neutral(opp: Fighter) -> void:
	_face(opp)
	var down := holds(Inp.DOWN)
	var fwd := holds(fwd_bit())
	var bk := holds(back_bit())
	guarding = bk and opp.is_threat_to(self)
	var sp := _special()
	if sp != "":
		_start_move(sp)
		return
	var bi := _take()
	if bi >= 0:
		_start_move(("cr_" if down else "st_") + Inp.BUTTON_NAMES[bi])
		return
	if holds(Inp.UP):
		jump_dir = 1 if fwd else (-1 if bk else 0)
		set_state(PREJUMP)
		vx = 0
		return
	if down:
		if state != CROUCH:
			set_state(CROUCH)
		vx = 0
		return
	if fwd:
		if state != WALK:
			set_state(WALK)
		vx = int(data["walk_f"]) * facing
	elif bk and not guarding:
		if state != WALK:
			set_state(WALK)
		vx = -int(data["walk_b"]) * facing
	else:
		if state != IDLE:
			set_state(IDLE)
		vx = 0


func _attack(opp: Fighter) -> void:
	if moves[move].has("path"):
		_path_move(opp)
		return
	var m: Dictionary = moves[move]
	var s: int = m["startup"]
	var a: int = m["active"]
	var r: int = m["recovery"]
	if sf == s:
		ev.append({"t": "swing", "s": m["strength"]})
	if move.begins_with("j_"):
		if sf >= s + a:
			set_state(AIR)
		return
	var st: Array = m["step"]
	if st.size() == 3 and sf >= int(st[0]) and sf < int(st[1]):
		vx = int(st[2]) * facing
	else:
		vx = 0
	if m["cancel"] and move_hit != 0 and sf >= s:
		var bi := _take(true)
		if bi >= 0:
			_start_move(("cr_" if holds(Inp.DOWN) else "st_") + Inp.BUTTON_NAMES[bi])
			return
	if sf >= s + a + r:
		_to_neutral()
		_neutral(opp)


## Plays a root-motion move: position follows the animation's path, hits come in order.
func _path_move(opp: Fighter) -> void:
	var m: Dictionary = moves[move]
	var path: Array = m["path"]
	var hits: Array = m["hits"]
	if hit_idx + 1 < hits.size() and sf >= int(hits[hit_idx + 1]["startup"]):
		hit_idx += 1
		move_hit = 0
	if sf == int(hits[hit_idx]["startup"]):
		ev.append({"t": "swing", "s": hits[hit_idx]["strength"]})
	var i := mini(sf, path.size() - 1)
	var prev: Array = path[i - 1] if i > 0 else path[0]
	var was_up := y > 0
	x += (int(path[i][0]) - int(prev[0])) * facing   # path is in 1/100 px, like x and y
	y = int(path[i][1])
	vx = 0
	vy = 0
	if was_up and y == 0:
		ev.append({"t": "land"})
	if sf >= path.size() - 1:
		y = 0
		_to_neutral()
		_neutral(opp)


func physics() -> void:
	if on_path():
		pass
	elif airborne():
		x += vx
		y += vy
		vy -= int(data["gravity"])
		if y <= 0 and vy < 0:
			y = 0
			_landed()
	else:
		x += vx
	if push_v != 0:
		x += push_v
		push_v = push_v * 3 / 4
		if absi(push_v) < 25:
			push_v = 0


func _landed() -> void:
	if state == FALL or state == KO:
		if (fall_kd or state == KO) and not bounced and vy < -450:
			bounced = true
			vy = -vy * 3 / 10
			vx = vx / 2
			ev.append({"t": "thud", "s": 2})
			return
		vy = 0
		vx = 0
		ev.append({"t": "thud", "s": 1})
		if state == KO:
			return
		if fall_kd:
			set_state(LIE)
		else:
			set_state(LAND)
			land_len = 8
		return
	var was_attack := is_air_move()
	vy = 0
	vx = 0
	set_state(LAND)
	land_len = 5 if was_attack else 3
	ev.append({"t": "land"})
