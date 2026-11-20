class_name CharData
## Per-character stats and frame data. All distances in pixels, times in frames (60/s).
## Sprite heights (Street Fighter scale on a 216 px screen): CED 92 px, KROS 97 px,
## MURFURRIE 94 px, SHORTY 50 px.
## Boxes are [x, y, w, h]: x forward from the feet, y up from the feet (or from
## the fighter's current height when airborne).
##
## Character differences (keep these when tuning):
##   reach (hit box length)  KROS longest   CED middle      MURFURRIE shortest
##   punch damage            KROS strongest MURFURRIE mid   CED weakest
##   kick damage             CED strongest  MURFURRIE mid   KROS weakest
##   speed (walk, jump)      CED fastest    MURFURRIE mid   KROS slowest
##   specials                CED Flying Knee, MURFURRIE Spit (projectile that drops halfway)
##   SHORTY: half size (50 px), fastest, takes 110% damage; punch buttons = slow heavy
##   headbutts, kick buttons = quick weak punches that hit low (see _shorty()).

enum Guard { MID, LOW, HIGH }

static var _cache := {}


static func get_data(id: String) -> Dictionary:
	if not _cache.has(id):
		match id:
			"ced": _cache[id] = _ced()
			"murfurrie": _cache[id] = _murfurrie()
			"shorty": _cache[id] = _shorty()
			_: _cache[id] = _kros()
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
		"walk_f": 325, "walk_b": 265,           # subpixels per frame (100 = 1 px)
		"jump_vy": 1100, "jump_vx": 390, "gravity": 66,
		"push_w": 11,
		"hurt_stand": [-11, 0, 23, 80], "hurt_crouch": [-13, 0, 26, 50], "hurt_air": [-11, 10, 21, 62],
		"moves": {
			# Weakest punches, strongest kicks, medium reach.
			"st_lp": _mv(4, 2, 5, 28, 13, 10, [10, 59, 21, 10]),
			"st_mp": _mv(5, 3, 8, 56, 17, 14, [11, 57, 26, 11]),
			"st_hp": _mv(7, 4, 15, 95, 22, 17, [11, 52, 29, 16], G.MID, {"step": [2, 8, 220]}),
			"st_lk": _mv(5, 3, 6, 40, 13, 10, [8, 18, 26, 11]),
			"st_mk": _mv(6, 4, 10, 72, 17, 14, [10, 36, 31, 13]),
			"st_hk": _mv(9, 4, 16, 118, 22, 17, [10, 55, 33, 16]),
			"cr_lp": _mv(4, 2, 5, 23, 12, 10, [10, 34, 21, 8]),
			"cr_mp": _mv(5, 3, 8, 52, 16, 13, [10, 33, 26, 10]),
			"cr_hp": _mv(6, 5, 20, 90, 22, 16, [2, 36, 23, 46], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 6, 30, 12, 10, [8, 0, 26, 8], G.LOW),
			"cr_mk": _mv(6, 3, 10, 62, 16, 13, [8, 0, 34, 10], G.LOW),
			# Sweep: a few px shorter than the sprite foot so Kros (long reach) outranges it; 7 frames
			# to come out like st_hp. Win rate is very sensitive to sweep startup and reach.
			"cr_hk": _mv(7, 3, 23, 98, 22, 16, [8, 0, 54, 10], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 33, 16, 12, [5, 29, 21, 15], G.HIGH),
			"j_mp": _mv(5, 6, 0, 62, 19, 15, [5, 24, 24, 16], G.HIGH),
			"j_hp": _mv(7, 5, 0, 97, 23, 17, [5, 18, 28, 21], G.HIGH),
			"j_lk": _mv(4, 10, 0, 40, 16, 12, [5, 8, 23, 13], G.HIGH),
			"j_mk": _mv(5, 6, 0, 72, 19, 15, [7, 5, 28, 15], G.HIGH),
			"j_hk": _mv(7, 6, 0, 112, 23, 17, [7, 2, 33, 16], G.HIGH),
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
		# down, down-forward, forward + any punch. "range": distances (px) the CPU uses it from.
		"specials": [{"motion": "qcf", "buttons": [2, 1, 0], "move": "flying_knee", "range": [70, 140]}],
	}


