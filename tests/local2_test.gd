extends SceneTree
## Headless check of local 2 players through the real keyboard path:
## title -> 2 PLAYERS -> both pick with their own keys -> fight with two humans,
## then P2's keys (IJKL + numpad) must move and attack with fighter 2.
## Run: godot --headless --path . --script res://tests/local2_test.gd

var main: Node
var frame := 0
var step := 0
var wait := 0
var fails: Array[String] = []
var x0 := 0


func _initialize() -> void:
	root.get_node("Settings").use_defaults("user://test_settings.cfg")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _tap(k: Key) -> void:
	_key(k, true)
	_key(k, false)


func _screen() -> Node:
	return main.get("current")


## Class names via the script, so this file compiles before the autoloads exist.
func _is(n: Node, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _physics_process(_delta: float) -> bool:
	frame += 1
	if wait > 0:
		wait -= 1
		return false
	var s := _screen()
	if frame > 2000:
		print("local2_test: TIMEOUT at step ", step)
		quit(2)
		return true
	match step:
		0:   # title: down to "2 PLAYERS", confirm
			_check(_is(s, "TitleScreen"), "starts on title")
			_tap(KEY_DOWN)
			wait = 2
		1:
			_tap(KEY_ENTER)
			wait = 3
		2:
			_check(_is(s, "SelectScreen"), "2 PLAYERS opens select")
			_check(_is(s, "SelectScreen") and s.local2, "select is in 2-player mode")
			_tap(KEY_J)        # P2 cursor left (KROS -> CED, any roster size)
			wait = 2
		3:
			_check(s.cursor[1] == 0, "P2 cursor moves with J (got %d)" % s.cursor[1])
			_tap(KEY_KP_4)     # P2 picks
			wait = 2
		4:
			_check(s.picked[1] and not s.picked[0], "P2 picks with numpad 4, P1 not yet")
			_tap(KEY_KP_2)     # P2 un-picks
			wait = 2
		5:
			_check(not s.picked[1], "P2 cancels with numpad 2")
			_tap(KEY_KP_1)
			wait = 2
		6:
			_tap(KEY_A)        # P1 picks
			wait = 3
		7:
			_check(s.stage == 2, "both picked -> VS splash")
			var g := root.get_node("Game")
			_check(g.p1_char == "ced" and g.p2_char == "ced", "mirror match chosen (%s vs %s)" % [g.p1_char, g.p2_char])
			wait = 130
		8:
			_check(_is(s, "FightScreen"), "VS splash -> fight")
			_check(_is(s, "FightScreen") and s.cpus[0] == null and s.cpus[1] == null, "no CPU in 2 players")
			wait = 200   # past ROUND 1 / FIGHT
		9:
			x0 = s.sim.f[1].x
			_key(KEY_J, true)   # P2 walks toward P1 (P2 starts on the right)
			wait = 30
		10:
			_key(KEY_J, false)
			_check(s.sim.f[1].x < x0, "P2 walks left with J (%d -> %d)" % [x0, s.sim.f[1].x])
			_key(KEY_KP_6, true)
			wait = 3
		11:
			_key(KEY_KP_6, false)
			_check(s.sim.f[1].state == Fighter.ATTACK, "P2 attacks with numpad 6")
			_check(s.sim.f[0].state != Fighter.ATTACK, "P1 did not attack")
			for m in fails:
				print("FAIL: ", m)
			print("local2_test: ", "OK" if fails.is_empty() else "%d failure(s)" % fails.size())
			quit(0 if fails.is_empty() else 1)
			return true
	step += 1
	return false
