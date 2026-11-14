extends Node
## Global state: input map, match setup, command-line test options.

const CHARACTERS := ["ced", "kros"]

var p1_char := "ced"
var p2_char := "kros"
var p1_cpu := false
var p2_cpu := true   # false = local 2 players
var cpu_level := 1  # 0 easy, 1 normal, 2 hard
var hi_score := 100000

# Command-line test options (pass after "--", e.g. -- --demo --shot=out.png --frames=300)
var opt := {}
var auto_started := false   # the --host/--join test hook already ran
var auto_matches := 0       # --autoplay: matches finished so far


func _ready() -> void:
	_setup_input()
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			opt[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			opt[s] = "1"


## Test hook: append one JSON line to the --result file.
func auto_report(d: Dictionary) -> void:
	if not opt.has("result"):
		return
	var path: String = opt["result"]
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(JSON.stringify(d))


func _key(action: String, keycode: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)


func _pad_button(action: String, device: int, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = button
	InputMap.action_add_event(action, e)


func _pad_axis(action: String, device: int, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)


func _add(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.4)


func _setup_input() -> void:
	var names := ["up", "down", "left", "right", "lp", "mp", "hp", "lk", "mk", "hk"]
	for p in ["p1", "p2"]:
		for n in names:
			_add(p + "_" + n)
	# Player 1 keyboard: arrows + ASD (punches) / ZXC (kicks)
	_key("p1_up", KEY_UP)
	_key("p1_down", KEY_DOWN)
	_key("p1_left", KEY_LEFT)
	_key("p1_right", KEY_RIGHT)
	_key("p1_lp", KEY_A)
	_key("p1_mp", KEY_S)
	_key("p1_hp", KEY_D)
	_key("p1_lk", KEY_Z)
	_key("p1_mk", KEY_X)
	_key("p1_hk", KEY_C)
	# Player 2 keyboard: IJKL + numpad 4 5 6 (punches) / 1 2 3 (kicks)
	_key("p2_up", KEY_I)
	_key("p2_down", KEY_K)
	_key("p2_left", KEY_J)
	_key("p2_right", KEY_L)
	_key("p2_lp", KEY_KP_4)
	_key("p2_mp", KEY_KP_5)
	_key("p2_hp", KEY_KP_6)
	_key("p2_lk", KEY_KP_1)
	_key("p2_mk", KEY_KP_2)
	_key("p2_hk", KEY_KP_3)
	# Gamepads (device 0 -> P1, device 1 -> P2), 6-button layout: X Y RB / A B RT
	for d in 2:
		var p := "p%d" % (d + 1)
		_pad_button(p + "_up", d, JOY_BUTTON_DPAD_UP)
		_pad_button(p + "_down", d, JOY_BUTTON_DPAD_DOWN)
		_pad_button(p + "_left", d, JOY_BUTTON_DPAD_LEFT)
		_pad_button(p + "_right", d, JOY_BUTTON_DPAD_RIGHT)
		_pad_axis(p + "_up", d, JOY_AXIS_LEFT_Y, -1.0)
		_pad_axis(p + "_down", d, JOY_AXIS_LEFT_Y, 1.0)
		_pad_axis(p + "_left", d, JOY_AXIS_LEFT_X, -1.0)
		_pad_axis(p + "_right", d, JOY_AXIS_LEFT_X, 1.0)
		_pad_button(p + "_lp", d, JOY_BUTTON_X)
		_pad_button(p + "_mp", d, JOY_BUTTON_Y)
		_pad_button(p + "_hp", d, JOY_BUTTON_RIGHT_SHOULDER)
		_pad_button(p + "_lk", d, JOY_BUTTON_A)
		_pad_button(p + "_mk", d, JOY_BUTTON_B)
		_pad_axis(p + "_hk", d, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	# Menus
	_add("menu_ok")
	_key("menu_ok", KEY_ENTER)
	_key("menu_ok", KEY_KP_ENTER)
	_key("menu_ok", KEY_SPACE)
	_key("menu_ok", KEY_A)
	_pad_button("menu_ok", 0, JOY_BUTTON_A)
	_pad_button("menu_ok", 0, JOY_BUTTON_START)
	_add("menu_back")
	_key("menu_back", KEY_ESCAPE)
	_key("menu_back", KEY_BACKSPACE)
	_pad_button("menu_back", 0, JOY_BUTTON_B)
	_pad_button("menu_back", 0, JOY_BUTTON_BACK)
	_add("menu_pause")
	_key("menu_pause", KEY_ESCAPE)
	_key("menu_pause", KEY_P)
	_pad_button("menu_pause", 0, JOY_BUTTON_START)
	_pad_button("menu_pause", 1, JOY_BUTTON_START)
	_add("toggle_fullscreen")
	_key("toggle_fullscreen", KEY_F11)
	_add("toggle_boxes")
	_key("toggle_boxes", KEY_F2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN
