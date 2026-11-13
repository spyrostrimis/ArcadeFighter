class_name Inp
## Input bitmask shared by players, CPU and (later) netplay.
## Directions are raw screen directions; the sim converts them to forward/back.

const UP := 1
const DOWN := 2
const LEFT := 4
const RIGHT := 8
const LP := 16
const MP := 32
const HP := 64
const LK := 128
const MK := 256
const HK := 512

const BUTTONS := [LP, MP, HP, LK, MK, HK]
const BUTTON_NAMES := ["lp", "mp", "hp", "lk", "mk", "hk"]


## Reads keyboard/gamepad state for a player slot ("p1" or "p2").
static func read_local(prefix: String) -> int:
	var b := 0
	if Input.is_action_pressed(prefix + "_up"): b |= UP
	if Input.is_action_pressed(prefix + "_down"): b |= DOWN
	if Input.is_action_pressed(prefix + "_left"): b |= LEFT
	if Input.is_action_pressed(prefix + "_right"): b |= RIGHT
	for i in BUTTONS.size():
		if Input.is_action_pressed(prefix + "_" + BUTTON_NAMES[i]):
			b |= BUTTONS[i]
	# Opposite directions cancel (SOCD neutral).
	if (b & LEFT) and (b & RIGHT): b &= ~(LEFT | RIGHT)
	if (b & UP) and (b & DOWN): b &= ~UP
	return b