static func _kros() -> Dictionary:
	var G := Guard
	return {
		"id": "kros", "name": "KROS",
		"health": 1000,
		"walk_f": 280, "walk_b": 230,
		"jump_vy": 1120, "jump_vx": 345, "gravity": 66,
		"push_w": 12,
		"hurt_stand": [-13, 0, 26, 90], "hurt_crouch": [-15, 0, 30, 56], "hurt_air": [-12, 11, 25, 69],
		"moves": {
			# Longest reach (claws, long legs), strongest punches, weakest kicks, slowest.
			"st_lp": _mv(4, 3, 5, 36, 13, 10, [11, 65, 28, 11]),
			"st_mp": _mv(6, 3, 9, 70, 17, 14, [12, 62, 34, 14]),
			# Heavies reach down to y 48 so they hit a crouching Ced (crouch hurtbox is 50 tall).
			"st_hp": _mv(8, 4, 16, 115, 22, 17, [14, 48, 37, 28]),
			"st_lk": _mv(5, 3, 7, 30, 13, 10, [9, 18, 32, 12]),
			"st_mk": _mv(7, 4, 11, 60, 17, 14, [11, 41, 39, 14]),
			"st_hk": _mv(10, 5, 17, 102, 22, 17, [11, 48, 41, 33], G.MID, {"step": [3, 10, 180]}),
			"cr_lp": _mv(5, 2, 5, 30, 12, 10, [11, 37, 26, 9]),
			"cr_mp": _mv(6, 3, 9, 64, 16, 13, [11, 34, 34, 12]),
			"cr_hp": _mv(7, 5, 21, 105, 22, 16, [4, 41, 28, 51], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 7, 22, 12, 10, [9, 0, 32, 9], G.LOW),
			"cr_mk": _mv(7, 3, 11, 50, 16, 13, [9, 0, 42, 11], G.LOW),
			"cr_hk": _mv(7, 4, 23, 86, 22, 16, [9, 0, 58, 11], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 40, 16, 12, [5, 30, 26, 16], G.HIGH),
			"j_mp": _mv(6, 6, 0, 74, 19, 15, [5, 25, 30, 19], G.HIGH),
			"j_hp": _mv(8, 5, 0, 115, 23, 17, [5, 16, 34, 25], G.HIGH),
			"j_lk": _mv(4, 10, 0, 32, 16, 12, [5, 7, 28, 14], G.HIGH),
			"j_mk": _mv(6, 6, 0, 60, 19, 15, [7, 4, 34, 16], G.HIGH),
			"j_hk": _mv(8, 6, 0, 100, 23, 17, [7, 0, 39, 19], G.HIGH),
		},
	}


static func _murfurrie() -> Dictionary:
	var G := Guard
	return {
		"id": "murfurrie", "name": "MURFURRIE",
		"health": 1080,
		"walk_f": 305, "walk_b": 250,
		"jump_vy": 1090, "jump_vx": 365, "gravity": 66,
		"push_w": 12,
		"hurt_stand": [-12, 0, 24, 83], "hurt_crouch": [-14, 0, 27, 52], "hurt_air": [-11, 10, 23, 64],
		"moves": {
			# Angry brawler in a suit: shortest reach, medium punches and kicks, medium speed,
			# and a spit that makes up for the short arms.
			"st_lp": _mv(4, 2, 6, 32, 13, 10, [10, 61, 18, 10]),
			"st_mp": _mv(6, 3, 8, 63, 17, 14, [11, 58, 23, 12]),
			# Straight right at head height, steps in (misses crouchers).
			"st_hp": _mv(8, 4, 16, 105, 22, 17, [14, 60, 23, 17], G.MID, {"step": [2, 9, 200]}),
			"st_lk": _mv(5, 3, 7, 35, 13, 10, [8, 18, 23, 11]),
			"st_mk": _mv(7, 4, 10, 66, 17, 14, [10, 37, 28, 13]),
			"st_hk": _mv(10, 4, 17, 110, 22, 17, [10, 54, 30, 17]),
			"cr_lp": _mv(4, 2, 6, 27, 12, 10, [10, 35, 18, 8]),
			"cr_mp": _mv(6, 3, 8, 58, 16, 13, [10, 34, 23, 10]),
			"cr_hp": _mv(7, 5, 21, 98, 22, 16, [3, 37, 20, 47], G.MID, {"kd": true}),
			"cr_lk": _mv(5, 3, 7, 26, 12, 10, [8, 0, 23, 8], G.LOW),
			"cr_mk": _mv(7, 3, 10, 56, 16, 13, [8, 0, 31, 10], G.LOW),
			"cr_hk": _mv(7, 3, 24, 92, 22, 16, [8, 0, 50, 10], G.LOW, {"kd": true}),
			"j_lp": _mv(4, 8, 0, 37, 16, 12, [5, 29, 19, 15], G.HIGH),
			"j_mp": _mv(5, 6, 0, 68, 19, 15, [5, 24, 22, 17], G.HIGH),
			"j_hp": _mv(8, 5, 0, 107, 23, 17, [5, 17, 26, 22], G.HIGH),
			"j_lk": _mv(4, 10, 0, 36, 16, 12, [5, 8, 21, 13], G.HIGH),
			"j_mk": _mv(6, 6, 0, 66, 19, 15, [7, 5, 26, 15], G.HIGH),
			"j_hk": _mv(8, 6, 0, 106, 23, 17, [7, 1, 31, 17], G.HIGH),
			# Spit: a projectile like a fireball that flies straight from his mouth, then drops
			# to the floor about halfway across the screen. No hit box of its own ("proj" spawns
			# on the first active frame). proj: spawn point [x, y] px from the feet, speed vx
			# (1/100 px per frame), frames it flies level ("float"), then gravity per frame, size.
			"spit": _mv(13, 4, 26, 60, 18, 14, [0, 0, 0, 0], G.MID, {"proj": {
				"x": 26, "y": 72, "vx": 420, "float": 20, "grav": 34, "w": 10, "h": 7,
			}}),
		},
		"specials": [{"motion": "qcf", "buttons": [2, 1, 0], "move": "spit", "range": [90, 200]}],
	}


