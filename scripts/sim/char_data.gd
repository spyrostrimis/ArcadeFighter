class_name CharData
## Per-character stats and frame data. All distances in pixels, times in frames (60/s).
## Sprite heights (Street Fighter scale on a 216 px screen): CED 92 px, KROS 97 px.
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
		"walk_f": 320, "walk_b": 260,           # subpixels per frame (100 = 1 px)
		"jump_vy": 1100, "jump_vx": 380, "gravity": 66,
		"push_w": 11,
		"hurt_stand": [-11, 0, 23, 80], "hurt_crouch": [-13, 0, 26, 50], "hurt_air": [-11, 10, 21, 62],
		"moves": {
			"st_lp": _mv(4, 2, 5, 30, 13, 10, [10, 59, 21, 10]),
			"st_mp": _mv(5, 3, 8, 60, 17, 14, [11, 57, 26, 11]),
			"st_hp": _mv(7, 4, 15, 100, 22, 17, [11, 52, 29, 16], G.MID, {"step": [2, 8, 220]}),
			"st_lk": _mv(5, 3, 6, 35, 13, 10, [8, 18, 26, 11]),
			"st_mk": _mv(6, 4, 10, 65, 17, 14, [10, 36, 31, 13]),
			"st_hk": _mv(9, 4, 16, 110, 22, 17, [10, 55, 33, 16]),
			"cr_lp": _mv(4, 2, 5, 25, 12, 10, [10, 34, 21, 8]),
			"cr_mp": _mv(5, 3, 8, 55, 16, 13, [10, 33, 26, 10]),
			"cr_hp": _mv(6, 5, 20, 95, 22, 16, [2, 36, 23, 46], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 6, 25, 12, 10, [8, 0, 26, 8], G.LOW),
			"cr_mk": _mv(6, 3, 10, 55, 16, 13, [8, 0, 34, 10], G.LOW),
			"cr_hk": _mv(8, 3, 22, 90, 22, 16, [8, 0, 58, 10], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 35, 16, 12, [5, 29, 21, 15], G.HIGH),
			"j_mp": _mv(5, 6, 0, 65, 19, 15, [5, 24, 24, 16], G.HIGH),
			"j_hp": _mv(7, 5, 0, 100, 23, 17, [5, 18, 28, 21], G.HIGH),
			"j_lk": _mv(4, 10, 0, 35, 16, 12, [5, 8, 23, 13], G.HIGH),
			"j_mk": _mv(5, 6, 0, 65, 19, 15, [7, 5, 28, 15], G.HIGH),
			"j_hk": _mv(7, 6, 0, 105, 23, 17, [7, 2, 33, 16], G.HIGH),
			# Flying knee (Mixamo animation): runs in, jumps, knee to the face, then a
			# hammer punch on the way down (overhead, knocks down). Path from tools/mixamo_move.py.
			"flying_knee": _mv(20, 26, 21, 90, 24, 18, [7, 3, 28, 49], G.HIGH, {
				"path": MovePaths.DATA["ced/flying_knee"],
				"hits": [
					_mv(20, 8, 0, 50, 30, 18, [5, 37, 24, 24], G.HIGH),
					_mv(36, 10, 0, 90, 24, 18, [7, 3, 28, 49], G.HIGH, {"kd": true}),
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
		"walk_f": 290, "walk_b": 240,
		"jump_vy": 1120, "jump_vx": 360, "gravity": 66,
		"push_w": 12,
		"hurt_stand": [-13, 0, 26, 90], "hurt_crouch": [-15, 0, 30, 56], "hurt_air": [-12, 11, 25, 69],
		"moves": {
			# Longer reach (claws, long legs), a little slower than Ced.
			"st_lp": _mv(4, 3, 5, 30, 13, 10, [11, 65, 28, 11]),
			"st_mp": _mv(6, 3, 9, 60, 17, 14, [12, 62, 34, 14]),
			"st_hp": _mv(8, 4, 16, 105, 22, 17, [14, 53, 37, 23]),
			"st_lk": _mv(5, 3, 7, 35, 13, 10, [9, 18, 32, 12]),
			"st_mk": _mv(7, 4, 11, 65, 17, 14, [11, 41, 39, 14]),
			"st_hk": _mv(10, 5, 17, 115, 22, 17, [11, 62, 41, 19], G.MID, {"step": [3, 10, 180]}),
			"cr_lp": _mv(5, 2, 5, 25, 12, 10, [11, 37, 26, 9]),
			"cr_mp": _mv(6, 3, 9, 55, 16, 13, [11, 34, 34, 12]),
			"cr_hp": _mv(7, 5, 21, 95, 22, 16, [4, 41, 28, 51], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 7, 25, 12, 10, [9, 0, 32, 9], G.LOW),
			"cr_mk": _mv(7, 3, 11, 55, 16, 13, [9, 0, 42, 11], G.LOW),
			"cr_hk": _mv(9, 4, 23, 95, 22, 16, [9, 0, 52, 11], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 35, 16, 12, [5, 30, 26, 16], G.HIGH),
			"j_mp": _mv(6, 6, 0, 65, 19, 15, [5, 25, 30, 19], G.HIGH),
			"j_hp": _mv(8, 5, 0, 105, 23, 17, [5, 16, 34, 25], G.HIGH),
			"j_lk": _mv(4, 10, 0, 35, 16, 12, [5, 7, 28, 14], G.HIGH),
			"j_mk": _mv(6, 6, 0, 65, 19, 15, [7, 4, 34, 16], G.HIGH),
			"j_hk": _mv(8, 6, 0, 110, 23, 17, [7, 0, 39, 19], G.HIGH),
		},
	}
