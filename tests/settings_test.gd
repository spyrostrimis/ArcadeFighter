extends SceneTree
## Headless check of the settings screen through real key presses:
## title -> SETTINGS, music volume down, P1 light punch rebound to Q (and back to A by
## swapping), rounds/time/training reach the match, values survive a save + load.
## Uses user://test_settings.cfg, so the player's own settings are not touched.
## Run: godot --headless --path . --script res://tests/settings_test.gd

const TEST_PATH := "user://test_settings.cfg"
var main: Node
var st: Node
var step := 0
var wait := 0
var frame := 0
var fails: Array[String] = []


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	st = root.get_node("Settings")
	st.use_defaults(TEST_PATH)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _tap(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)


func _is(n: Node, cls: String) -> bool:
	return n != null and n.get_script() != null and n.get_script().get_global_name() == cls


func _check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)


func _key_for(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return int((e as InputEventKey).physical_keycode)
	return 0


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame > 3000:
		print("settings_test: TIMEOUT at step ", step)
		quit(2)
		return true
	if wait > 0:
		wait -= 1
		return false
	var s: Node = main.get("current")
	var seq := [
		func(): for i in 3: _tap(KEY_DOWN),                       # VS CPU -> SETTINGS
		func(): _tap(KEY_ENTER),
		func(): _check(_is(s, "SettingsScreen"), "SETTINGS opens the settings screen"); _tap(KEY_DOWN),   # MUSIC
		func(): _tap(KEY_LEFT); _tap(KEY_LEFT),
		func(): _check(int(st.v["music"]) == 4, "music volume 6 -> 4 (got %s)" % st.v["music"]),
		func(): _check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < -3.0, "Music bus got quieter"),
		func(): for i in 2: _tap(KEY_DOWN),                       # SOUND, P1 KEYS (headers are skipped)
		func(): _tap(KEY_ENTER),
		func(): _check(s.page == "p1", "P1 KEYS page opens"); for i in 4: _tap(KEY_DOWN),   # LIGHT PUNCH
		func(): _tap(KEY_ENTER),
		func(): _check(s.waiting == "p1_lp", "waiting for a key"); _tap(KEY_Q),
		func(): _check(_key_for("p1_lp") == KEY_Q, "P1 light punch is now Q"),
		func(): _tap(KEY_DOWN); _tap(KEY_ENTER),                    # MEDIUM PUNCH (S) -> Q: swap
		func(): _tap(KEY_Q),
		func(): _check(_key_for("p1_mp") == KEY_Q and _key_for("p1_lp") == KEY_S, "Q swapped: MP=Q, LP=S"),
		func(): _tap(KEY_ENTER),
		func(): _tap(KEY_ESCAPE),                                   # cancel the capture
		func(): _check(s.waiting == "" and _key_for("p1_mp") == KEY_Q, "ESC cancels key capture"),
		func(): _tap(KEY_UP); _tap(KEY_ENTER),
		func(): _tap(KEY_P),
		func(): _check(_key_for("p1_lp") == KEY_S, "reserved key P is refused"); _tap(KEY_ESCAPE),
		func(): _tap(KEY_ESCAPE),                                   # back to main page
		func(): _check(s.page == "", "ESC leaves the keys page"),
		func(): for i in 2: _tap(KEY_DOWN),                       # P2 KEYS, ROUNDS
		func(): _tap(KEY_LEFT),
		func(): _tap(KEY_DOWN); _tap(KEY_RIGHT),                    # ROUND TIME 99 -> NO LIMIT
		func(): _check(int(st.v["wins"]) == 1 and int(st.v["time"]) == 0, "rounds 1, no time limit"),
		func(): _tap(KEY_ESCAPE),                                   # leave -> saves
		func(): _check(_is(s, "TitleScreen"), "ESC goes back to the title"),
		func():
			var cf := ConfigFile.new()
			_check(cf.load(TEST_PATH) == OK, "settings file saved")
			_check(int(cf.get_value("keys", "p1_mp", 0)) == KEY_Q, "saved key binding")
			st.use_defaults()
			st._load()
			st.apply_all()
			_check(int(st.v["music"]) == 4 and _key_for("p1_mp") == KEY_Q, "settings load back"),
		func():
			var sim := MatchSim.new("ced", "kros", st.match_opts())
			_check(sim.wins_needed == 1 and sim.round_time == 0, "match uses the rounds/time settings")
			var tr := MatchSim.new("ced", "kros", {"training": true})
			for i in 1500:
				tr.step(0, 0)
			_check(tr.phase == MatchSim.FIGHT and tr.timer < 99, "training sim still runs normally")
			var dflt := MatchSim.new("ced", "kros")
			_check(dflt.wins_needed == 2 and dflt.round_time == 99, "defaults unchanged without opts"),
	]
	if step < seq.size():
		seq[step].call()
		step += 1
		wait = 3
		return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	for m in fails:
		print("FAIL: ", m)
	print("settings_test: ", "OK" if fails.is_empty() else "%d failure(s)" % fails.size())
	quit(0 if fails.is_empty() else 1)
	return true
