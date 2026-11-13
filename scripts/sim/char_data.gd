class_name CharData
## Per-character stats and frame data. All distances in pixels, times in frames (60/s).
## Boxes are [x, y, w, h]: x forward from the feet, y up from the feet (or from
## the fighter's current height when airborne).

enum Guard { MID, LOW, HIGH }

static var _cache := {}


static func get_data(id: String) -> Dictionary:
	if not _cache.has(id):
		_cache[id] = _ced() if id == "ced" else _kros()
	return _cache[id]


static func _mv(startup: int, active: int, recovery: int, damage: int, hitstun: int,
		blockstun: int, box: Array, guard := Guard.MID, extra := {}) -> Dictionary:
	var strength := 0
	if damage >= 50: strength = 1
	if damage >= 85: strength = 2
	var m := {
		"startup": startup, "active": active, "recovery": recovery,
		"damage": damage, "hitstun": hitstun, "blockstun": blockstun,
		"box": box, "guard": guard, "strength": strength,
		"hitstop": [9, 11, 14][strength],
		"push_hit": [5, 6, 8][strength], "push_block": [6, 7, 9][strength],
		"cancel": strength == 0, "kd": false, "step": [],
	}
	m.merge(extra, true)
	return m


static func _ced() -> Dictionary:
	var G := Guard
	return {
		"id": "ced", "name": "CED",
		"health": 1000,
		"walk_f": 250, "walk_b": 200,           # subpixels per frame (100 = 1 px)
		"jump_vy": 950, "jump_vx": 300, "gravity": 52,
		"push_w": 13,
		"hurt_stand": [-14, 0, 28, 98], "hurt_crouch": [-16, 0, 32, 62], "hurt_air": [-13, 12, 26, 76],
		"moves": {
			"st_lp": _mv(4, 2, 6, 30, 13, 10, [12, 72, 26, 12]),
			"st_mp": _mv(6, 3, 11, 60, 17, 14, [14, 70, 32, 14]),
			"st_hp": _mv(8, 4, 20, 100, 22, 17, [14, 64, 36, 20], G.MID, {"step": [2, 8, 220]}),
			"st_lk": _mv(5, 3, 8, 35, 13, 10, [10, 22, 32, 14]),
			"st_mk": _mv(7, 4, 14, 65, 17, 14, [12, 44, 38, 16]),
			"st_hk": _mv(10, 4, 22, 110, 22, 17, [12, 68, 40, 20]),
			"cr_lp": _mv(4, 2, 6, 25, 12, 10, [12, 42, 26, 10]),
			"cr_mp": _mv(6, 3, 11, 55, 16, 13, [12, 40, 32, 12]),
			"cr_hp": _mv(7, 5, 22, 95, 22, 16, [2, 44, 28, 56], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 8, 25, 12, 10, [10, 0, 32, 10], G.LOW),
			"cr_mk": _mv(7, 3, 14, 55, 16, 13, [10, 0, 42, 12], G.LOW),
			"cr_hk": _mv(9, 3, 24, 90, 22, 16, [10, 0, 50, 12], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 35, 16, 12, [6, 36, 26, 18], G.HIGH),
			"j_mp": _mv(6, 6, 0, 65, 19, 15, [6, 30, 30, 20], G.HIGH),
			"j_hp": _mv(8, 5, 0, 100, 23, 17, [6, 22, 34, 26], G.HIGH),
			"j_lk": _mv(4, 10, 0, 35, 16, 12, [6, 10, 28, 16], G.HIGH),
			"j_mk": _mv(6, 6, 0, 65, 19, 15, [8, 6, 34, 18], G.HIGH),
			"j_hk": _mv(8, 6, 0, 105, 23, 17, [8, 2, 40, 20], G.HIGH),
			# Flying knee (Mixamo animation): runs in, jumps, knee to the face, then a
			# hammer punch on the way down (overhead, knocks down). Path from tools/mixamo_move.py.
			"flying_knee": _mv(20, 26, 21, 90, 24, 18, [8, 4, 34, 60], G.HIGH, {
				"path": MovePaths.DATA["ced/flying_knee"],
				"hits": [
					_mv(20, 8, 0, 50, 30, 18, [6, 46, 30, 30], G.HIGH),
					_mv(36, 10, 0, 90, 24, 18, [8, 4, 34, 60], G.HIGH, {"kd": true}),
				],
			}),
		},
		# down, down-forward, forward + any punch
		"specials": [{"motion": "qcf", "buttons": [2, 1, 0], "move": "flying_knee"}],
	}


static func _kros() -> Dictionary:
	var G := Guard
	return {
		"id": "kros", "name": "KROS",
		"health": 1000,
		"walk_f": 220, "walk_b": 190,
		"jump_vy": 980, "jump_vx": 280, "gravity": 50,
		"push_w": 14,
		"hurt_stand": [-15, 0, 30, 102], "hurt_crouch": [-17, 0, 34, 64], "hurt_air": [-14, 12, 28, 78],
		"moves": {
			# Longer reach (claws, long legs), a little slower than Ced.
			"st_lp": _mv(4, 3, 7, 30, 13, 10, [12, 74, 32, 12]),
			"st_mp": _mv(7, 3, 12, 60, 17, 14, [14, 70, 38, 16]),
			"st_hp": _mv(9, 4, 22, 105, 22, 17, [16, 60, 42, 26]),
			"st_lk": _mv(5, 3, 9, 35, 13, 10, [10, 20, 36, 14]),
			"st_mk": _mv(8, 4, 15, 65, 17, 14, [12, 46, 44, 16]),
			"st_hk": _mv(11, 5, 23, 115, 22, 17, [12, 70, 46, 22], G.MID, {"step": [3, 10, 180]}),
			"cr_lp": _mv(5, 2, 7, 25, 12, 10, [12, 42, 30, 10]),
			"cr_mp": _mv(7, 3, 12, 55, 16, 13, [12, 38, 38, 14]),
			"cr_hp": _mv(8, 5, 23, 95, 22, 16, [4, 46, 32, 58], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 9, 25, 12, 10, [10, 0, 36, 10], G.LOW),
			"cr_mk": _mv(8, 3, 15, 55, 16, 13, [10, 0, 48, 12], G.LOW),
			"cr_hk": _mv(10, 4, 25, 95, 22, 16, [10, 0, 56, 12], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 35, 16, 12, [6, 34, 30, 18], G.HIGH),
			"j_mp": _mv(7, 6, 0, 65, 19, 15, [6, 28, 34, 22], G.HIGH),
			"j_hp": _mv(9, 5, 0, 105, 23, 17, [6, 18, 38, 28], G.HIGH),
			"j_lk": _mv(4, 10, 0, 35, 16, 12, [6, 8, 32, 16], G.HIGH),
			"j_mk": _mv(7, 6, 0, 65, 19, 15, [8, 4, 38, 18], G.HIGH),
			"j_hk": _mv(9, 6, 0, 110, 23, 17, [8, 0, 44, 22], G.HIGH),
		},
	}