static func _shorty() -> Dictionary:
	var G := Guard
	return {
		"id": "shorty", "name": "SHORTY",
		# About half the others' height (50 px). The fastest fighter, but he takes extra damage.
		# His buttons are swapped: the PUNCH buttons are headbutts (slow, heavy, blocked like
		# punches) and the KICK buttons are his punches (very quick, weak, hit low like kicks:
		# block them crouching). Moves keep their button names (st_lp = standing light headbutt).
		"health": 1000,
		"dmg_taken": 110,                      # percent of the damage other fighters take
		"walk_f": 355, "walk_b": 295,
		"jump_vy": 1000, "jump_vx": 410, "gravity": 66,
		"push_w": 8,
		"push_box": [48, 32, 8, 42],           # push heights: standing, crouching, airborne bottom/top
		"hurt_stand": [-8, 0, 16, 48], "hurt_crouch": [-9, 0, 18, 32], "hurt_air": [-8, 6, 16, 36],
		"showcase": true,                      # round 1 starts with his intro (the two ladies)
		"moves": {
			# Headbutts (punch buttons): slow, heavy, at his head height (the opponent's belly).
			# Each lunges forward (he is tiny: it's how he gets in).
			"st_lp": _mv(8, 3, 12, 60, 16, 13, [8, 38, 16, 12], G.MID, {"step": [2, 8, 250]}),
			"st_mp": _mv(12, 4, 16, 95, 22, 17, [9, 36, 18, 14], G.MID, {"step": [3, 12, 300]}),
			# Slow to come out, but he recovers fast enough that a blocked one is only just unsafe.
			"st_hp": _mv(16, 5, 15, 140, 26, 18, [10, 34, 22, 16], G.MID, {"step": [4, 17, 340]}),
			"cr_lp": _mv(8, 3, 12, 55, 16, 13, [8, 22, 16, 12], G.MID, {"step": [2, 8, 220]}),
			"cr_mp": _mv(12, 4, 13, 90, 20, 16, [8, 20, 18, 14], G.MID, {"step": [3, 12, 260]}),
			# Rising headbutt: the anti-air, knocks down.
			"cr_hp": _mv(14, 5, 24, 130, 24, 18, [2, 26, 18, 30], G.MID, {"kd": true}),
			"j_lp": _mv(6, 8, 0, 60, 18, 14, [4, 10, 16, 14], G.HIGH),
			"j_mp": _mv(9, 6, 0, 95, 21, 16, [4, 6, 18, 16], G.HIGH),
			"j_hp": _mv(12, 6, 0, 140, 25, 18, [4, 2, 22, 18], G.HIGH),
			# Punches (kick buttons): very quick and weak, at the opponent's knees: block low.
			"st_lk": _mv(3, 2, 4, 20, 11, 9, [8, 22, 20, 8], G.LOW),
			"st_mk": _mv(4, 2, 6, 32, 13, 10, [8, 20, 24, 9], G.LOW),
			# heavy punches dart forward: how he gets back at a long sweep
			"st_hk": _mv(5, 3, 8, 45, 15, 12, [9, 20, 28, 10], G.LOW, {"step": [1, 6, 500]}),
			"cr_lk": _mv(3, 2, 4, 18, 10, 8, [8, 4, 20, 8], G.LOW),
			"cr_mk": _mv(4, 2, 6, 28, 12, 10, [8, 3, 24, 9], G.LOW),
			"cr_hk": _mv(5, 3, 12, 42, 16, 12, [8, 2, 30, 10], G.LOW, {"kd": true, "step": [1, 6, 550]}),
			"j_lk": _mv(3, 8, 0, 22, 13, 10, [5, 10, 18, 10], G.HIGH),
			"j_mk": _mv(4, 6, 0, 32, 15, 12, [5, 8, 21, 11], G.HIGH),
			"j_hk": _mv(5, 6, 0, 45, 17, 13, [5, 6, 24, 12], G.HIGH),
		},
	}
